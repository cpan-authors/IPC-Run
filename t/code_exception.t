#!/usr/bin/perl

=pod

=head1 NAME

code_exception.t - Test that exceptions in child CODE refs propagate to parent

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

use Test::More tests => 5;
use IPC::Run qw( run start );

# Test 1: Exception in CODE ref propagates through run()
SCOPE: {
    my $exception;
    eval {
        run sub { die "child exception via run\n" };
    };
    $exception = $@;
    ok( $exception, 'run() propagates exception from child CODE ref' );
    like( $exception, qr/child exception via run/, 'exception message is correct for run()' );
}

# Test 2: Exception in CODE ref propagates through start()
SCOPE: {
    my $exception;
    eval {
        start sub { die "child exception via start\n" };
    };
    $exception = $@;
    ok( $exception, 'start() propagates exception from child CODE ref' );
    like( $exception, qr/child exception via start/, 'exception message is correct for start()' );
}

# Test 3: No exception when CODE ref succeeds
SCOPE: {
    my $exception;
    eval {
        run sub { 1 };
    };
    $exception = $@;
    ok( !$exception, 'no exception propagated when CODE ref succeeds' );
}
