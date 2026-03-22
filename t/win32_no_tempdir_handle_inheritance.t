#!/usr/bin/perl

=pod

=head1 NAME

win32_no_tempdir_handle_inheritance.t - start() must not lock File::Temp tempdirs on Win32

=head1 DESCRIPTION

Regression test for https://github.com/cpan-authors/IPC-Run/issues/141

When IPC::Run::start() spawns a child process on Win32 it calls
Win32::Process::Create() with bInheritHandles=TRUE.  Any inheritable
handles open in the parent process at that moment (including those held
internally by File::Temp::newdir) are inherited by the child.  Because
the child is long-lived (start/finish), those handles keep the temp
directory locked so File::Temp cannot clean it up.

The fix marks all file descriptors that are not intended for the child
(i.e. everything except fd 0/1/2) as non-inheritable before the
CreateProcess call.

=cut

use strict;
use warnings;

use Test::More;
use File::Temp;
use IPC::Run qw(start finish);

plan skip_all => 'Win32 only' unless $^O eq 'MSWin32';
plan tests => 1;

my ( $in, $out, $err ) = ( '', '', '' );

my $dir_path;
{
    my $tempdir = File::Temp->newdir;
    $dir_path = "$tempdir";

    # Spawn any executable.  %COMSPEC% is always present on Windows.
    my $h = start( [ $ENV{COMSPEC} || 'cmd.exe', '/c', 'exit 0' ],
        \$in, \$out, \$err );

    # Create a file inside the tempdir AFTER start() was called so that
    # we can verify both the dir and a file within it are removable.
    my $file = "$tempdir/probe.txt";
    open my $fh, '>', $file or die "open: $!";
    print {$fh} "test\n";
    close $fh;

    # Finish the child process BEFORE $tempdir goes out of scope so that
    # all child handles are released and File::Temp can clean up without
    # "Permission denied" warnings (GH#236).
    finish $h;

    # $tempdir goes out of scope here; File::Temp will try to unlink the
    # file and rmdir the directory.  Before the fix for GH#141 this raised
    # "Permission denied" because start() inherited a handle into the dir.
}

# Verify the directory was actually removed by File::Temp's DESTROY.
ok( !-d $dir_path, 'File::Temp tempdir cleaned up after child finished' );
