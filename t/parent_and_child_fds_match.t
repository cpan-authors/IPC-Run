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
    my $expected_fd = $ARGV[1];
    my $fh = IO::Handle->new_from_fd($expected_fd, '+<');
    if (!defined $fh) {
        # Diagnostics: report which fds ARE open so failures are actionable
        my @open_fds;
        for my $fd (0..20) {
            push @open_fds, $fd if defined POSIX::fcntl($fd, Fcntl::F_GETFD(), 0);
        }
        die "new_from_fd($expected_fd): $! (open fds: @open_fds)";
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

    # Find the lowest available (closed) fd >= 3. We don't close any fds
    # because that could break the test harness (e.g., prove uses fd 3).
    # The kernel allocates the lowest available fd, so tempfile() will
    # naturally land on $target_fd, giving us TFD == KFD to exercise the
    # matching-fd code path in _do_kid_and_exit.
    my $target_fd = 3;
    while (defined POSIX::fcntl($target_fd, Fcntl::F_GETFD(), 0)) {
        $target_fd++;
    }

    my $fh = tempfile();
    ok($fh, 'opened file');

    my $actual_fd = fileno($fh);
    if ($actual_fd != $target_fd) {
        # Something grabbed $target_fd between our check and tempfile().
        # Move the tempfile there (we know $target_fd is available).
        POSIX::dup2($actual_fd, $target_fd) or die "dup2($actual_fd, $target_fd): $!";
        POSIX::close($actual_fd);
        open($fh, '+<&=', $target_fd) or die "reopen fd $target_fd: $!";
    }

    diag("tempfile is fd " . fileno($fh) . " (target was $target_fd)");

    my @command = ($^X, $0, 'child', $target_fd);

    my $stdout = sub { note_output("stdout", $_); return; };
    my $stderr = sub { note_output("stderr", $_); return; };

    my $harness = IPC::Run::start(
        \@command,
        \undef,  # fd 0
        $stdout, # fd 1
        $stderr, # fd 2
        "${target_fd}>", $fh,
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
