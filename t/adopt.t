#!/usr/bin/perl

=pod

=head1 NAME

adopt.t - Test suite for IPC::Run::adopt

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

use Test::More skip_all => 'adopt not implemented yet';

# use Test::More tests => 29;
use IPC::Run qw( start pump finish );

##
## $^X is the path to the perl binary.  This is used run all the subprocesses.
##
my @echoer = ( $^X, '-pe', 'BEGIN { $| = 1 }' );

##
## harness, pump, run
##
SCOPE: {
    my $in  = 'SHOULD BE UNCHANGED';
    my $out = 'REPLACE ME';
    $? = 99;
    my $fd_map = IPC::Run::_map_fds();
    my $h = start( \@echoer, \$in, \$out );
    ok( $h->isa('IPC::Run') );
    ok( $?,   99 );
    ok( $in,  'SHOULD BE UNCHANGED' );
    ok( $out, '' );
    ok( $h->pumpable );
    $in = '';
    $?  = 0;
    pump_nb $h for ( 1 .. 100 );
    ok(1);
    ok( $in,  '' );
    ok( $out, '' );
    ok( $h->pumpable );
}

SCOPE: {
    my $in  = 'SHOULD BE UNCHANGED';
    my $out = 'REPLACE ME';
    $? = 99;
    my $fd_map = IPC::Run::_map_fds();
    my $h = start( \@echoer, \$in, \$out );
    ok( $h->isa('IPC::Run') );
    ok( $?,   99 );
    ok( $in,  'SHOULD BE UNCHANGED' );
    ok( $out, '' );
    ok( $h->pumpable );
    $in = "hello\n";
    $?  = 0;
    pump $h until $out =~ /hello/;
    ok(1);
    ok( !$? );
    ok( $in,  '' );
    ok( $out, "hello\n" );
    ok( $h->pumpable );
    $in = "world\n";
    $?  = 0;
    pump $h until $out =~ /world/;
    ok(1);
    ok( !$? );
    ok( $in,  '' );
    ok( $out, "hello\nworld\n" );
    ok( $h->pumpable );
    warn "hi";
    ok( $h->finish );
    ok( !$? );
    ok( IPC::Run::_map_fds(), $fd_map );
    ok( $out,                 "hello\nworld\n" );
    ok( !$h->pumpable );
}
