use strict;
use warnings;

use IPC::Run qw( harness );
use Test::More tests => 10;

my @perl = ($^X);
my @cmd1 = ( @perl, '-e', q{ exit 0 } );
my @cmd2 = ( @perl, '-e', q{ kill 'KILL', $$ } );
my @cmd3 = ( @perl, '-e', q{ exit 42 } );
my $h = harness( \@cmd1, '&', \@cmd2, '&', \@cmd3 );
$h->run;

is_deeply( [$h->results], [ 0, 0, 42 ], 'Results of all processes');
is( $h->result, 42, 'First non-zero result' );
is( $h->result( 0 ), 0, 'Result of the first process' );
is( $h->result( 1 ), 0, 'Result of the second process' );
is( $h->result( 2 ), 42, 'Result of the third process' );

is_deeply( [$h->full_results], [ 0, 9, 10752 ], 'Full results of all processes');
is( $h->full_result, 9, 'First non-zero full result' );
is( $h->full_result( 0 ), 0, 'Full result of the first process' );
is( $h->full_result( 1 ), 9, 'Full result of the second process' );
is( $h->full_result( 2 ), 10752, 'Full result of the third process' );
