use strict;
use warnings;

use IPC::Run qw( harness );
use Test::More tests => 7;

my @perl  = ($^X);
my @exit0 = ( @perl, '-e', q{ exit 0 } );

# Test 1: finished() returns false before harness is started
{
    my $h = harness( \@exit0 );
    ok( !$h->finished, 'finished() is false before start' );
}

# Test 2: finished() returns false while harness is running
{
    my $h = harness( \@exit0 );
    $h->start;
    # We can't reliably test "during" execution for such a short process,
    # but we can confirm it returns true after finish.
    $h->finish;
    ok( $h->finished, 'finished() is true after finish' );
}

# Test 3: finished() returns true after run()
{
    my $h = harness( \@exit0 );
    $h->run;
    ok( $h->finished, 'finished() is true after run()' );
}

# Test 4: finished() works with all-zero exit codes (the ambiguous case from issue #93)
# result() returns undef for all-zero exits, but finished() should still return true
{
    my @exit0b = ( @perl, '-e', q{ exit 0 } );
    my $h = harness( \@exit0, '&', \@exit0b );
    $h->run;
    ok( !$h->result,   'result() returns false when all children exit 0' );
    ok( $h->finished, 'finished() is true even when all children exit 0' );
}

# Test 5: finished() returns false before run, true after — same harness reused
{
    my $h = harness( \@exit0 );
    ok( !$h->finished, 'finished() false before run (reuse check)' );
    $h->run;
    ok( $h->finished, 'finished() true after run (reuse check)' );
}
