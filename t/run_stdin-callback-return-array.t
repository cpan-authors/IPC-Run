# Demonstrate Perl IPC::Run stdin callback problem returning array
# by David Paul Christensen dpchrist@holgerdanske.com
# Public Domain

use strict;
use warnings;

use IPC::Run qw( run );
use Test::More tests => 9;

my @cmd = ("true");
if ($^O eq 'MSWin32') {
  @cmd = ( $^X, '-e', 'exit 0' );
}
our ( $i, @i );
my ( $in, @in );

ok( run( \@cmd ) == 1, "no callback" );    #     1
ok( run( \@cmd, sub { return undef } ) == 1, "undef" );             #     2
ok( run( \@cmd, sub { return "" } ) == 1,    "empty string" );      #     3
ok( run( \@cmd, sub { return () } ) == 1,    "empty array" );       #     4
ok( run( \@cmd, sub { return $i } ) == 1,    "package scalar" );    #     5
ok( run( \@cmd, sub { return $in } ) == 1,   "lexical scalar" );    #     6
ok(
    run( \@cmd, sub { my @a; return @a } ) == 1,
    "block lexical array"
);                                                                  #     7
ok( run( \@cmd, sub { return @i } ) == 1,  "package array" );       #     8
ok( run( \@cmd, sub { return @in } ) == 1, "lexical array" );       #     9
