#!/usr/bin/perl

=pod

=head1 NAME

pty_error_handling.t - Test error handling when PTY creation fails

=cut

use strict;
use warnings;

BEGIN {
    $|  = 1;
    $^W = 1;
    if ( $ENV{PERL_CORE} ) {
        chdir '../lib/IPC/Run' if -d '../lib/IPC/Run';
        unshift @INC, 'lib', '../..';
        $^X = '../../../t/' . $^X;
    }
}

use Test::More;

BEGIN {
    if ( !eval { require IO::Pty; } ) {
        plan skip_all => "IO::Pty not installed";
    }
    elsif ( !eval { IO::Pty->VERSION('1.25'); 1 } ) {
        plan skip_all => "IO::Pty >= 1.25 required (have $IO::Pty::VERSION)";
    }
    else {
        plan tests => 3;
    }
}

use IPC::Run qw( start );

# Test that PTY allocation failure is reported as an exception
# rather than crashing with an unhandled error.

# Save the original _pty function
my $orig_pty = \&IPC::Run::_pty;

{
    # Mock _pty to simulate allocation failure
    no warnings 'redefine';
    local *IPC::Run::_pty = sub {
        die "mock: PTY allocation failed\n";
    };

    my $out = '';
    my $err = '';
    my $h;
    my $ok = eval {
        $h = start [ $^X, '-e', 'print "hello\n"' ],
            '<pty<', \my $in,
            '>',     \$out,
            '2>',    \$err;
        1;
    };
    my $error = $@;

    ok( !$ok, 'start() fails when PTY allocation fails' );
    like( $error, qr/PTY allocation failed/,
        'error message propagates from _pty()' );

    # Verify no PTY handles leaked (harness should clean up)
    ok( !defined $h || !$h->{PTYS} || !grep { defined $_ } values %{ $h->{PTYS} || {} },
        'no PTY handles leaked after allocation failure' );
}
