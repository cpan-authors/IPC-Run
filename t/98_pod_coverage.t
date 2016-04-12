#!/usr/bin/perl

# Test that the syntax of our POD documentation is valid
use strict;

BEGIN {
    $|  = 1;
    $^W = 1;
}

my @MODULES = (
    'Test::Pod::Coverage 1.04',
);

# Don't run tests during end-user installs
use Test::More;
unless ( $ENV{AUTOMATED_TESTING} or $ENV{RELEASE_TESTING} ) {
    plan( skip_all => "Author tests not required for installation" );
}

# Load the testing modules
foreach my $MODULE (@MODULES) {
    eval "use $MODULE";
    if ($@) {
        $ENV{RELEASE_TESTING}
          ? die("Failed to load required release-testing module $MODULE")
          : plan( skip_all => "$MODULE not available for testing" );
    }
}
plan tests => 7;

#my $private_subs = { private => [qr/foo_fizz/]};
#pod_coverage_ok('IPC::Run', $private_subs, "Test IPC::Run that all modules are documented.");

pod_coverage_ok( 'IPC::Run',        "Test IPC::Run that all modules are documented." );
pod_coverage_ok( 'IPC::Run::Debug', "Test IPC::Run::Debug that all modules are documented." );
pod_coverage_ok( 'IPC::Run::IO',    "Test IPC::Run::IO that all modules are documented." );
pod_coverage_ok( 'IPC::Run::Timer', "Test IPC::Run::Timer that all modules are documented." );
TODO: {
    local $TODO = "These modules are not fully documented yet.";
    pod_coverage_ok( 'IPC::Run::Win32Helper', "Test IPC::Run::Win32Helper that all modules are documented." );
    pod_coverage_ok( 'IPC::Run::Win32IO',     "Test IPC::Run::Win32IO that all modules are documented." );
    pod_coverage_ok( 'IPC::Run::Win32Pump',   "Test IPC::Run::Win32Pump that all modules are documented." );
}
