#!/usr/bin/perl

=pod

=head1 NAME

io.t - Test suite exercising IPC::Run::IO with IPC::Run::run.

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

use Test::More tests => 18;
use IPC::Run qw( :filters run io );
use IPC::Run::Debug qw( _map_fds );

my $text           = "Hello World\n";
my $emitter_script = qq{print '$text'; print STDERR uc( '$text' )};
##
## $^X is the path to the perl binary.  This is used run all the subprocesses.
##
my @perl = ($^X);
my @emitter = ( @perl, '-e', $emitter_script );

my $recv;
my $send;

my $in_file  = 'io.t.in';
my $out_file = 'io.t.out';
my $err_file = 'io.t.err';

my $io;
my $r;

my $fd_map;

## TODO: Test filters, etc.

sub slurp($) {
    my ($f) = @_;
    open( S, "<$f" ) or return "$! '$f'";
    my $r = join( '', <S> );
    close S or warn "$! closing '$f'";
    return $r;
}

sub spit($$) {
    my ( $f, $s ) = @_;
    open( S, ">$f" ) or die "$! '$f'";
    print S $s or die "$! '$f'";
    close S or die "$! '$f'";
}

sub wipe($) {
    my ($f) = @_;
    unlink $f or warn "$! unlinking '$f'" if -f $f;
}

$io = io( 'foo', '<', \$send );
ok $io->isa('IPC::Run::IO');

# Error message should report the invalid operator (not $_ which would be empty)
{
    my $bad_op = 'BOGUS';
    eval { io( 'foo', $bad_op, \$send ) };
    like( $@, qr/\Q$bad_op\E/, "invalid operator reported in error message" );
}

# io() should accept a GLOB reference (rt.cpan.org #111214)
{
    local *MYHANDLE;
    open( MYHANDLE, '<', \$send ) or die "open: $!";
    $io = io( \*MYHANDLE, '<', \$send );
    ok $io->isa('IPC::Run::IO'), "io() accepts a GLOB reference";
    close MYHANDLE;
}

is( io( 'foo', '<',  \$send )->mode, 'w' );
is( io( 'foo', '<<', \$send )->mode, 'wa' );
is( io( 'foo', '>',  \$recv )->mode, 'r' );
is( io( 'foo', '>>', \$recv )->mode, 'ra' );

SKIP: {
    if ( IPC::Run::Win32_MODE() ) {
        skip( "$^O does not allow select() on non-sockets", 11 );
    }

    ##
    ## Input from a file
    ##
  SCOPE: {
        spit $in_file, $text;
        $recv   = 'REPLACE ME';
        $fd_map = _map_fds;
        $r      = run io( $in_file, '>', \$recv );
        wipe $in_file;
        ok($r);
    }

    ok( !$? );
    is( _map_fds, $fd_map );
    is( $recv,    $text );

    ##
    ## Output to a file
    ##
  SCOPE: {
        wipe $out_file;
        $send   = $text;
        $fd_map = _map_fds;
        $r      = run io( $out_file, '<', \$send );
        $recv   = slurp $out_file;
        wipe $out_file;
        ok($r);
    }

    ok( !$? );
    is( _map_fds, $fd_map );
    is( $send,    $text );
    is( $recv,    $text );

    ##
    ## Filter exception propagation — error messages should not be corrupted
    ##
  SCOPE: {
        spit $in_file, $text;
        my $err_msg = "deliberate filter error for testing";
        eval {
            run io( $in_file, '>',
                sub { die $err_msg },
                \$recv );
        };
        wipe $in_file;
        like( $@, qr/\Q$err_msg\E/, "filter exception propagated from io()" );
        unlike( $@, qr/\back\b/,    "filter exception not prefixed with debug artifact" );
    }
}
