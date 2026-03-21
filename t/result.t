use strict;
use warnings;

use IPC::Run qw( harness start finish );
use Test::More tests => 14;

my $has_test_warn = eval { require Test::Warn; Test::Warn->import; 1 };

my @perl   = ($^X);
my @exit0  = ( @perl, '-e', q{ exit 0 } );
my @exit42 = ( @perl, '-e', q{ exit 42 } );
my ( @cmds, @expect_full, $first_nonzero, $first_nonzero_full );
if (IPC::Run::Win32_MODE) {
    require IPC::Run::Win32Process;
    require Math::BigInt;

    # Perl exit() doesn't preserve these high exit codes, but cmd.exe does.
    my $exit_max_shifted = IPC::Run::Win32Process->new(
        $ENV{COMSPEC},
        q{cmd.exe /c exit 16777215}
    );
    my $exit_max = IPC::Run::Win32Process->new(
        $ENV{COMSPEC},
        q{cmd.exe /c exit 4294967295}
    );

    # Construct 0xFFFFFFFF00 in a way that works on !USE_64_BIT_INT builds.
    my $expect_exit_max = Math::BigInt->new(0xFFFFFFFF);
    $expect_exit_max->blsft(8);

    @cmds = ( \@exit0, '&', $exit_max, '&', $exit_max_shifted, '&', \@exit42 );
    @expect_full        = ( 0, $expect_exit_max, 0xFFFFFF00, 42 << 8 );
    $first_nonzero      = 0xFFFFFFFF;
    $first_nonzero_full = $expect_exit_max;
}
else {
    my @kill9 = ( @perl, '-e', q{ kill 'KILL', $$ } );

    @cmds = ( \@exit0, '&', \@exit0, '&', \@kill9, '&', \@exit42 );
    @expect_full = ( 0, 0, 9, 42 << 8 );
    $first_nonzero      = 42;
    $first_nonzero_full = 9;
}
my $h = harness(@cmds);
$h->run;

is_deeply(
    [ $h->results ], [ map { $_ >> 8 } @expect_full ],
    'Results of all processes'
);
is_deeply(
    [ $h->full_results ], \@expect_full,
    'Full results of all processes'
);
is( $h->result,      $first_nonzero,      'First non-zero result' );
is( $h->full_result, $first_nonzero_full, 'First non-zero full result' );
foreach my $pos ( 0 .. $#expect_full ) {
    is( $h->result($pos), $expect_full[$pos] >> 8, "Result of process $pos" );
    is(
        $h->full_result($pos), $expect_full[$pos],
        "Full result of process $pos"
    );
}

# Test that result() and results() produce no "isn't numeric" warnings
# when SIGCHLD is set to IGNORE (causing RESULT to be "unknown result, unknown PID")
SKIP: {
    skip "No SIGCHLD on Win32", 2 if IPC::Run::Win32_MODE;
    skip "Test::Warn not installed", 2 unless $has_test_warn;
    local $SIG{CHLD} = 'IGNORE';
    my ( $in, $out, $err );
    my $h2 = start( [ $^X, '-e', 'exit 0' ], \$in, \$out, \$err );
    finish($h2);
    Test::Warn::warnings_are( sub { $h2->result(0) }, [], 'result($pos) produces no warnings with SIGCHLD=IGNORE' );
    Test::Warn::warnings_are( sub { $h2->results },   [], 'results() produces no warnings with SIGCHLD=IGNORE' );
}
