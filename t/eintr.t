#!/usr/bin/perl

=pod

=head1 NAME

eintr.t - Test select() and read() failing with EINTR

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
use IPC::Run qw( start run );

my $got_usr1 = 0;
$SIG{USR1} = sub { $got_usr1++ };

# Need the child to send a signal to this process in order to trigger
# EINTR on select(), skip the test on platforms where we can't do that.
my ( $in, $out, $err ) = ( '', '', '' );
run [ $^X, '-e', "kill 'USR1', $$" ], \$in, \$out, \$err;
if ( $got_usr1 != 1 ) {
    plan skip_all => "can't deliver a signal on this platform";
}

plan tests => 5;

# A kid that will send SIGUSR1 to this process and then produce some output.
my $kid_perl = qq[sleep 1; kill 'USR1', $$; sleep 1; print "foo\n"; sleep 180];
my @kid = ( $^X, '-e', "\$| = 1; $kid_perl" );

# If EINTR on select() is not handled properly then IPC::Run can think
# that one or more kid output handles are ready for reads when they are
# not, causing it to block until the kid exits.

( $in, $out, $err ) = ( '', '', '' );
my $harness = start \@kid, \$in, \$out, \$err;

my $pump_started = time;
$harness->pump;

is $out, "foo\n", "got stdout on the first pump";

ok time - $pump_started < 180, "first pump didn't wait for kid exit";

is $got_usr1, 2, 'got USR1 from the kid';

$harness->kill_kill;
$harness->finish;

# Have kid send SIGUSR1 while we're in read of sync pipe.  That pipe conveys any
# exec failure to us.
SKIP: {
    if ( IPC::Run::Win32_MODE() ) {
        skip "Can't really exec() $^O", 2;
    }

    my $expected = 'exec failed';
    my $h        = eval {
        start(
            [ $^X, "-e", 1 ],
            _sigusr1_after_fork    => 1,
            _simulate_exec_failure => 1
        );
    };
    my $got = $@ =~ $expected ? $expected : $@ || "";
    is $got_usr1, 3, 'got USR1 from the _simulate_exec_failure kid';
    is( $got, $expected, "reported exec failure despite USR1" );
}
