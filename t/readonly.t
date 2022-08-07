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
use Test::More;

$] > 5.014 or plan skip_all => q{IPC::Run doesn't support Readonly below 5.14};

BEGIN {
    eval 'use Readonly';
    $INC{'Readonly.pm'} or plan skip_all => "Readonly is required for this test to work.";
}

my @lowercase = 'a' .. 'c';
Readonly::Array my @UPPERCASE => 'A' .. 'C';
Readonly my @MIXEDCASE        => qw( X y Z );

run_echo($_) for ( @lowercase, @UPPERCASE, @MIXEDCASE );

done_testing();
exit;

sub run_echo {
    my $value = shift;

    #   my @args = ( '/bin/echo', $value );
    my @args = ( '/bin/echo', 'hello' );
    if ($^O eq 'MSWin32') {
        @args = ( $^X, '-e', 'print "hello\n"' );
    }

    my $t = "test case '$value': '@args'";
    note("Running $t");

    my ( $in, $out, $err );
    my $rv = run( [@args], \$in, \$out, \$err )
      or die "Cannot run @args: $err";
    ok( $rv, "Ran $t: OK" );
    note($out);
}
