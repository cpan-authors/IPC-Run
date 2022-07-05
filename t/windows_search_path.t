#!perl -w

use strict;
use warnings;

use Test::More tests => 11;
use IPC::Run;

{
    no warnings;
    sub IPC::Run::Win32_MODE { 1 }
}

my $ismsys = $^O eq 'msys';     # save it before being ovrwritten below

is( IPC::Run::Win32_MODE, 1, "We're win32 mode?" );
$^O = 'Win32';

# Proves that files in subdirs with . still work.
mkdir '5.11.5';
my @tests = qw(
  ./temp ./temp.EXE
  .\\temp .\\temp.EXE
  ./5.11.5/temp ./5.11.5/temp.EXE
  ./5.11.5/temp ./5.11.5/temp.COM

);

if ($ismsys) {
    { local $TODO = "Windows/msys does not accept .BAT as executables"; }
    SKIP: {
        skip "Windows/msys does not accept .BAT as executables", 2;
    }
}
else {
    push @tests, qw(
      ./5.11.5/temp ./5.11.5/temp.BAT
    );
}

while (@tests) {
    my $path   = shift @tests;
    my $result = shift @tests;

    touch($result);
    my $got = eval { IPC::Run::_search_path($path) };
    is( $@,   '',      "No error calling _search_path for '$path'" );
    is( $got, $result, "Executable $result found" );
    unlink $result;
}

exit;

sub touch {
    my $file = shift;
    open( FH, ">$file" ) or die;
    print FH 1 or die;
    close FH   or die;
    chmod( 0700, $file ) or die;
}

sub END {
    rmdir('5.11.5');
}
