#!/usr/bin/perl

=pod

=head1 NAME

tied_stderr.t - Test IPC::Run with tied STDERR that lacks FILENO

=head1 DESCRIPTION

Regression test for rt.cpan.org#102824 / GitHub issue #92.
When STDERR is tied to a class that doesn't implement FILENO,
IPC::Run should still work correctly.

=cut

use strict;
use warnings;
use Test::More tests => 2;
use IPC::Run qw(run timeout);

{
    package MySTDERR;
    sub TIEHANDLE { return bless {}, __PACKAGE__ }
    sub PRINT { shift; print STDOUT @_ }
}

# Tie STDERR to a handle that doesn't implement FILENO
tie *STDERR, 'MySTDERR' or die $!;

my $out;

# This should not die with "Can't locate object method "FILENO""
# Use $^X instead of 'echo' so the test works on Win32 where echo is
# a shell built-in, not a standalone executable (GH#222).
eval { run [ $^X, '-e', 'print qq(hello\n)' ], '>', \$out, timeout(30) };
my $err = $@;

untie *STDERR;

ok( !$err, "run() succeeds with tied STDERR lacking FILENO" )
    or diag("Got error: $err");

$out = '' unless defined $out;
$out =~ s/\r?\n$//;
is( $out, 'hello', "run() captures output correctly with tied STDERR" );
