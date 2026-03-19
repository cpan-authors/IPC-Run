use strict;
use warnings;

use IPC::Run qw( harness );
use Test::More;

plan skip_all => 'No fork on Win32' if IPC::Run::Win32_MODE;

plan tests => 18;

my @perl = ($^X);

# Test pid() and pids() - single process
{
    my $h = harness( [ @perl, '-e', 'sleep 10' ] );
    $h->start;

    ok( defined $h->pid,    'pid() defined while running' );
    ok( $h->pid > 0,        'pid() positive while running' );
    is( $h->pid, $h->pid(0), 'pid() == pid(0)' );

    my @pids = $h->pids;
    is( scalar @pids, 1, 'pids() returns one element for single process' );
    is( $pids[0], $h->pid, 'pids() first element matches pid()' );

    $h->kill_kill;
    $h->finish;
}

# Test pid() and pids() - multiple processes (pipeline)
{
    my ( $out1, $out2 );
    my $h = harness(
        [ @perl, '-e', 'sleep 10' ],
        '|',
        [ @perl, '-e', 'sleep 10' ],
    );
    $h->start;

    my @pids = $h->pids;
    is( scalar @pids, 2, 'pids() returns two elements for pipeline' );
    ok( $pids[0] > 0, 'first pid positive' );
    ok( $pids[1] > 0, 'second pid positive' );
    ok( $pids[0] != $pids[1], 'two different pids' );
    is( $h->pid(1), $pids[1], 'pid(1) matches pids()[1]' );

    $h->kill_kill;
    $h->finish;
}

# Test is_running()
{
    my $h = harness( [ @perl, '-e', 'sleep 10' ] );

    ok( !$h->is_running, 'not running before start()' );

    $h->start;
    ok( $h->is_running, 'running after start()' );

    $h->kill_kill;
    $h->finish;
    ok( !$h->is_running, 'not running after finish()' );
}

# Test full_path() and full_paths()
{
    my $h = harness( [ @perl, '-e', 'exit 0' ] );
    $h->start;

    my $path = $h->full_path;
    ok( defined $path, 'full_path() defined after start()' );
    ok( -e $path,      'full_path() points to an existing file' );
    is( $path, $h->full_path(0), 'full_path() == full_path(0)' );

    my @paths = $h->full_paths;
    is( scalar @paths, 1, 'full_paths() returns one element for single process' );
    is( $paths[0], $path, 'full_paths() first element matches full_path()' );

    $h->finish;
}
