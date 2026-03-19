use strict;
use warnings;

# Test that result() and friends don't emit "isn't numeric" warnings
# when $SIG{CHLD} is 'IGNORE' (which causes waitpid to return -1,
# setting RESULT to the string "unknown result, unknown PID").
# See https://github.com/cpan-authors/IPC-Run/issues/169

use IPC::Run qw( start );
use Test::More;

plan tests => 5;

my @warn;
local $SIG{__WARN__} = sub { push @warn, @_ };
local $SIG{CHLD}     = 'IGNORE';

my ( $in, $out, $err ) = ( '', '', '' );
my $h = start [ $^X, '-e', 'exit 0' ], \$in, \$out, \$err;

eval { $h->finish };

# The harness may or may not finish cleanly with SIGCHLD ignored,
# but calling the result accessors must not warn.
@warn = ();

my $r  = $h->result(0);
my @rs = $h->results;
my $fr = $h->full_result(0);
my @frs = $h->full_results;

# Also test the no-argument forms
my $r_noarg  = $h->result;
my $fr_noarg = $h->full_result;

is( scalar @warn, 0, 'no warnings from result accessors with SIGCHLD IGNORE' )
    or diag "Got warnings: @warn";

# When SIGCHLD is IGNORE, results are 0 (the string coerces to 0)
is( $r, 0, 'result(0) returns 0 for unknown result' );
is_deeply( \@rs, [0], 'results() returns list of 0 for unknown result' );
ok( defined $fr, 'full_result(0) returns a defined value' );
ok( defined $frs[0], 'full_results() returns defined values' );
