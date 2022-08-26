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

if (@ARGV > 0 && $ARGV[0] eq 'child') {
    exit(child());
}

exit(parent());

sub child {
    my $fh = IO::Handle->new_from_fd(3, '+<');
    die "new_from_fd(): $!" unless defined $fh;
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

    # This is fd 3 since we have 0, 1, 2 taken by stdin, stdout, and stderr.
    my $fh = tempfile();
    ok($fh, 'opened file');

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
