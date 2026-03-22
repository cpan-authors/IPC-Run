#!/usr/bin/perl

=pod

=head1 NAME

search_path_cache.t - Test that _search_path() cache is invalidated when $PATH changes

=head1 DESCRIPTION

Regression test for https://github.com/cpan-authors/IPC-Run/issues/85

IPC::Run caches the resolved path for each command name. If $PATH changes
between calls, the cache should be invalidated so the new $PATH is searched.
A public clearcache() function must also be available for manual purging.

=cut

use strict;
use warnings;

BEGIN {
    $|  = 1;
    $^W = 1;
    if ( $ENV{PERL_CORE} ) {
        chdir '../lib/IPC/Run' if -d '../lib/IPC/Run';
        unshift @INC, 'lib', '../..';
        $^X = '../../../t/' . $^X;
    }
}

use File::Spec ();
use File::Temp qw( tempdir );
use Test::More;

# Windows does not use the same PATH separator or script execution model;
# skip rather than adding complex OS-specific logic to this test.
if ( $^O eq 'MSWin32' or $^O eq 'cygwin' ) {
    plan skip_all => "PATH-change cache tests not supported on $^O";
}

use IPC::Run qw( clearcache );

plan tests => 4;

# -----------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------

sub make_script {
    my ( $dir, $name, $output ) = @_;
    my $path = File::Spec->catfile( $dir, $name );
    open my $fh, '>', $path or die "Cannot write $path: $!";
    print $fh "#!/bin/sh\necho '$output'\n";
    close $fh;
    chmod 0755, $path or die "Cannot chmod $path: $!";
    return $path;
}

# -----------------------------------------------------------------------
# Test 1 & 2: cache is invalidated when $ENV{PATH} changes
# -----------------------------------------------------------------------

SCOPE: {
    my $dir1 = tempdir( CLEANUP => 1 );
    my $dir2 = tempdir( CLEANUP => 1 );

    make_script( $dir1, 'ipcrun_test_cmd', 'from_dir1' );
    make_script( $dir2, 'ipcrun_test_cmd', 'from_dir2' );

    local $ENV{PATH} = "$dir1:$ENV{PATH}";

    # Ensure we start with a clean cache so prior test runs don't interfere.
    clearcache();

    my $out1 = '';
    IPC::Run::run( ['ipcrun_test_cmd'], '>', \$out1 );
    chomp $out1;

    is( $out1, 'from_dir1', 'first run uses command from dir1' );

    # Now change PATH so dir2 comes first, then rerun.
    $ENV{PATH} = "$dir2:$ENV{PATH}";

    my $out2 = '';
    IPC::Run::run( ['ipcrun_test_cmd'], '>', \$out2 );
    chomp $out2;

    is( $out2, 'from_dir2', 'second run uses command from dir2 after PATH change' );
}

# -----------------------------------------------------------------------
# Test 3 & 4: clearcache() forces a fresh PATH search
# -----------------------------------------------------------------------

SCOPE: {
    my $dir1 = tempdir( CLEANUP => 1 );
    my $dir2 = tempdir( CLEANUP => 1 );

    make_script( $dir1, 'ipcrun_test_cmd2', 'cache_dir1' );
    make_script( $dir2, 'ipcrun_test_cmd2', 'cache_dir2' );

    local $ENV{PATH} = "$dir1:$ENV{PATH}";
    clearcache();

    my $out1 = '';
    IPC::Run::run( ['ipcrun_test_cmd2'], '>', \$out1 );
    chomp $out1;
    is( $out1, 'cache_dir1', 'first run populates cache with dir1 entry' );

    # Prepend dir2, then explicitly clear the cache.
    $ENV{PATH} = "$dir2:$ENV{PATH}";
    clearcache();

    my $out2 = '';
    IPC::Run::run( ['ipcrun_test_cmd2'], '>', \$out2 );
    chomp $out2;
    is( $out2, 'cache_dir2', 'after clearcache(), new PATH is searched' );
}
