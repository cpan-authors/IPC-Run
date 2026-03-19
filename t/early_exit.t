#!/usr/bin/perl

=pod

=head1 NAME

early_exit.t - Test that IPC::Run survives a child that exits before consuming all stdin

=head1 DESCRIPTION

Reproduces GitHub issue #35 / rt.cpan.org #11568: IPC::Run causes Perl to
silently abort when a child process exits early while the parent is still
writing to its stdin pipe.  The default SIGPIPE disposition kills the parent
silently; IPC::Run must install a local SIGPIPE handler to prevent this.

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
use IPC::Run qw( run );

# Skip on Windows - SIGPIPE semantics differ
if ( IPC::Run::Win32_MODE() ) {
    plan skip_all => "SIGPIPE is a Unix concept; skipping on $^O";
}

plan tests => 4;

# A large input that the child will never consume because it exits immediately.
my $large_input = "x" x 1_000_000;

my ( $out, $err ) = ( '', '' );

# run() must not die/abort when the child exits before reading all stdin.
my $ok = eval {
    run [ $^X, '-e', 'exit 7' ], \$large_input, \$out, \$err;
    1;
};
is $@,  '',   'run() did not throw an exception on early child exit';
ok $ok,       'run() returned without dying';

# $? must reflect the child's exit code.
my $status = $? >> 8;
is $status, 7, 'exit code is correctly propagated';

# Repeat several times to catch race conditions between write and child exit.
my $passed = 0;
for my $i ( 1 .. 10 ) {
    my ( $o, $e ) = ( '', '' );
    eval { run [ $^X, '-e', 'exit 3' ], \$large_input, \$o, \$e };
    $passed++ unless $@;
}
is $passed, 10, 'survived 10 consecutive early-exit runs without dying';
