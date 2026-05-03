#!/usr/bin/perl

=pod

=head1 NAME

paused_input_close.t - Test that closing a paused input channel doesn't
corrupt _select_loop's paused-channel count.

=head1 DESCRIPTION

When an input channel is paused (waiting for more data from a callback)
and the callback signals EOF, the channel transitions from paused to closed.
Previously, the closed channel was still counted in the $paused tally,
which could cause premature loop exit via break_on_io or an unnecessary
timeout shortening.

=cut

use strict;
use warnings;

BEGIN {
    $|  = 1;
    $^W = 1;
    if ( $ENV{PERL_CORE} ) {
        chdir '../lib/IPC/Run' if -d '../lib/IPC/Run';
        unshift @INC, 'lib', '../..';
        $^X = '../../../t/' . $^X;
    }
}

use Test::More;
use IPC::Run::Debug qw( _map_fds );
use IPC::Run qw( start pump finish timeout );

if ( $^O eq 'MSWin32' ) {
    plan skip_all => "pump() callback timing unreliable on Win32";
}

plan tests => 7;

my @echoer = ( $^X, '-pe', 'BEGIN { $| = 1 }' );
my $fd_map = _map_fds;

## Test 1-3: callback that provides data, pauses, then closes.
## The paused→closed transition must not cause pump to misbehave.
{
    my @chunks = ( "hello\n", "world\n" );
    my $done = 0;

    # Callback: returns data on first two calls, empty string once
    # (which causes the channel to pause), then undef (EOF).
    my $cb = sub {
        return shift @chunks if @chunks;
        return undef if $done++;
        return '';    # pause: no data yet
    };

    my $out = '';
    my $h   = start \@echoer, $cb, \$out, timeout(10);

    # Pump until we see all output.  The callback will pause once
    # (returning '') and then close (returning undef) during the
    # unpausing check in _select_loop.
    pump $h until $out =~ /world/;

    $h->finish;

    my $nl = $^O eq 'MSWin32' ? "\r\n" : "\n";
    like( $out, qr/hello/, "got first chunk through paused→closed cycle" );
    like( $out, qr/world/, "got second chunk" );
    ok( !$h->pumpable, "harness finished cleanly" );
}

## Test 4-6: multiple pump() calls with callback that pauses repeatedly
## before finally closing.
{
    my $call_count = 0;
    my @data       = ( "line1\n", "line2\n", "line3\n" );

    # Alternate between providing data and pausing.
    # Sequence: data, pause, data, pause, data, pause, close.
    my $cb = sub {
        $call_count++;
        if ( @data && $call_count % 2 == 1 ) {
            return shift @data;
        }
        return undef unless @data;    # EOF after all data delivered
        return '';                    # pause
    };

    my $out = '';
    my $h   = start \@echoer, $cb, \$out, timeout(10);

    pump $h until $out =~ /line3/;

    $h->finish;

    like( $out, qr/line1/, "alternating pause/data: got line1" );
    like( $out, qr/line3/, "alternating pause/data: got line3" );
    ok( !$h->pumpable, "harness finished after alternating pauses" );
}

## Test 7: no file descriptor leak after paused-then-closed input
{
    my $sent = 0;
    my $cb   = sub {
        return "check\n" unless $sent++;
        return undef;
    };

    my $out = '';
    my $h   = start \@echoer, $cb, \$out, timeout(5);
    pump $h until $out =~ /check/;
    $h->finish;

    is( _map_fds, $fd_map, "no fd leak after paused→closed input" );
}
