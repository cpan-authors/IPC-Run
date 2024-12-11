#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use IPC::Run 'run';
use File::Spec;
use Cwd 'getcwd';

plan skip_all => 'Skipping on Win32' if $ENV{GITHUB_WINDOWS_TESTING};
plan skip_all => 'Skipping when not on Win32' unless $^O eq 'MSWin32';
run_tests();
done_testing;

sub run_tests {
    chdir "eg";    # so we don't have to have files in project root
    ## The 2 on the space bat prevents accidentally running the normal one.
    my @summary;
    my %seen;
    test_set(
        \@summary,
        reverse sort map +( $seen{$_}++ ? () : ($_) ),
        map {
            my $slash     = $_;
            my $abs_slash = my $abs = File::Spec->rel2abs($_);
            $slash     =~ s@/@\\@g;
            $abs_slash =~ s@\\@/@g;
            ( $_, /\// ? ($slash) : (), $abs, $abs_slash )
        } (
            "ipctest.bat",
            "ipctest2 space.bat",
            "./ipctest.bat",
            "./ipctest2 space.bat",
            "dirnospace/ipctest.bat",
            "dirnospace/ipctest2 space.bat",
            "dir space/ipctest.bat",
            "dir space/ipctest2 space.bat"
        )
    );
    note join "\n", "\nSUMMARY:", @summary, " ";
    return;
}

sub test_set {
    my ( $summary, @tests ) = @_;
    push @{$summary}, "\n\ntests:\n", @tests, " ", "successes:\n";
    check( $summary, $_ ) for @tests;
    return;
}

sub check {
    my ( $summary, $executable ) = @_;
    note "\ntest '$executable'";
    my $t;
    my $r = eval {
        run [ $executable, "meep marp" ], ">", \my $out;
        $t = is $out, qq[\"meep marp\"\n], "output was correct";
        1;
    };
    push @{$summary}, $executable if $t;
    fail "died with '$@'" if !$r;
    return;
}
