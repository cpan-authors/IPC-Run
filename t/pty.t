#!/usr/bin/perl

=pod

=head1 NAME

pty.t - Test suite for IPC::Run's pty (pseudo-terminal) support

=head1 DESCRIPTION

This test suite starts off with a test that seems to cause a deadlock
on freebsd: \@cmd, '<pty<', ... '>', ..., '2>'... 

This seems to cause the child process entry in the process table to
hang around after the child exits.  Both output pipes are closed, but
the PID is still valid so IPC::Run::finish() thinks it's still alive and
the whole shebang deadlocks waiting for the child to exit.

This is a very rare corner condition, so I'm not patching in a fix yet.
One fix might be to hack IPC::Run to close the master pty when all outputs
from the child are closed.  That's a hack, not sure what to do about it.

This problem needs to be reproduced in a standalone script and investigated
further, but I have not the time.

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

BEGIN {
    if ( !eval { require IO::Pty; } ) {
        plan skip_all => "IO::Pty not installed";
    }
    elsif ( !eval { IO::Pty->VERSION('1.25'); 1 } ) {
        plan skip_all => "IO::Pty >= 1.25 required (have $IO::Pty::VERSION)";
    }
    else {
        plan tests => 37;
    }
}

use IPC::Run::Debug qw( _map_fds );
use IPC::Run qw( start pump finish );

select STDERR;
select STDOUT;

diag("IO::Tty $IO::Tty::VERSION, IO::Pty $IO::Pty::VERSION");

my $echoer_script = <<TOHERE;
\$| = 1;
\$s = select STDERR; \$| = 1; select \$s;
while (<>) {
   print STDERR uc \$_;
   print;
   last if /quit/;
}
TOHERE

##
## $^X is the path to the perl binary.  This is used run all the subprocesses.
##
my @echoer = ( $^X, '-e', $echoer_script );
my $in;
my $out;
my $err;
my $h;
my $r;
my $fd_map;
my $text = "hello world\n";

## TODO: test lots of mixtures of pty's and pipes & files.  Use run().

## Older Perls can't ok( a, qr// ), so I manually do that here.
my $exp;
my $platform_skip = $^O =~ /(?:dragonfly|aix|freebsd|openbsd|netbsd|darwin)/ ? "$^O deadlocks on this test" : "";

# May force opening /var/lib/sss/mc/group on some systems (see
# https://github.com/toddr/IPC-Run/issues/130)
# OpenBSD libc devname(3) opens /var/run/dev.db and keeps it open.
# As this would confuse open file descriptor checks, open it in
# advance.
{my $pty = IO::Pty->new}

##
## stdin only
##
SKIP: {
    if ($platform_skip) {
        skip( $platform_skip, 9 );
    }

    $out    = 'REPLACE ME';
    $?      = 99;
    $fd_map = _map_fds;
    $h      = start \@echoer, '<pty<', \$in, '>', \$out, '2>', \$err;
    $in     = "hello\n";
    $?      = 0;
    pump $h until $out =~ /hello/ && $err =~ /HELLO/;
    is( $out, "hello\n" );
    $exp = qr/^HELLO\n(?!\n)$/;
    $err =~ $exp ? ok(1) : is( $err, $exp );
    is( $in, '' );
    $in = "world\n";
    $?  = 0;
    pump $h until $out =~ /world/ && $err =~ /WORLD/;
    is( $out, "hello\nworld\n" );
    $exp = qr/^HELLO\nWORLD\n(?!\n)$/;
    $err =~ $exp ? ok(1) : is( $err, $exp );
    is( $in, '' );
    $in = "quit\n";
    ok( $h->finish );
    ok( !$? );
    is( _map_fds, $fd_map );
}

