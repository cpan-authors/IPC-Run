#!/usr/bin/perl

=pod

=head1 NAME

close_stdin.t - Test suite for IPC::Run::close_stdin

=head1 DESCRIPTION

Tests the close_stdin() method which allows users to close the child's
stdin pipe while continuing to drain output incrementally via pump().

This addresses the memory issue described in GitHub #154 where finish()
would buffer all remaining child output in memory.

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

use Test::More tests => 13;
use IPC::Run::Debug qw( _map_fds );
use IPC::Run qw( start pump finish timeout );

my @cat = ( $^X, '-e', 'print while <STDIN>' );
my @echoer = ( $^X, '-pe', 'BEGIN { $| = 1 }' );

## Test 1: close_stdin returns the harness for chaining
{
    my ( $in, $out ) = ( '', '' );
    my $h = start \@echoer, \$in, \$out, timeout(5);

    my $ret = $h->close_stdin;
    is( $ret, $h, "close_stdin returns the harness for chaining" );

    $h->finish;
    ok( !$h->pumpable, "harness is not pumpable after finish" );
}

## Test 2: close_stdin signals EOF, child exits, output is captured
{
    my $in  = "hello world\n";
    my $out = '';
    my $h   = start \@cat, \$in, \$out, timeout(5);

    # Pump until input is consumed
    pump $h until $in eq '';

    $h->close_stdin;

    # Continue pumping until child exits
    while ( $h->pumpable ) {
        $h->pump;
    }

    $h->finish;
    is( $out, "hello world\n", "output received after close_stdin" );
}

## Test 3: close_stdin allows incremental output draining
{
    # This simulates the decompression pattern from issue #154.
    # Feed multiple lines, close stdin, then drain output incrementally.
    my @line_printer = ( $^X, '-e', '
        $| = 1;
        while (<STDIN>) {
            # Echo each line back with a prefix
            print "OUT:$_";
        }
    ' );

    my ( $in, $out ) = ( '', '' );
    my $h = start \@line_printer, \$in, \$out, timeout(5);

    # Send some input
    $in = "line1\nline2\nline3\n";
    pump $h until $in eq '';

    # Close stdin - child should see EOF
    $h->close_stdin;

    # Drain output incrementally
    my $collected = '';
    while ( $h->pumpable ) {
        $h->pump;
        if ( length $out ) {
            $collected .= $out;
            $out = '';
        }
    }

    $h->finish;

    like( $collected, qr/OUT:line1/, "incremental drain got line1" );
    like( $collected, qr/OUT:line2/, "incremental drain got line2" );
    like( $collected, qr/OUT:line3/, "incremental drain got line3" );
}

## Test 4: close_stdin is idempotent (calling twice doesn't crash)
{
    my ( $in, $out ) = ( '', '' );
    my $h = start \@echoer, \$in, \$out, timeout(5);

    $h->close_stdin;
    eval { $h->close_stdin };
    is( $@, '', "calling close_stdin twice does not throw" );

    $h->finish;
    ok(1, "finish after double close_stdin succeeds");
}

## Test 5: close_stdin followed by finish works correctly
{
    my $in  = "test\n";
    my $out = '';
    my $h   = start \@echoer, \$in, \$out, timeout(5);

    pump $h until $in eq '';
    $h->close_stdin;

    # Now finish should work without accumulating unbounded output
    $h->finish;

    is( $out, "test\n", "close_stdin + finish produces correct output" );
}

## Test 6: file descriptor leak check
{
    my $fd_map_before = _map_fds;

    my ( $in, $out ) = ( '', '' );
    my $h = start \@echoer, \$in, \$out, timeout(5);

    $in = "fd check\n";
    pump $h until $in eq '';
    $h->close_stdin;

    while ( $h->pumpable ) {
        $h->pump;
    }
    $h->finish;

    is( _map_fds, $fd_map_before, "no file descriptor leak after close_stdin" );
}

## Test 7: close_stdin with pipeline (multiple children)
{
    my @upper = ( $^X, '-pe', '$_ = uc' );
    my ( $in, $out ) = ( '', '' );
    my $h = start \@echoer, \$in, '|', \@upper, \$out, timeout(5);

    $in = "pipeline test\n";
    pump $h until $in eq '';
    $h->close_stdin;

    while ( $h->pumpable ) {
        $h->pump;
    }
    $h->finish;

    is( $out, "PIPELINE TEST\n", "close_stdin works with pipelines" );
}

## Test 8: close_stdin with multi-line streaming pattern
{
    my @counter = ( $^X, '-e', '
        $| = 1;
        my $count = 0;
        while (<STDIN>) {
            $count++;
            print "line $count\n";
        }
        print "total: $count\n";
    ' );

    my ( $in, $out ) = ( '', '' );
    my $h = start \@counter, \$in, \$out, timeout(5);

    # Feed lines one at a time
    for my $i ( 1 .. 5 ) {
        $in = "input $i\n";
        pump $h until $in eq '';
    }

    # Close stdin to trigger the "total" line
    $h->close_stdin;

    my $collected = '';
    while ( $h->pumpable ) {
        $h->pump;
        $collected .= $out;
        $out = '';
    }
    $h->finish;

    like( $collected, qr/total: 5/, "child received all input before close_stdin" );
    like( $collected, qr/line 5/,   "all lines processed" );
}
