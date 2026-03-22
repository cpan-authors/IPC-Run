#!perl

# Test for regression introduced in 20180523.0 (PR #118):
# Passing bare undef to run() crashed with
# "Modification of a read-only value attempted" at the bless() call in
# harness() because $_ in map aliases read-only literal undef arguments.
#
# Before 20180523.0, bare undef arguments were silently absorbed via the
# !ref $_ branch in the harness() parsing loop (equivalent to a no-op).
# See: https://github.com/cpan-authors/IPC-Run/issues/124

use strict;
use warnings;

use Test::More tests => 4;
use IPC::Run qw( run );

my ( $out, $err );

# Bare undef at end of arg list should not die
$out = $err = '';
ok(
    eval { run( [$^X, '-e', '1'], \undef, \$out, \$err, undef ); 1 },
    'run() with trailing bare undef does not die'
) or diag("Error: $@");

# Bare undef with \undef as stdin and named vars for output
$out = $err = '';
ok(
    eval { run( [$^X, '-e', '1'], \undef, \$out, undef ); 1 },
    'run() with bare undef mixed in args does not die'
) or diag("Error: $@");

# Bare undef only (no redirections at all besides the command)
ok(
    eval { run( [$^X, '-e', '1'], undef ); 1 },
    'run() with single bare undef does not die'
) or diag("Error: $@");

# Multiple bare undefs
ok(
    eval { run( [$^X, '-e', '1'], undef, undef, undef ); 1 },
    'run() with multiple bare undefs does not die'
) or diag("Error: $@");
