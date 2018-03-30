use strict;
use warnings;

use IPC::Run;
use Test::More tests => 4;

if ( $^O !~ /Win32/ ) {
    STDOUT->autoflush();
    my $flush = sprintf( "AUTOFLUSH %s: %d", select, $| );
    is( $flush, "AUTOFLUSH main::STDOUT: 1", "Autoflush set" );

    IPC::Run::run( [ 'perl', '-V' ], '1>', "/dev/null", '2>', "/dev/null" );

    $flush = sprintf( "AUTOFLUSH %s: %d", select, $| );
    is( $flush, "AUTOFLUSH main::STDOUT: 1", "Autoflush still set" );

    STDOUT->autoflush(0);
    $flush = sprintf( "AUTOFLUSH %s: %d", select, $| );
    is( $flush, "AUTOFLUSH main::STDOUT: 0", "Autoflush unset" );

    IPC::Run::run( [ 'perl', '-V' ], '1>', "/dev/null", '2>', "/dev/null" );

    $flush = sprintf( "AUTOFLUSH %s: %d", select, $| );
    is( $flush, "AUTOFLUSH main::STDOUT: 0", "Autoflush still unset" );
}
else {
    my $flush = sprintf( "AUTOFLUSH %s: %d", select, $| );
    is( $flush, "AUTOFLUSH main::STDOUT: 1", "Autoflush set" );

    IPC::Run::run( [ 'perl', '-V' ], '1>', "/dev/null", '2>', "/dev/null" );

    $flush = sprintf( "AUTOFLUSH %s: %d", select, $| );
    is( $flush, "AUTOFLUSH main::STDOUT: 1", "Autoflush still set" );

    { local $TODO = 'Seems to work on at least Strawberry Perl 5.20.0';
    STDOUT->autoflush(0);
    $flush = sprintf( "AUTOFLUSH %s: %d", select, $| );
    is( $flush, "AUTOFLUSH main::STDOUT: 1", "Unseting Autoflush on Windows doesn't work" );
    }

    pass('Finished Windows test');
}
