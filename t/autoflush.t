use strict;
use warnings;

use File::Spec;
use IPC::Run;
use Test::More tests => 4;

my $devnull = File::Spec->devnull;

STDOUT->autoflush();
my $flush = sprintf( "AUTOFLUSH %s: %d", select, $| );
is( $flush, "AUTOFLUSH main::STDOUT: 1", "Autoflush set" );

IPC::Run::run( [ $^X, '-V' ], '1>', $devnull, '2>', $devnull );

$flush = sprintf( "AUTOFLUSH %s: %d", select, $| );
is( $flush, "AUTOFLUSH main::STDOUT: 1", "Autoflush still set" );

STDOUT->autoflush(0);
$flush = sprintf( "AUTOFLUSH %s: %d", select, $| );
is( $flush, "AUTOFLUSH main::STDOUT: 0", "Autoflush unset" );

IPC::Run::run( [ $^X, '-V' ], '1>', $devnull, '2>', $devnull );

$flush = sprintf( "AUTOFLUSH %s: %d", select, $| );
is( $flush, "AUTOFLUSH main::STDOUT: 0", "Autoflush still unset" );
