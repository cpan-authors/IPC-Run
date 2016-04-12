#!/usr/bin/perl

=pod

=head1 NAME

binary.t - Test suite for IPC::Run binary functionality

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

use Test::More tests => 24;
use IPC::Run qw( harness run binary );

sub Win32_MODE();
*Win32_MODE = \&IPC::Run::Win32_MODE;

my $crlf_text = "Hello World\r\n";

my $text = $crlf_text;
$text =~ s/\r//g if Win32_MODE;

my $nl_text = $crlf_text;
$nl_text =~ s/\r//g;

my @perl = ($^X);

my $emitter_script = q{ binmode STDOUT; print qq{Hello World\r\n} };
my @emitter = ( @perl, '-e', $emitter_script );

my $reporter_script = q{ binmode STDIN; $_ = join q{}, <>; s/([\000-\037])/sprintf qq{\\\\0x%02x}, ord $1/ge; print };
my @reporter = ( @perl, '-e', $reporter_script );

my $in;
my $out;
my $err;

sub f($) {
    my $s = shift;
    $s =~ s/([\000-\027])/sprintf "\\0x%02x", ord $1/ge;
    $s;
}

## Parsing tests
is( eval { harness [], '>', binary, \$out } ? 1 : $@, 1 );
is( eval { harness [], '>', binary, "foo" } ? 1 : $@, 1 );
is( eval { harness [], '<', binary, \$in }  ? 1 : $@, 1 );
is( eval { harness [], '<', binary, "foo" } ? 1 : $@, 1 );

## Testing from-kid now so we can use it to test stdin later
ok( run( \@emitter, ">", \$out ) );
is( f($out), f($text), "no binary" );

ok( run( \@emitter, ">", binary, \$out ) );
is( f($out), f($crlf_text), "out binary" );

ok( run( \@emitter, ">", binary(0), \$out ) );
is( f($out), f($text), "out binary 0" );

ok( run( \@emitter, ">", binary(1), \$out ) );
is( f($out), f($crlf_text), "out binary 1" );

## Test to-kid
ok( run( \@reporter, "<", \$nl_text, ">", \$out ) );
is( $out, "Hello World" . ( Win32_MODE ? "\\0x0d" : "" ) . "\\0x0a", "reporter < \\n" );

ok( run( \@reporter, "<", binary, \$nl_text, ">", \$out ) );
is( $out, "Hello World\\0x0a", "reporter < binary \\n" );

ok( run( \@reporter, "<", binary, \$crlf_text, ">", \$out ) );
is( $out, "Hello World\\0x0d\\0x0a", "reporter < binary \\r\\n" );

ok( run( \@reporter, "<", binary(0), \$nl_text, ">", \$out ) );
is( $out, "Hello World" . ( Win32_MODE ? "\\0x0d" : "" ) . "\\0x0a", "reporter < binary(0) \\n" );

ok( run( \@reporter, "<", binary(1), \$nl_text, ">", \$out ) );
is( $out, "Hello World\\0x0a", "reporter < binary(1) \\n" );

ok( run( \@reporter, "<", binary(1), \$crlf_text, ">", \$out ) );
is( $out, "Hello World\\0x0d\\0x0a", "reporter < binary(1) \\r\\n" );
