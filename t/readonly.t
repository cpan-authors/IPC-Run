#!perl

# Test script to reproduce error:
#   Modification of a read-only value attempted at //ms/dist/perl5/PROJ/IPC-Run/0.79/lib/perl5/IPC/Run.pm line 1695
#
# Global $_ is set to a Readonly value when IPC::run() is called.
# Note that in test below, $value (which is $_) is not actually passed to IPC::run()
#

use strict;
use warnings;

use IPC::Run 'run';
use Test::More qw( no_plan );
use Readonly;

my @lowercase = 'a' .. 'c';
Readonly::Array my @UPPERCASE => 'A' .. 'C';
Readonly my @MIXEDCASE        => qw( X y Z );

run_echo($_) for ( @lowercase, @UPPERCASE, @MIXEDCASE );

sub run_echo {
    my $value = shift;

    #   my @args = ( '/bin/echo', $value );
    my @args = ( '/bin/echo', 'hello' );

    my $t = "test case '$value': '@args'";
    diag("Running $t");

    my ( $in, $out, $err );
    my $rv = run( [@args], \$in, \$out, \$err )
      or die "Cannot run @args: $err";
    ok( $rv, "Ran $t: OK" );
    diag($out);
}
