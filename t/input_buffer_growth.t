#!/usr/bin/perl

=pod

=head1 NAME

input_buffer_growth.t - Test that the input buffer ($in) does not grow unboundedly

=head1 DESCRIPTION

Regression test for GitHub issue #154: when using start()/pump() to stream
data to a child process, the internal intermediate buffer would accumulate
all of $in at once when clear_ins=1.  This caused exponential memory growth
when the child was a slow consumer and the user kept appending to $in.

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

use Test::More tests => 4;
use IPC::Run qw( start pump finish timeout );

##
## $^X is the path to the perl binary.
##
my @passthrough = ( $^X, '-pe', 'BEGIN { $| = 1 }' );

## Test 1 & 2: Large input is chunked -- $in should NOT be fully cleared in one pump_nb.
##
## The SCALAR source filter must copy at most 65536 bytes per invocation.
## Without the fix, the entire $in (200KB) was moved to the internal FBUFS buffer
## in one shot, leaving $in empty after the first pump_nb.
## With the fix, only 65536 bytes are copied per filter run, so $in retains
## the remaining ~134KB after the first pump_nb.
{
    my ( $in, $out ) = ( '', '' );
    my $h = start( \@passthrough, \$in, \$out, timeout(30) );

    my $chunk_size = 65536;    # must match the limit in IO.pm
    my $total      = $chunk_size * 3;    # 196608 bytes -- three full chunks

    $in = 'A' x $total;

    # One non-blocking pump: this should trigger exactly one write-side
    # filter invocation, moving at most $chunk_size bytes from $in into the
    # internal pipe buffer.
    $h->pump_nb;

    my $remaining = length($in);

    # With the fix: at most one chunk was consumed, so $in must still have
    # at least two full chunks worth of data.
    cmp_ok( $remaining, '>=', $total - $chunk_size,
        'GH#154: pump_nb consumes at most one chunk from $in' );

    # And $in must have been reduced at all (one chunk was written).
    cmp_ok( $remaining, '<', $total,
        'GH#154: pump_nb did consume some data from $in' );

    $in = '';    # clear before finish so the child sees EOF
    $h->finish;
}

## Test 3: All data arrives correctly when fed in large chunks.
##
## Verifies the fix does not lose or corrupt data when streaming
## more than chunk_size bytes through start/pump.
{
    my ( $in, $out ) = ( '', '' );
    my $h = start( \@passthrough, \$in, \$out, timeout(30) );

    my $chunk_size   = 65536;
    my $num_chunks   = 5;
    my $expected_len = $chunk_size * $num_chunks;    # 327680 bytes

    $in = 'B' x $expected_len;
    pump $h until !length($in);    # pump until all input consumed

    $h->finish;

    is( length($out), $expected_len,
        'GH#154: all data transmitted correctly over multiple chunks' );
}

## Test 4: Incremental streaming keeps $in bounded.
##
## Simulates the original bug scenario: user appends small chunks to $in
## on each pump_nb call.  With the fix, $in should stay bounded because
## the filter drains it in 65536-byte chunks.  Without the fix, $in would
## grow to the total data size before being flushed all at once.
{
    my ( $in, $out ) = ( '', '' );
    my $h = start( \@passthrough, \$in, \$out, timeout(30) );

    my $chunk_size   = 65536;
    my $user_chunk   = 1024;         # bytes added per iteration
    my $iterations   = 400;          # total = 400KB
    my $max_in_seen  = 0;

    for ( 1 .. $iterations ) {
        $in .= 'C' x $user_chunk;
        $h->pump_nb;
        my $cur = length($in);
        $max_in_seen = $cur if $cur > $max_in_seen;
    }

    $in = '';
    $h->finish;

    # With the fix, $in is drained in 65536-byte increments, so the maximum
    # observed $in size should stay well below the total data volume.
    # Allow generous slack for OS scheduling variation.
    my $total = $user_chunk * $iterations;
    cmp_ok( $max_in_seen, '<', $total,
        'GH#154: $in does not accumulate all data before flushing' );
}
