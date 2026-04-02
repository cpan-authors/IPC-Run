#!/usr/bin/perl

=pod

=head1 NAME

false_string_input.t - Verify that Perl-false strings like "0" are
correctly piped to child stdin.

=cut

use strict;

BEGIN {
    $| = 1;
    $^W = 1;
    if ( $ENV{PERL_CORE} ) {
        chdir '../lib/IPC/Run' if -d '../lib/IPC/Run';
        unshift @INC, 'lib', '../..';
        $^X = '../../../t/' . $^X;
    }
}

use Test::More;
use IPC::Run qw( run );

BEGIN {
    if ( IPC::Run::Win32_MODE() ) {
        plan skip_all => 'Skipping on Win32';
        exit(0);
    }
    else {
        plan tests => 3;
    }
}

# The string "0" is false in Perl boolean context but is valid input
# that must be written to the child's stdin.
{
    my $in  = "0";
    my $out = '';
    ok( run( [ $^X, '-e', 'print <STDIN>' ], \$in, \$out ), 'run() with "0" input succeeds' );
    is( $out, "0", 'child receives "0" on stdin' );
}

# Also verify "0" works as part of a larger pipeline (start/pump/finish)
{
    my $in  = "0";
    my $out = '';
    my $h   = IPC::Run::start( [ $^X, '-e', 'print <STDIN>' ], \$in, \$out );
    $h->finish;
    is( $out, "0", 'start/finish with "0" input delivers data' );
}
