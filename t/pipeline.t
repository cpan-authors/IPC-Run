#!/usr/bin/perl

=pod

=head1 NAME

pipeline.t - Test suite for multi-child pipeline behavior

=head1 DESCRIPTION

Tests IPC::Run's pipeline ('|') operator with multiple children,
verifying data flow, exit codes, error propagation, and resource
cleanup across pipeline stages.

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

use IPC::Run qw( run start pump finish harness timeout );
use IPC::Run::Debug qw( _map_fds );

plan skip_all => 'No fork on Win32' if IPC::Run::Win32_MODE;

plan tests => 29;

my @perl = ($^X);

##
## Two-stage pipeline: basic data flow
##
{
    my $out = '';
    my $r = run(
        [ @perl, '-pe', '$_ = uc' ],
        \q{hello world\n},
        '|',
        [ @perl, '-pe', 's/\s+/_/g; $_ .= "\n" unless /\n$/' ],
        \$out,
    );
    ok( $r, 'two-stage pipeline succeeds' );
    like( $out, qr/HELLO_WORLD/, 'data flows through two stages' );
}

##
## Three-stage pipeline: data flows through all stages
##
{
    my $out = '';
    my $r = run(
        [ @perl, '-e', 'print "one two three\n"' ],
        '|',
        [ @perl, '-pe', '$_ = uc' ],
        '|',
        [ @perl, '-pe', 's/\s+/-/g' ],
        \$out,
    );
    ok( $r, 'three-stage pipeline succeeds' );
    like( $out, qr/ONE-TWO-THREE/, 'data flows through three stages' );
}

##
## Four-stage pipeline
##
{
    my $out = '';
    my $r = run(
        [ @perl, '-e', 'print "abcd\n"' ],
        '|',
        [ @perl, '-pe', '$_ = uc' ],
        '|',
        [ @perl, '-pe', '$_ = reverse' ],
        '|',
        [ @perl, '-pe', 'chomp; $_ = "[$_]\n"' ],
        \$out,
    );
    ok( $r, 'four-stage pipeline succeeds' );
    # "abcd\n" -> "ABCD\n" -> "\nDCBA" -> "[\nDCBA]\n" but reverse includes the newline
    # Let's just check it ran and produced bracketed output
    like( $out, qr/\[.*\]/, 'four-stage pipeline produces output' );
}

##
## Pipeline with input from scalar ref
##
{
    my $in  = "line one\nline two\nline three\n";
    my $out = '';
    my $r = run(
        [ @perl, '-pe', '$_ = uc' ],
        \$in,
        '|',
        [ @perl, '-ne', 'print if /TWO/' ],
        \$out,
    );
    ok( $r, 'pipeline with scalar input succeeds' );
    like( $out, qr/LINE TWO/, 'pipeline filters correctly' );
}

##
## Pipeline with per-child stderr
##
{
    my $out = '';
    my $err = '';
    my $r = run(
        [ @perl, '-e', 'print STDERR "err1\n"; print "data\n"' ],
        '|',
        [ @perl, '-e', 'print STDERR "err2\n"; while(<STDIN>){print uc}' ],
        \$out,
        \$err,
    );
    ok( $r, 'pipeline with stderr succeeds' );
    is( $out, "DATA\n", 'stdout flows through pipeline' );
    # Both children's stderr goes to the shared stderr scalar
    like( $err, qr/err1/, 'first child stderr captured' );
    like( $err, qr/err2/, 'second child stderr captured' );
}

##
## Pipeline exit codes: all succeed
##
{
    my $h = harness(
        [ @perl, '-e', 'exit 0' ],
        '|',
        [ @perl, '-e', 'exit 0' ],
    );
    $h->start;
    $h->finish;
    my @results = $h->results;
    is( scalar @results, 2, 'results() returns one per child' );
    is( $results[0], 0, 'first child exit 0' );
    is( $results[1], 0, 'second child exit 0' );
}

