use strict;
use warnings;

use IPC::Run;
use Test::More tests => 3;

my $nl = $^O eq 'MSWin32' ? "\r\n" : "\n";

my $h = IPC::Run::start( [ $^X, '-le', 'for (1..10) { print $_ }' ], '>pipe', my $fh );
ok $h;
my @content = <$fh>;
is_deeply \@content, [ map { "$_$nl" } (1..10) ];
ok $h->finish;
