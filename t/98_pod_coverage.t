#!perl

use Test::More;

eval "use Test::Pod::Coverage 1.04";
plan skip_all => "Test::Pod::Coverage 1.04 required for testing POD coverage" if $@;

plan tests => 7;

#my $private_subs = { private => [qr/foo_fizz/]};
#pod_coverage_ok('IPC::Run', $private_subs, "Test IPC::Run that all modules are documented.");

pod_coverage_ok('IPC::Run'             , "Test IPC::Run that all modules are documented.");
pod_coverage_ok('IPC::Run::Debug'      , "Test IPC::Run::Debug that all modules are documented.");
pod_coverage_ok('IPC::Run::IO'         , "Test IPC::Run::IO that all modules are documented.");
pod_coverage_ok('IPC::Run::Timer'      , "Test IPC::Run::Timer that all modules are documented.");
pod_coverage_ok('IPC::Run::Win32Helper', "Test IPC::Run::Win32Helper that all modules are documented.");
pod_coverage_ok('IPC::Run::Win32IO'    , "Test IPC::Run::Win32IO that all modules are documented.");
pod_coverage_ok('IPC::Run::Win32Pump'  , "Test IPC::Run::Win32Pump that all modules are documented.");
