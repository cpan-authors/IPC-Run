#!/usr/bin/perl

=pod

=head1 NAME

pump.t - Test suite for IPC::Run::run, etc.

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

use Test::More tests => 27;
use IPC::Run::Debug qw( _map_fds );
use IPC::Run qw( start pump finish timeout );

##
## $^X is the path to the perl binary.  This is used run all the subprocesses.
##
my @echoer = ( $^X, '-pe', 'BEGIN { $| = 1 }' );
my $in;
my $out;
my $h;
my $fd_map;

$in     = 'SHOULD BE UNCHANGED';
$out    = 'REPLACE ME';
$?      = 99;
$fd_map = _map_fds;
$h      = start( \@echoer, \$in, \$out, timeout 5 );
ok( $h->isa('IPC::Run') );
is( $?,   99 );
is( $in,  'SHOULD BE UNCHANGED' );
is( $out, '' );
ok( $h->pumpable );
$in = '';
$?  = 0;
pump_nb $h for ( 1 .. 100 );
ok(1);
is( $in,  '' );
is( $out, '' );
ok( $h->pumpable );
$in = "hello\n";
$?  = 0;
pump $h until $out =~ /hello/;
ok(1);
ok( !$? );
is( $in,  '' );
is( $out, "hello\n" );
ok( $h->pumpable );
$in = "world\n";
$?  = 0;
pump $h until $out =~ /world/;
ok(1);
ok( !$? );
is( $in,  '' );
is( $out, "hello\nworld\n" );
ok( $h->pumpable );

## Test \G pos() restoral
$in  = "hello\n";
$out = "";
$?   = 0;
pump $h until $out =~ /hello\n/g;
ok(1);
is pos($out), 6, "pos\$out";
$in = "world\n";
$?  = 0;
pump $h until $out =~ /\Gworld/gc;
ok(1);
ok( $h->finish );
ok( !$? );
is( _map_fds, $fd_map );
is( $out,     "hello\nworld\n" );
ok( !$h->pumpable );
