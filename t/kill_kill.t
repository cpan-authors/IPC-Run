#!/usr/bin/perl

=pod

=head1 NAME

kill_kill.t - Test suite for IPC::Run->kill_kill

=cut

BEGIN {
    $|  = 1;
    $^W = 1;
    if ( $ENV{PERL_CORE} ) {
        chdir '../lib/IPC/Run' if -d '../lib/IPC/Run';
        unshift @INC, 'lib', '../..';
        $^X = '../../../t/' . $^X;
    }
}

use strict;
use warnings;
use Test::More;
use IPC::Run ();

# Don't run this test script on Windows at all
if ( IPC::Run::Win32_MODE() ) {
    plan( skip_all => 'Temporarily ignoring test failure on Win32' );
    exit(0);
}
else {
    plan( tests => 2 );
}

# Test 1
SCOPE: {
    my $out;
    my $h = IPC::Run::start(
        [
            $^X,
            '-e',
            '$|=1;print "running\n";sleep while 1',
        ],
        \undef,
        \$out
    );

    # On most platforms, we don't need to wait to read the "running" message.
    # On NetBSD 10.0, not waiting led to us often issuing kill(kid, SIGTERM)
    # before the end of the child's exec().  Per https://gnats.netbsd.org/58268,
    # NetBSD then discarded the signal.
    pump $h until $out =~ /running/;
    my $needed = $h->kill_kill;
    ok( !$needed, 'Did not need kill_kill' );
}

# Test 2
SKIP: {
    if ( IPC::Run::Win32_MODE() ) {
        skip( "$^O does not support ignoring the TERM signal", 1 );
    }

    my $out;
    my $h = IPC::Run::start(
        [
            $^X,
            '-e',
            '$SIG{TERM}=sub{};$|=1;print "running\n";sleep while 1',
        ],
        \undef,
        \$out
    );
    pump $h until $out =~ /running/;
    my $needed = $h->kill_kill( grace => 1 );
    ok( $needed, 'Did need kill_kill' );
}
