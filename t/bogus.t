#!/usr/bin/perl

=pod

=head1 NAME

bogus.t - test bogus file cases.

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

use Test::More tests => 2;
use IPC::Run qw( start );

SCOPE: {
    ## Older Test.pm's don't grok qr// in $expected.
    my $expected = 'file not found';
    eval { start ["./bogus_really_bogus"] };
    my $got = $@ =~ $expected ? $expected : $@ || "";
    is( $got, $expected, "starting ./bogus_really_bogus" );
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
