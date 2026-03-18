#!/usr/bin/perl

=pod

=head1 NAME

started.t - Tests for IPC::Run->started() method

=cut

use strict;
use warnings;

use Test::More tests => 5;
use IPC::Run qw( harness start finish );

my @perl = ($^X);
my @cmd  = ( @perl, '-e', q{ exit 0 } );

# Test 1: harness is not started before start()
my $h = harness( \@cmd );
ok( !$h->started, 'harness not started before start()' );

# Test 2: harness is started after start()
$h->start;
ok( $h->started, 'harness started after start()' );

# Test 3: harness is not started after finish()
$h->finish;
ok( !$h->started, 'harness not started after finish()' );

# Test 4: harness is started again after re-start()
$h->start;
ok( $h->started, 'harness started again after re-start()' );
$h->finish;

# Test 5: start() function also returns a started harness
my $h2 = start( \@cmd );
ok( $h2->started, 'harness returned by start() is started' );
$h2->finish;
