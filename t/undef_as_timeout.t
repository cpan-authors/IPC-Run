#!/usr/bin/perl

=pod

=head1 NAME

undef_as_timeout.t - Test that undef passed as a timeout argument is silently ignored

=head1 DESCRIPTION

Regression test for GitHub issue #128:
"Unopened filehandle in output redirect" when passing undef as timeout.

When undef is passed where a timeout object would go, it should be silently
ignored rather than being misidentified as a filehandle destination.

=cut

use strict;
use warnings;

use Test::More tests => 4;
use IPC::Run qw( run start );

my $output = '';
my $func = sub { $output .= $_[0] };

# Test 1: undef as timeout with run() + coderefs (exact case from issue #128)
{
    my $input;
    my $timeout;
    my $ok = eval {
        run( [ $^X, '-e', 'print "foo\n"' ], \$input, $func, $func, $timeout );
        1;
    };
    ok( $ok, 'run() with undef timeout does not die' )
        or diag("Error: $@");
}

# Test 2: output was captured correctly
like( $output, qr/foo/, 'output was captured correctly with undef timeout' );

# Test 3: undef as timeout with start()
{
    my $timeout;
    my $out = '';
    my $h = eval {
        start( [ $^X, '-e', 'print "bar\n"' ], '>', \$out, $timeout );
    };
    ok( $h, 'start() with undef timeout does not die' )
        or diag("Error: $@");
    $h->finish if $h;
    like( $out, qr/bar/, 'output captured correctly via start() with undef timeout' );
}
