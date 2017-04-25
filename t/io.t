#!/usr/bin/perl

=pod

=head1 NAME

io.t - Test suite exercising IPC::Run::IO with IPC::Run::run.

=cut

use strict;

BEGIN {
    $|  = 1;
    $^W = 1;
    if ( $ENV{PERL_CORE} ) {
        chdir '../lib/IPC/Run' if -d '../lib/IPC/Run';
        unshift @INC, 'lib', '../..';
        $^X = '../../../t/' . $^X;
    }
}

use Test::More tests => 14;
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

is( io( 'foo', '<',  \$send )->mode, 'w' );
is( io( 'foo', '<<', \$send )->mode, 'wa' );
is( io( 'foo', '>',  \$recv )->mode, 'r' );
is( io( 'foo', '>>', \$recv )->mode, 'ra' );

SKIP: {
    if ( IPC::Run::Win32_MODE() ) {
        skip( "$^O does not allow select() on non-sockets", 9 );
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
}
