#!/usr/bin/perl

=pod

=head1 NAME

early_exit.t - Test that parent survives when child exits before consuming all input

=head1 DESCRIPTION

Regression test for GitHub issue #49 / rt.cpan.org #81928.

When a child process exits very quickly (before reading all of its stdin),
the parent must not die.  Previously, the broken-pipe EPIPE from the write
call propagated as an uncaught exception and killed the parent.

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
use IPC::Run qw( run timeout );

BEGIN {
    if ( IPC::Run::Win32_MODE() ) {
        plan skip_all => 'Skipping on Win32';
        exit(0);
    }
    else {
        plan tests => 3;
    }
}

# Reproduce the race: child exits immediately without reading stdin.
# Run multiple times to increase the chance of triggering the race window.
my $survived = 0;
for my $i ( 1 .. 20 ) {
    my $in  = "some input data\n" x 100;   # non-trivial input to make the race more likely
    my $out = '';
    my $err = '';
    eval {
        run [ 'sh', '-c', 'exit 7' ], \$in, \$out, \$err, timeout(5);
    };
    # EPIPE/broken-pipe must NOT propagate; only a timeout or the child's
    # non-zero exit is acceptable.
    if ( $@ && $@ !~ /timeout|IPC::Run/ ) {
        fail("Iteration $i: parent died with unexpected exception: $@");
        last;
    }
    $survived++;
}
is( $survived, 20, 'parent survives all 20 runs of a fast-exiting child' );

# Verify the exit status is correctly reported (child exits with code 7).
{
    my $in  = "\n";
    my $out = '';
    my $err = '';
    my $ok  = eval {
        run [ 'sh', '-c', 'exit 7' ], \$in, \$out, \$err, timeout(5);
    };
    my $exc = $@;

    # run() returns false on non-zero exit; exception must not be thrown
    ok( !$exc, 'no exception thrown when child exits with non-zero status' )
        or diag("Exception: $exc");

    # Child exited with status 7 → POSIX wait status 7 << 8 = 1792
    # IPC::Run stores this in $?
    is( $? >> 8, 7, 'child exit code 7 is correctly propagated' );
}
