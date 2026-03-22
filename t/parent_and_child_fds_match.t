#!/usr/bin/env perl
#
# Test a child process can use the fd if it happens to be the same number as it
# was in the parent.

use strict;
use warnings;

use Data::Dumper;
use File::Temp qw( tempfile );
use IO::Handle ();
use IPC::Run ();
use POSIX ();

if (@ARGV > 0 && $ARGV[0] eq 'child') {
    exit(child());
}

exit(parent());

sub child {
    my $fh = IO::Handle->new_from_fd(3, '+<');
    if (!defined $fh) {
        # Diagnostics: report which fds ARE open so failures are actionable
        my @open_fds;
        for my $fd (0..20) {
            push @open_fds, $fd if defined POSIX::fcntl($fd, Fcntl::F_GETFD(), 0);
        }
        die "new_from_fd(3): $! (open fds: @open_fds)";
    }
    return 0;
}

sub parent {
    # Load at runtime to not involve the child's run in any tests. We could
    # alternatively move the child to its own program but it is easier to
    # re-run ourselves by using $0.
    require Test::More;
    Test::More->import;

    plan(skip_all => "$^O does not allow redirection of file descriptors > 2")
      if IPC::Run::Win32_MODE();
    # We can't use done_testing() to account for number of tests as 5.8.9's
    # Test::More apparently doesn't support that.
    plan(tests => 3);

    # Ensure fd 3 is available for the tempfile. Under some test harnesses
    # (e.g., prove), fd 3 may already be in use, which would push the
    # tempfile to a higher fd and change the nature of what we're testing.
    # We specifically need TFD == KFD == 3 to exercise the matching-fd
    # code path in _do_kid_and_exit.
    POSIX::close(3) if defined POSIX::fcntl(3, Fcntl::F_GETFD(), 0);

    my $fh = tempfile();
    ok($fh, 'opened file');

    my $actual_fd = fileno($fh);
    if ($actual_fd != 3) {
        # Despite closing fd 3, something else grabbed it. Move the
        # tempfile to fd 3 explicitly so the test exercises the right path.
        POSIX::dup2($actual_fd, 3) or die "dup2($actual_fd, 3): $!";
        POSIX::close($actual_fd);
        open($fh, '+<&=', 3) or die "reopen fd 3: $!";
    }

    diag("tempfile is fd " . fileno($fh));

    my @command = ($^X, $0, 'child');

    my $stdout = sub { note_output("stdout", $_); return; };
    my $stderr = sub { note_output("stderr", $_); return; };

    my $harness = IPC::Run::start(
        \@command,
        \undef,  # fd 0
        $stdout, # fd 1
        $stderr, # fd 2
        $fh,     # fd 3
    );

    ok($harness, 'started process');

    ok($harness->finish, 'child process exited with success status');

    return 0;
}

sub note_output {
    my ($prefix, $rest) = @_;
    if (ref $rest) {
        note("$prefix: " . Dumper($rest));
        return;
    }
    note("$prefix: $rest");
    return;
}