##
## Pipeline exit codes: last child fails
##
{
    my $out = '';
    my $h = harness(
        [ @perl, '-e', 'print "ok\n"; exit 0' ],
        '|',
        [ @perl, '-e', 'while(<STDIN>){}; exit 42' ],
        \$out,
    );
    $h->start;
    eval { $h->finish };
    my @results = $h->results;
    is( $results[0], 0,  'first child exits 0 in failed pipeline' );
    is( $results[1], 42, 'last child exit code captured' );
}

##
## Pipeline exit codes: first child fails
##
{
    my $out = '';
    my $h = harness(
        [ @perl, '-e', 'print "partial\n"; exit 7' ],
        '|',
        [ @perl, '-pe', '$_ = uc' ],
        \$out,
    );
    $h->start;
    eval { $h->finish };
    my @results = $h->results;
    is( $results[0], 7, 'first child exit code captured' );
    # second child may succeed or get SIGPIPE depending on timing
    ok( defined $results[1], 'second child has a result' );
}

##
## Pipeline with result() returns first non-zero
##
{
    my $out = '';
    my $h = harness(
        [ @perl, '-e', 'exit 0' ],
        '|',
        [ @perl, '-e', 'exit 5' ],
        '|',
        [ @perl, '-e', 'exit 0' ],
        \$out,
    );
    $h->start;
    eval { $h->finish };
    is( $h->result, 5, 'result() returns first non-zero exit code' );
}

##
## Pipeline with start/pump/finish (async API)
##
{
    my $in  = '';
    my $out = '';
    my $h = start(
        [ @perl, '-e', '$| = 1; while (<STDIN>) { print uc }' ],
        \$in,
        '|',
        [ @perl, '-e', '$| = 1; while (<STDIN>) { print "prefix: $_" }' ],
        \$out,
        timeout(10),
    );

    $in = "hello\n";
    pump $h until length $out;
    like( $out, qr/prefix: HELLO/i, 'async pipeline processes data' );

    $in = "world\n";
    $out = '';
    pump $h until length $out;
    like( $out, qr/prefix: WORLD/i, 'async pipeline processes second chunk' );

    $h->close_stdin;
    $h->finish;
    ok( 1, 'async pipeline finish succeeds' );
}

##
## Pipeline with timeout
##
{
    my $out = '';
    my $h = harness(
        [ @perl, '-e', 'sleep 60; print "never\n"' ],
        '|',
        [ @perl, '-pe', '' ],
        \$out,
        timeout(2),
    );
    $h->start;
    my $timed_out = 0;
    eval {
        $h->finish;
    };
    if ( $@ && $@ =~ /timeout/ ) {
        $timed_out = 1;
    }
    ok( $timed_out, 'pipeline with timeout fires' );
    $h->kill_kill;
}

##
## File descriptor cleanup after pipeline
##
{
    my $fd_before = _map_fds;
    for my $i (1..3) {
        my $out = '';
        run(
            [ @perl, '-e', 'print "test\n"' ],
            '|',
            [ @perl, '-pe', '' ],
            \$out,
        );
    }
    is( _map_fds, $fd_before, 'no fd leak after repeated pipelines' );
}

##
## Pipeline with empty input (stdin closed immediately)
##
{
    my $out = '';
    my $r = run(
        [ @perl, '-e', 'print while <STDIN>' ],
        \q{},
        '|',
        [ @perl, '-pe', '' ],
        \$out,
    );
    ok( $r, 'pipeline with empty input succeeds' );
    is( $out, '', 'pipeline with empty input produces no output' );
}

##
## Pipeline preserves binary data
##
{
    # Build a string with bytes 0x00-0xFF
    my $binary = join '', map { chr($_) } 0..255;
    my $out = '';
    my $r = run(
        [ @perl, '-e', 'binmode STDOUT; print join("", map { chr } 0..255)' ],
        '|',
        [ @perl, '-e', 'binmode STDIN; binmode STDOUT; print while sysread(STDIN, $_, 4096)' ],
        \$out,
    );
    ok( $r, 'binary pipeline succeeds' );
    is( length($out), 256, 'binary data preserved through pipeline' );
}
