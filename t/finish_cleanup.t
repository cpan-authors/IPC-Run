#!/usr/bin/perl

=pod

=head1 NAME

finish_cleanup.t - Test that finish() cleans up even when _select_loop throws

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
use IPC::Run qw( start timeout );
use IPC::Run::Debug qw( _map_fds );

my @perl = ($^X);

##
## Test 1-2: finish() cleans up pipes and reaps children on timeout exception
##
## Before the fix, _select_loop throwing an exception in finish() would skip
## _cleanup(), leaking pipes and child processes.  run() handled this via
## eval + kill_kill, but the async API (start/pump/finish) had no safety net.
##
SKIP: {
    if ( IPC::Run::Win32_MODE() ) {
        skip( "Win32 kills children immediately, different cleanup path", 4 );
    }

    my $fd_map = _map_fds;

    my $out = '';
    my $h   = start(
        [ @perl, '-e', 'sleep 60' ],
        '>', \$out,
        timeout(0.01),
    );

    ## Give the timeout a moment to definitely expire
    select( undef, undef, undef, 0.05 );

    eval { $h->finish };
    my $err = $@;

    like( $err, qr/timeout/i, "finish() propagated timeout exception" );

    ## The harness should be marked as finished despite the exception
    ok( $h->finished, "harness marked finished after exception" );

    ## Key assertion: file descriptors should be the same as before start()
    ## This proves _cleanup() ran even though _select_loop threw
    is( _map_fds, $fd_map, "no fd leak after finish() exception" );

    ## Verify no zombie child processes remain
    ## _cleanup calls _waitpid for all kids, so PID should be reaped
    my $kids_reaped = 1;
    for my $kid ( @{ $h->{KIDS} } ) {
        if ( defined $kid->{PID} && kill( 0, $kid->{PID} ) ) {
            $kids_reaped = 0;
            ## Clean up the leaked child if the test fails
            kill 'KILL', $kid->{PID};
            waitpid( $kid->{PID}, 0 );
        }
    }
    ok( $kids_reaped, "child processes reaped after finish() exception" );
}
