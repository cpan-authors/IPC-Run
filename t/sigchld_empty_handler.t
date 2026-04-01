use strict;
use warnings;

# Test that _select_loop handles $SIG{CHLD} set to '' (empty string)
# and 'DEFAULT' without emitting 'SIGCHLD handler "" not defined' warnings.
# This mirrors the fix for $SIG{PIPE} in GH#242: the same pattern
# of overriding undef/''/'DEFAULT' should apply to SIGCHLD.
# Observed on Cygwin smokers where $SIG{CHLD} was '' (empty string).

use IPC::Run qw( run );
use Test::More;

plan tests => 4;

# Test 1-2: $SIG{CHLD} = '' (empty string)
{
    my @warn;
    local $SIG{__WARN__} = sub { push @warn, @_ };
    local $SIG{CHLD}     = '';

    my ( $out, $err ) = ( '', '' );

    # Use a child that produces output to ensure pump loop runs
    # and SIGCHLD can be delivered during select()
    my $ok = eval {
        run [ $^X, '-e', 'print "x" x 1000; exit 0' ], \undef, \$out, \$err;
        1;
    };

    ok( $ok, 'run() completes when $SIG{CHLD} is empty string' );

    my @chld_warns = grep { /SIGCHLD.*handler.*not defined/i } @warn;
    is( scalar @chld_warns, 0,
        'no "SIGCHLD handler not defined" warnings with $SIG{CHLD} = ""' )
        or diag "Got warnings: @chld_warns";
}

# Test 3-4: $SIG{CHLD} = 'DEFAULT'
{
    my @warn;
    local $SIG{__WARN__} = sub { push @warn, @_ };
    local $SIG{CHLD}     = 'DEFAULT';

    my ( $out, $err ) = ( '', '' );
    my $ok = eval {
        run [ $^X, '-e', 'print "x" x 1000; exit 0' ], \undef, \$out, \$err;
        1;
    };

    ok( $ok, 'run() completes when $SIG{CHLD} is DEFAULT' );

    my @chld_warns = grep { /SIGCHLD.*handler.*not defined/i } @warn;
    is( scalar @chld_warns, 0,
        'no warnings with $SIG{CHLD} = DEFAULT' )
        or diag "Got warnings: @chld_warns";
}
