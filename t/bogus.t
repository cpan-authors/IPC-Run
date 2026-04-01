#!/usr/bin/perl

=pod

=head1 NAME

bogus.t - test bogus file cases.

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

use Test::More tests => 6;
use IPC::Run qw( run start );

SCOPE: {
    ## Older Test.pm's don't grok qr// in $expected.
    my $expected = 'file not found';
    eval { start ["./bogus_really_bogus"] };
    my $got = $@ =~ $expected ? $expected : $@ || "";
    is( $got, $expected, "starting ./bogus_really_bogus" );
}

# Test that run() with undef command name throws an error rather than
# executing an arbitrary executable from PATH (GitHub issue #162, #271).
SCOPE: {
    my $expected = 'undefined command';
    eval { run [undef] };
    my $got = $@ =~ $expected ? $expected : $@ || "";
    is( $got, $expected, "run [undef] croaks with clear error" );
}

SCOPE: {
    my $expected = 'command name is undefined or empty';
    eval { run [''] };
    my $got = $@ =~ $expected ? $expected : $@ || "";
    is( $got, $expected, "run [''] croaks with clear error" );
}

# Test that harness() with an arrayref whose first element is undef
# throws an error at parse time (GitHub issue #164, #271).
SCOPE: {
    my $expected = 'undefined command';
    eval { run [undef, "arg1", "arg2"] };
    my $got = $@ =~ $expected ? $expected : $@ || "";
    is( $got, $expected, "run [undef, 'arg1', 'arg2'] croaks at harness parse time" );
}

SCOPE: {
    my $expected = 'undefined command';
    my @cmd;
    $cmd[1] = "arg1";    # $cmd[0] is undef
    eval { run \@cmd };
    my $got = $@ =~ $expected ? $expected : $@ || "";
    is( $got, $expected, "run with sparse array (undef first element) croaks at harness parse time" );
}

SKIP: {
    if ( IPC::Run::Win32_MODE() ) {
        skip "Can't really exec() $^O", 1;
    }

    ## Older Test.pm's don't grok qr// in $expected.
    my $expected = 'exec failed';
    my $h        = eval { start( [ $^X, "-e", 1 ], _simulate_exec_failure => 1 ); };
    my $got      = $@ =~ $expected ? $expected : $@ || "";
    is( $got, $expected, "starting $^X with simulated_exec_failure => 1" );
}
