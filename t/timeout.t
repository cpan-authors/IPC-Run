#!/usr/bin/perl

=pod

=head1 NAME

timeout.t - Test suite for IPC::Run timeouts

=cut

use strict;

BEGIN {
    $|  = 1;
    $^W = 1;
    if ( $ENV{PERL_CORE} ) {
        chdir '../lib/IPC/Run' if -d '../lib/IPC/Run';
        unshift @INC, 'lib', '../..';
        $^X = '../../../t/' . $^X;
    }
}

## Separate from run.t so run.t is not too slow.
use Test::More tests => 26;
use IPC::Run qw( harness timeout );

my $h;
my $t;
my $in;
my $out;
my $started;

$h = harness( [$^X], \$in, \$out, $t = timeout(1) );
ok( $h->isa('IPC::Run') );
ok( !!$t->is_reset );
ok( !$t->is_running );
ok( !$t->is_expired );
$started = time;
$h->start;
ok(1);
ok( !$t->is_reset );
ok( !!$t->is_running );
ok( !$t->is_expired );
$in = '';
eval { $h->pump };

# Older perls' Test.pms don't know what to do with qr//s
$@ =~ /IPC::Run: timeout/ ? ok(1) : is( $@, qr/IPC::Run: timeout/ );

SCOPE: {
    my $elapsed = time - $started;
    $elapsed >= 1 ? ok(1) : is( $elapsed, ">= 1" );
    is( $t->interval, 1 );
    ok( !$t->is_reset );
    ok( !$t->is_running );
    ok( !!$t->is_expired );

    ##
    ## Starting from an expired state
    ##
    $started = time;
    $h->start;
    ok(1);
    ok( !$t->is_reset );
    ok( !!$t->is_running );
    ok( !$t->is_expired );
    $in = '';
    eval { $h->pump };
    $@ =~ /IPC::Run: timeout/ ? ok(1) : is( $@, qr/IPC::Run: timeout/ );
    ok( !$t->is_reset );
    ok( !$t->is_running );
    ok( !!$t->is_expired );
}

SCOPE: {
    my $elapsed = time - $started;
    $elapsed >= 1 ? ok(1) : is( $elapsed, ">= 1" );
    $h = harness( [$^X], \$in, \$out, timeout(1) );
    $started = time;
    $h->start;
    $in = '';
    eval { $h->pump };
    $@ =~ /IPC::Run: timeout/ ? ok(1) : is( $@, qr/IPC::Run: timeout/ );
}

SCOPE: {
    my $elapsed = time - $started;
    $elapsed >= 1 ? ok(1) : is( $elapsed, ">= 1" );
}

{
    $h = harness( [ $^X, '-e', 'sleep 1' ], timeout(10), debug => 0 );
    my $started_at = time;
    $h->start;
    $h->finish;
    my $finished_at = time;
    ok( $finished_at - $started_at <= 2, 'not too slow to reap' )
      or diag( $finished_at - $started_at . " seconds passed" );
}
