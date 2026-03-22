#!/usr/bin/perl

=pod

=head1 NAME

gh_57_external_pipe_child_dies.t - Test that external pipe input handles are closed after fork

=head1 DESCRIPTION

Regression test for GitHub issue #57 (rt.cpan.org #93301).

When an external filehandle (e.g. IO::Pipe read end) is passed as input via
C<< '<', $fh >>, IPC::Run must close the fd in the parent after fork.
Otherwise the parent retains a reader on the pipe, preventing EPIPE/SIGPIPE
when the child exits early — which can hang the writing process forever.

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
use IPC::Run qw( start finish timeout );
use IO::Handle;

BEGIN {
    if ( IPC::Run::Win32_MODE() ) {
        plan skip_all => 'Skipping on Win32';
        exit(0);
    }
    else {
        plan tests => 2;
    }
}

# GH#57: When a child dies immediately and input comes from an external pipe,
# the parent must not hang.  The key is that IPC::Run closes the pipe's read
# end in the parent after fork, so writes to the write end get EPIPE once the
# child is gone.

SKIP: {
    pipe( my $read, my $write )
        or skip "pipe() failed: $!", 2;
    IO::Handle::autoflush($write, 1);

    # Ignore SIGPIPE for the entire test — closing handles and finish()
    # can trigger it after the child exits.
    local $SIG{PIPE} = 'IGNORE';

    my $out = '';
    my $err = '';

    # Child exits immediately with non-zero status (simulates die).
    my $h = start(
        [ $^X, '-e', 'exit 42' ],
        '<',  $read,
        '>',  \$out,
        '2>', \$err,
    );

    # After start(), the read end should be closed in the parent.
    # Writing large data should get EPIPE/SIGPIPE instead of hanging.
    my $timed_out = 0;
    my $write_ok  = 1;
    eval {
        local $SIG{ALRM} = sub { $timed_out = 1; die "alarm\n" };
        alarm(10);

        my $chunk = "x" x 4096 . "\n";
        for ( 1 .. 1000 ) {    # ~4 MB, well above any pipe buffer
            my $r = print {$write} $chunk;
            unless ($r) {
                $write_ok = 0;
                last;
            }
        }

        alarm(0);
    };
    alarm(0);    # safety reset

    ok( !$timed_out, 'GH#57: writing to external pipe does not hang when child dies' );

    # Clean up: close handles, finish harness.
    close $write;
    close $read;    # may already be closed by IPC::Run — that is fine

    eval { finish $h };

    is( $? >> 8, 42, 'GH#57: child exit status is correctly reported' );
}
