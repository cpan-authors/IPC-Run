#!/usr/bin/perl

=pod

=head1 NAME

large_write.t - Test writing more than 65536 bytes through a pipe

=head1 DESCRIPTION

Regression test for GitHub issue #126: writing more than 65536 bytes
(the typical kernel pipe buffer size) to a child's stdin via IPC::Run
would fail because _write() did not handle EAGAIN from non-blocking
pipe writes.

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

use IPC::Run qw( run start pump finish timeout );
use Test::More;

if ( IPC::Run::Win32_MODE() ) {
    plan skip_all => 'Non-blocking pipe write test not applicable on Win32';
}
else {
    plan tests => 4;
}

## Test 1: run() delivers all data >64KB to child via scalar ref
{
    my $size = 80_000;
    my $in   = 'x' x $size;
    my $out  = '';

    run( [ $^X, '-e', 'use bytes; my $d = do { local $/; <STDIN> }; print length($d)' ],
        \$in, \$out );

    chomp $out;
    is( $out, $size, "GH#126: run() delivers all $size bytes to child stdin" );
}

## Test 2: start()/finish() delivers all data >64KB to child via scalar ref
{
    my $size = 100_000;
    my $in   = 'y' x $size;
    my $out  = '';

    my $h = start(
        [ $^X, '-e', 'use bytes; my $d = do { local $/; <STDIN> }; print length($d)' ],
        \$in, \$out, timeout(30)
    );
    $h->finish;

    chomp $out;
    is( $out, $size, "GH#126: start/finish delivers all $size bytes to child stdin" );
}

## Test 3: Large data round-trip -- send >64KB, child echoes it back
{
    my $size = 200_000;
    my $in   = 'z' x $size;
    my $out  = '';

    run( [ $^X, '-e', 'binmode STDIN; binmode STDOUT; print while <STDIN>' ],
        \$in, \$out );

    is( length($out), $size, "GH#126: $size bytes round-trip through child" );
}

## Test 4: Slow consumer -- child reads one byte at a time, forcing pipe
## buffer to fill completely and triggering EAGAIN on non-blocking writes.
{
    my $size = 80_000;
    my $in   = 'w' x $size;
    my $out  = '';

    # Child reads one byte at a time via sysread to maximise back-pressure
    my $slow_reader = q{
        use bytes;
        binmode STDIN;
        my $total = 0;
        while (1) {
            my $n = sysread(STDIN, my $buf, 1);
            last unless $n;
            $total += $n;
        }
        print $total;
    };

    run( [ $^X, '-e', $slow_reader ], \$in, \$out, timeout(60) );

    chomp $out;
    is( $out, $size, "GH#126: all $size bytes delivered to slow consumer" );
}
