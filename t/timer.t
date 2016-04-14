#!/usr/bin/perl

=pod

=head1 NAME

timer.t - Test suite for IPC::Run::Timer

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

use Test::More tests => 77;
use IPC::Run qw( run );
use IPC::Run::Timer qw( :all );

my $t;
my $started;

$t = timer(

    # debug => 1,
    1,
);
is( ref $t, 'IPC::Run::Timer' );

is( $t->interval, 1 );

$t->interval(0);
is( $t->interval, 0 );
$t->interval(0.1);
ok( $t->interval > 0 );
$t->interval(1);
ok( $t->interval >= 1 );
$t->interval(30);
ok( $t->interval >= 30 );
$t->interval(30.1);
ok( $t->interval > 30 );
$t->interval(30.1);
ok( $t->interval <= 31 );

SKIP: {
    skip( "Perl below 5.8.9 doesn't seem to be able to handle infinity", 1 ) if ( $] < 5.008009 );
    $t->interval('inf');
    ok( $t->interval > 1000, "Infinity timer." );
}

$t->interval("1:0");
is( $t->interval, 60 );
$t->interval("1:0:0");
is( $t->interval, 3600 );
$t->interval("1:1:1");
is( $t->interval, 3661 );
$t->interval("1:1:1.1");
ok( $t->interval > 3661 );
$t->interval("1:1:1.1");
ok( $t->interval <= 3662 );
$t->interval("1:1:1:1");
is( $t->interval, 90061 );

SCOPE: {
    eval { $t->interval("1:1:1:1:1") };
    my $msg = 'IPC::Run: expected <= 4';
    $@ =~ /$msg/ ? ok(1) : is( $@, $msg );
}

SCOPE: {
    eval { $t->interval("foo") };
    my $msg = 'IPC::Run: non-numeric';
    $@ =~ /$msg/ ? ok(1) : is( $@, $msg );
}

SCOPE: {
    eval { $t->interval("1foo1:9:bar:0") };
    my $msg = 'IPC::Run: non-numeric';
    $@ =~ /$msg/ ? ok(1) : is( $@, $msg );
}

SCOPE: {
    eval { $t->interval("6:4:") };
    my $msg = 'IPC::Run: non-numeric';
    $@ =~ /$msg/ ? ok(1) : is( $@, $msg );
}

$t->reset;
$t->interval(5);
$t->start( 1, 0 );
ok( !$t->is_expired );
ok( !!$t->is_running );
ok( !$t->is_reset );
ok( !!$t->check(0) );
ok( !$t->is_expired );
ok( !!$t->is_running );
ok( !$t->is_reset );
ok( !!$t->check(1) );
ok( !$t->is_expired );
ok( !!$t->is_running );
ok( !$t->is_reset );
ok( !$t->check(2) );
ok( !!$t->is_expired );
ok( !$t->is_running );
ok( !$t->is_reset );
ok( !$t->check(3) );
ok( !!$t->is_expired );
ok( !$t->is_running );
ok( !$t->is_reset );

## Restarting from the expired state.

$t->start( undef, 0 );
ok( !$t->is_expired );
ok( !!$t->is_running );
ok( !$t->is_reset );
ok( !!$t->check(0) );
ok( !$t->is_expired );
ok( !!$t->is_running );
ok( !$t->is_reset );
ok( !!$t->check(1) );
ok( !$t->is_expired );
ok( !!$t->is_running );
ok( !$t->is_reset );
ok( !$t->check(2) );
ok( !!$t->is_expired );
ok( !$t->is_running );
ok( !$t->is_reset );
ok( !$t->check(3) );
ok( !!$t->is_expired );
ok( !$t->is_running );
ok( !$t->is_reset );

## Restarting while running

$t->start( 1,     0 );
$t->start( undef, 0 );
ok( !$t->is_expired );
ok( !!$t->is_running );
ok( !$t->is_reset );
ok( !!$t->check(0) );
ok( !$t->is_expired );
ok( !!$t->is_running );
ok( !$t->is_reset );
ok( !!$t->check(1) );
ok( !$t->is_expired );
ok( !!$t->is_running );
ok( !$t->is_reset );
ok( !$t->check(2) );
ok( !!$t->is_expired );
ok( !$t->is_running );
ok( !$t->is_reset );
ok( !$t->check(3) );
ok( !!$t->is_expired );
ok( !$t->is_running );
ok( !$t->is_reset );

my $got;
eval {
    $got = "timeout fired";
    run [ $^X, '-e', 'sleep 3' ], timeout 1;
    $got = "timeout didn't fire";
};
is $got, "timeout fired", "timer firing in run()";
