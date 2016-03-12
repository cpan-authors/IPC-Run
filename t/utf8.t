use Test::More;
BEGIN {
	if ($^O eq 'MSWin32') {
		plan skip_all => "no cat on Windows"; #and "cmd /C type con" reads from real STDIN
	} else {
		plan tests => 4;
	}
}

use strict;
use warnings;
use IPC::Run ();
use Encode   ();

##### data setup and sanity check
my $unicode_string = "string\x{2026}";
my $byte_string    = "string\xE2\x80\xA6";

## make sure what we're doing doesn't incidentally change the data and that the data is what we expect
my $x = Encode::decode_utf8($byte_string);
isnt( $x, $byte_string, "Encode::decode_utf8() does not lvalue our bytes string var" );
is( $unicode_string, Encode::decode_utf8($byte_string), "byte string and unicode string same string as far as humans are concerned" );

##### actual IPC::Run::run() tests
my $bytes_out;

## Test using the byte string: "cat" should be transparent.
IPC::Run::run( ["cat"], \$byte_string, \$bytes_out );
is( $bytes_out, $byte_string, "run() w/ byte string" );

##  Same test using the Unicode string
IPC::Run::run( ["cat"], \$unicode_string, \$bytes_out );
is( Encode::decode_utf8($bytes_out), $unicode_string, "run() w/ unicode string" );
