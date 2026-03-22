#!/usr/bin/perl

=pod

=head1 NAME

undef_args.t - Test that passing undef (or \undef) to run/harness does not die

=head1 DESCRIPTION

Regression test for https://github.com/cpan-authors/IPC-Run/issues/139

Passing C<undef> or C<\undef> as stdin/stdout/stderr should not cause:
  "Modification of a read-only value attempted"

=cut

use strict;
use warnings;

use Test::More tests => 6;
use IPC::Run qw( run harness );

my @cmd;
if ( $^O eq 'MSWin32' ) {
    @cmd = ( $^X, '-e', 'print "hello\n"' );
}
else {
    @cmd = ( $^X, '-e', 'print "hello\n"' );
}

# undef as stdin (the original failing case from the issue)
{
    my ( $out, $err );
    my $ok = eval { run( \@cmd, undef, \$out, \$err ) };
    ok( !$@,  'run with undef stdin does not die' );
    ok( $ok,  'run with undef stdin succeeds' );
}

# \undef as stdin
{
    my ( $out, $err );
    my $ok = eval { run( \@cmd, \undef, \$out, \$err ) };
    ok( !$@,  'run with \\undef stdin does not die' );
    ok( $ok,  'run with \\undef stdin succeeds' );
}

# undef as stdout
{
    my ( $in, $err ) = ( '', '' );
    my $ok = eval { run( \@cmd, \$in, undef, \$err ) };
    ok( !$@,  'run with undef stdout does not die' );
}

# undef as stderr
{
    my ( $in, $out ) = ( '', '' );
    my $ok = eval { run( \@cmd, \$in, \$out, undef ) };
    ok( !$@,  'run with undef stderr does not die' );
}
