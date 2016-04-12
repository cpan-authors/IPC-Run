#!/usr/bin/perl

=pod

=head1 NAME

parallel.t - Test suite for running multiple processes in parallel.

=cut

use strict;

BEGIN {
    $|  = 1;
    $^W = 1;
    if ( $ENV{PERL_CORE} ) {
        chdir '../lib/IPC/Run' if -d '../lib/IPC/Run';
        unshift @INC, 'lib', '../..';
        $^X = '../../../t/' . $^X;
    }
}

## Handy to have when our output is intermingled with debugging output sent
## to the debugging fd.
select STDERR;
select STDOUT;

BEGIN {
    use Test::More;
    if ( $^O eq 'MSWin32' ) {
        plan skip_all => 'Parallel tests are dangerous on MSWin32';
    }
    else {
        plan tests => 6;
    }

}
use IPC::Run qw( start pump finish );

my $text1 = "Hello world 1\n";
my $text2 = "Hello world 2\n";

my @perl = ($^X);
my @catter = ( @perl, '-pe1' );

my ( $h1,   $h2 );
my ( $out1, $out2 );
$h1 = start \@catter, "<", \$text1, ">", \$out1;
ok($h1);
$h2 = start \@catter, "<", \$text2, ">", \$out2;
ok($h2);
pump $h1;
ok(1);
pump $h2;
ok(1);
finish $h1;
ok(1);
finish $h2;
ok(1);