##
## stdout, stderr
##
$out    = 'REPLACE ME';
$?      = 99;
$fd_map = _map_fds;
$h      = start \@echoer, \$in, '>pty>', \$out;
$in     = "hello\n";
$?      = 0;
pump $h until $out =~ /hello\r?\n/;
## We assume that the slave's write()s are atomic
$exp = qr/^(?:hello\r?\n){2}(?!\n)$/i;
$out =~ $exp ? ok(1) : is( $out, $exp );
is( $in, '' );
$in = "world\n";
$?  = 0;
pump $h until $out =~ /world\r?\n/;
$exp = qr/^(?:hello\r?\n){2}(?:world\r?\n){2}(?!\n)$/i;
$out =~ $exp ? ok(1) : is( $out, $exp );
is( $in, '' );
$in = "quit\n";
ok( $h->finish );
ok( !$? );
is( _map_fds, $fd_map );
##
## stdout only
##
$out    = 'REPLACE ME';
$?      = 99;
$fd_map = _map_fds;
$h      = start \@echoer, \$in, '>pty>', \$out, '2>', \$err;
$in     = "hello\n";
$?      = 0;
pump $h until $out =~ /hello\r?\n/ && $err =~ /HELLO/;
$exp = qr/^hello\r?\n(?!\n)$/;
$out =~ $exp ? ok(1) : is( $out, $exp );
$exp = qr/^HELLO\n(?!\n)$/;
$err =~ $exp ? ok(1) : is( $err, $exp );
is( $in, '' );
$in = "world\n";
$?  = 0;
pump $h until $out =~ /world\r?\n/ && $err =~ /WORLD/;
$exp = qr/^hello\r?\nworld\r?\n(?!\n)$/;
$out =~ $exp ? ok(1) : is( $out, $exp );
$exp = qr/^HELLO\nWORLD\n(?!\n)$/,
  $err =~ $exp ? ok(1) : is( $err, $exp );
is( $in, '' );
$in = "quit\n";
ok( $h->finish );
ok( !$? );
is( _map_fds, $fd_map );
##
## stdin, stdout, stderr
##
$out    = 'REPLACE ME';
$?      = 99;
$fd_map = _map_fds;
$h      = start \@echoer, '<pty<', \$in, '>pty>', \$out;
$in     = "hello\n";
$?      = 0;
pump $h until $out =~ /hello.*hello.*hello\r?\n/is;
## We assume that the slave's write()s are atomic
$exp = qr/^(?:hello\r?\n){3}(?!\n)$/i;
$out =~ $exp ? ok(1) : is( $out, $exp );
is( $in, '' );
$in = "world\n";
$?  = 0;
pump $h until $out =~ /world.*world.*world\r?\n/is;
$exp = qr/^(?:hello\r?\n){3}(?:world\r?\n){3}(?!\n)$/i;
$out =~ $exp ? ok(1) : is( $out, $exp );
is( $in, '' );
$in = "quit\n";
ok( $h->finish );
ok( !$? );
is( _map_fds, $fd_map );

##
## GH #131: run with '>pty>' should not warn when $^W=1
##
{
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };
    local $^W = 1;

    my $pty_out = '';
    IPC::Run::run( [ $^X, '-e', 'print "ok\n"' ], '>pty>', \$pty_out );
    my @pty_warnings = grep { /reopened/ } @warnings;
    is( scalar @pty_warnings, 0, "no 'reopened' warnings with '>pty>' and \$^W=1 (GH #131)" );
}

##
## GH #240: pty slave fd must remain valid after close_terminal in child.
## On some platforms (macOS + IO::Pty 1.21), make_slave_controlling_terminal
## invalidates the cached slave fd; the fix reopens it from the saved ttyname.
## These tests exercise the affected code paths end-to-end.
##
{
    ## '>pty>' with implicit stderr→stdout dup — the exact scenario that
    ## triggered EBADF on affected platforms before the fix.
    my $pty_out = '';
    my $ok = eval {
        IPC::Run::run(
            [ $^X, '-e', 'print STDOUT "out\n"; print STDERR "err\n"' ],
            '>pty>', \$pty_out,
        );
        1;
    };
    ok( $ok, "GH#240: '>pty>' with implicit stderr dup does not EBADF" );
    SKIP: {
        skip( "$^O: pty output may not drain fully with run() on this platform", 1 )
            if $platform_skip;
        like( $pty_out, qr/out/, "GH#240: stdout captured via pty" );
    }
}

{
    ## '>pty>' with explicit separate stderr — exercises the slave fd
    ## reopen path when multiple fds reference the pty after close_terminal.
    my $pty_out = '';
    my $sep_err = '';
    my $ok = eval {
        IPC::Run::run(
            [ $^X, '-e', 'print STDOUT "pty-out\n"; print STDERR "pipe-err\n"' ],
            '>pty>', \$pty_out,
            '2>',    \$sep_err,
        );
        1;
    };
    ok( $ok, "GH#240: '>pty>' with separate '2>' does not EBADF" );
    SKIP: {
        skip( "$^O: pty output may not drain fully with run() on this platform", 1 )
            if $platform_skip;
        like( $pty_out, qr/pty-out/, "GH#240: stdout via pty with separate stderr" );
    }
}
