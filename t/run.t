#!/usr/bin/perl

=pod

=head1 NAME

run.t - Test suite for IPC::Run::run, etc.

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

my @WARNING_MESSAGES;
$SIG{__WARN__} = sub {
    push @WARNING_MESSAGES, @_;
    diag("WARN: $_") foreach (@_);
};

sub get_warnings {
    my @warnings = @WARNING_MESSAGES;
    @WARNING_MESSAGES = ();
    return @warnings;
}

## Handy to have when our output is intermingled with debugging output sent
## to the debugging fd.
select STDERR;
select STDOUT;

use Test::More tests => 268;
use IPC::Run::Debug qw( _map_fds );
use IPC::Run qw( :filters :filter_imp start );

require './t/lib/Test.pm';
IPC::Run::Test->import();

# Must do this this late as plan uses localtime, and localtime on darwin opens
# a file descriptor. Quite probably other operating systems do file descriptor
# things during the test setup.
my $fd_map = _map_fds;

sub run {
    IPC::Run::run( ref $_[0] ? ( noinherit => 1 ) : (), @_ );
}

## Test at least some of the win32 PATHEXT logic
my $perl = $^X;
$perl =~ s/\.\w+\z// if IPC::Run::Win32_MODE();

sub _unlink {
    my ($f) = @_;
    my $tries;
    while () {
        return if unlink $f;
        if ( $^O =~ /Win32/ && ++$tries <= 10 ) {
            print STDOUT "# Waiting for Win32 to allow $f to be unlinked ($!)\n";
            select undef, undef, undef, 0.1;
            next;
        }
        die "$! unlinking $f at ", join( ", line ", (caller)[ 1, 2 ] ), "\n";
    }
}

my $text           = "Hello World\n";
my @perl           = ($perl);
my $emitter_script = qq{print '$text'; print STDERR uc( '$text' ) unless \@ARGV };
my @emitter        = ( @perl, '-e', $emitter_script );

my $in;
my $out;
my $err;

my $in_file  = 'run.t.in';
my $out_file = 'run.t.out';
my $err_file = 'run.t.err';

my $h;

sub slurp($) {
    my ($f) = @_;
    open( S, "<$f" ) or return "$! $f";
    my $r = join( '', <S> );
    close S or warn "$!: $f";
    select 0.1 if $^O =~ /Win32/;
    return $r;
}

sub spit($$) {
    my ( $f, $s ) = @_;
    open( S, ">$f" ) or die "$! $f";
    print S $s or die "$! $f";
    close S or die "$! $f";
}

##
## A grossly inefficient filter to test filter
## chains.  It's inefficient because we want to make sure that the
## filter chain flushing logic works.  The inefficiency is that it
## doesn't process as much input as it could each call, so lots of calls
## are required.
##
sub alt_casing_filter {
    my ( $in_ref, $out_ref ) = @_;
    return input_avail && do {
        $$out_ref .= lc( substr( $$in_ref, 0, 1, '' ) );
        1;
      }
      && (
        !input_avail || do {
            $$out_ref .= uc( substr( $$in_ref, 0, 1, '' ) );
            1;
        }
      );
}

sub case_inverting_filter {
    my ( $in_ref, $out_ref ) = @_;
    return input_avail && do {
        $$in_ref =~ tr/a-zA-Z/A-Za-z/;
        $$out_ref .= $$in_ref;
        $$in_ref = '';
        1;
    };
}

sub eok {
    my ( $got, $exp, $name ) = @_;
    $got =~ s/([\000-\037])/sprintf "\\0x%02x", ord $1/ge if defined $exp;
    $exp =~ s/([\000-\037])/sprintf "\\0x%02x", ord $1/ge if defined $exp;

    my ( $pack, $file, $line ) = caller();
    $name ||= qq[eok at $file line $line];

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    return is( $got, $exp, $name );
}

my $r;

is( _map_fds, $fd_map );
$fd_map = _map_fds;

##
## Internal testing
##
filter_tests(
    "alt_casing_filter",
    "Hello World",
    [ "hElLo wOrLd" =~ m/(..?)/g ],
    \&alt_casing_filter
  ),

  is( _map_fds, $fd_map );
$fd_map = _map_fds;

filter_tests(
    "case_inverting_filter",
    "Hello World",
    "hELLO wORLD",
    \&case_inverting_filter
  ),

  is( _map_fds, $fd_map );
$fd_map = _map_fds;

##
## Calling the local system shell
##
ok( run qq{$perl -e exit} );
is( $?, 0 );

is( _map_fds, $fd_map );
$fd_map = _map_fds;
SKIP: {
    if ( IPC::Run::Win32_MODE() ) {
        skip( "$^O's shell returns 0 even if last command doesn't", 3 );
    }

    ok( !run(qq{$perl -e 'exit(42)'}) );
    ok($?);
    is( $? >> 8, 42 );
}
is( _map_fds, $fd_map );
$fd_map = _map_fds;

##
## Simple commands, not executed via shell
##
ok( run $perl, qw{-e exit} );
is( $?, 0 );

is( _map_fds, $fd_map );
$fd_map = _map_fds;

ok( !run $perl, qw{-e exit(42)} );
ok($?);
is $? >> 8, 42;

is( _map_fds, $fd_map );
$fd_map = _map_fds;

##
## A function
##
SKIP: {
    if ( IPC::Run::Win32_MODE() ) {
        skip( "Can't spawn subroutines on $^O", 5 );
    }

    ok run sub { };
    is $?, 0;
    ok !run sub { exit 42 };
    ok $? ;
    is $? >> 8, 42;
}
is( _map_fds, $fd_map );
$fd_map = _map_fds;

##
## A function, and an init function
##
SKIP: {
    if ( IPC::Run::Win32_MODE() ) {
        skip( "Can't spawn subroutines on $^O", 2 );
    }

    my $e = 0;
    ok(
        !run(
            sub { exit($e) },
            init => sub { $e = 42 }
        )
    );
    ok($?);
}
is( _map_fds, $fd_map );
$fd_map = _map_fds;

##
## scalar ref I & O redirection using op tokens
##
$out    = 'REPLACE ME';
$fd_map = _map_fds;
$r      = run [ @emitter, "nostderr" ], '>', \$out;
ok($r);

ok( !$? );
is( _map_fds, $fd_map );
eok( $out, $text );

$out    = 'REPLACE ME';
$fd_map = _map_fds;
$r      = run [ @emitter, "nostderr" ], '<', \undef, '>', \$out;
ok($r);

ok( !$? );
is( _map_fds, $fd_map );
eok( $out, $text );

$in     = $emitter_script;
$out    = 'REPLACE ME';
$err    = 'REPLACE ME';
$fd_map = _map_fds;
$r      = run \@perl, '<', \$in, '>', \$out, '2>', \$err,;
ok($r);

ok( !$? );
is( _map_fds, $fd_map );

eok( $in,  $emitter_script );
eok( $out, $text );
eok( $err, uc($text) );
##
## scalar ref I & O redirection, succinct mode.
##

$in     = $emitter_script;
$out    = 'REPLACE ME';
$err    = 'REPLACE ME';
$fd_map = _map_fds;
$r      = run \@perl, \$in, \$out, \$err;
ok($r);

ok( !$? );
is( _map_fds, $fd_map );

eok( $in,  $emitter_script );
eok( $out, $text );
eok( $err, uc($text) );

##
## Long output, to test for blocking read.
##
## Assume pipe buffer length <= 10000, need to double that to assure enough
## chars to fill a buffer so.  This test adapted from a test submitted by
## Borislav Deianov <borislav@ensim.com>.

$in     = "-" x 20000 . "end\n";
$out    = 'REPLACE ME';
$fd_map = _map_fds;
$r      = run [ $perl, qw{-e print"-"x20000;<STDIN>;} ], \$in, \$out;
ok($r);

ok( !$? );
is( _map_fds, $fd_map );

is( length $out, 20000 );
unlike( $out, qr/[^-]/ );

##
## Long output run through twice
##
## Adapted from a stress test by Aaron Elkiss <aelkiss@wam.umd.edu>
##

$h   = start [ $perl, qw( -pe BEGIN{$|=1}1 ) ], \$in, \$out;
$in  = "\n";
$out = "";
pump $h until length $out;
is $out, "\n";

my $long_string = "x" x 20000 . "DOC2\n";
$in  = $long_string;
$out = "";
my $ok_1 = eval {
    pump $h until $out =~ /DOC2/;
    1;
};
my $x    = $@;
my $ok_2 = eval {
    finish $h;
    1;
};

$x = $@ if $ok_1 && !$ok_2;

if ( $ok_1 && $ok_2 ) {
    is $long_string, $out;
}
else {
    $x =~ s/(x+)/sprintf "...%d \"x\" chars...", length $1/e;
    is $x, "";
}

##
## child function, scalar ref I & O redirection, succinct mode.
##
SKIP: {
    if ( IPC::Run::Win32_MODE() ) {
        skip( "Can't spawn subroutines on $^O", 6 );
    }

    $in     = $text;
    $out    = 'REPLACE ME';
    $err    = 'REPLACE ME';
    $fd_map = _map_fds;
    $r      = run(
        sub {
            while (<>) { print; print STDERR uc($_) }
        },
        \$in,
        \$out,
        \$err
    );
    ok($r);
    ok !$?;
    is( _map_fds, $fd_map );
    eok( $in,  $text );
    eok( $out, $text );
    eok( $err, uc($text) );
}

##
## here document as input
##
$out    = 'REPLACE ME';
$err    = 'REPLACE ME';
$fd_map = _map_fds;
$r      = run \@perl, \<<TOHERE, \$out, \$err;
$emitter_script
TOHERE
ok($r);

ok( !$? );
is( _map_fds, $fd_map );

eok( $out, $text );
eok( $err, uc($text) );

##
## undef as input
##
$out    = 'REPLACE ME';
$err    = 'REPLACE ME';
$fd_map = _map_fds;
$r      = run \@perl, \undef, \$out, \$err;
ok($r);

ok( !$? );
is( _map_fds, $fd_map );

eok( $out, '' );
eok( $err, '' );

##
## filehandle input redirection
##
$out    = 'REPLACE ME';
$err    = 'REPLACE ME';
$fd_map = _map_fds;
spit( $in_file, $emitter_script );
open( F, "<$in_file" ) or die "$! $in_file";
$r = run \@perl, \*F, \$out, \$err;
close F;
unlink $in_file or warn "$! $in_file";
ok($r);

ok( !$? );
is( _map_fds, $fd_map );

eok( $out, $text );
eok( $err, uc($text) );

##
## input redirection via caller writing directly to a pipe
##
$out    = 'REPLACE ME';
$err    = 'REPLACE ME';
$fd_map = _map_fds;
$h      = start \@perl, '<pipe', \*IN, '>', \$out, '2>', \$err;
## Assume this won't block...
print IN $emitter_script;
close IN or warn $!;
$r = $h->finish;
ok($r);

ok( !$? );
is( _map_fds, $fd_map );

eok( $out, $text );
eok( $err, uc($text) );

##
## filehandle input redirection, passed via *F{IO}
##
$out    = 'REPLACE ME';
$err    = 'REPLACE ME';
$fd_map = _map_fds;
spit( $in_file, $emitter_script );
open( F, "<$in_file" ) or die "$! $in_file";
$r = run \@perl, *F{IO}, \$out, \$err;
close F;
_unlink $in_file;
ok($r);

ok( !$? );
is( _map_fds, $fd_map );

eok( $out, $text );
eok( $err, uc($text) );

##
## filehandle output redirection
##
$fd_map = _map_fds;
open( OUT, ">$out_file" ) or die "$! $out_file";
open( ERR, ">$err_file" ) or die "$! $err_file";
print OUT "out: ";
print ERR uc("err: ");
$r = run \@emitter, \undef, \*OUT, \*ERR;
print OUT " more out data";
print ERR uc(" more err data");
close OUT;
close ERR;
$out = slurp($out_file);
$err = slurp($err_file);
_unlink $out_file;
_unlink $err_file;
ok($r);

ok( !$? );
is( _map_fds, $fd_map );

eok( $out, "out: $text more out data" );
eok( $err, uc("err: $text more err data") );

##
## filehandle output redirection via a pipe that is returned to the caller
##
$fd_map = _map_fds;
$r      = run \@emitter, \undef, '>pipe', \*OUT, '2>pipe', \*ERR;
$out    = '';
$err    = '';
read OUT, $out, 10000 or warn $!;
read ERR, $err, 10000 or warn $!;
close OUT or warn $!;
close ERR or warn $!;
ok($r);

ok( !$? );
is( _map_fds, $fd_map );

eok( $out, $text );
eok( $err, uc($text) );

##
## sub I & O redirection
##
$in     = $emitter_script;
$out    = undef;
$err    = undef;
$fd_map = _map_fds;
$r      = run(
    \@perl,
    '<', sub { my $f = $in; $in = undef; return $f },
    '>',  sub { $out .= shift },
    '2>', sub { $err .= shift },
);
ok($r);
ok( !$? );
is( _map_fds, $fd_map );

eok( $out, $text );
eok( $err, uc($text) );

##
## input redirection from a file
##
$out    = undef;
$err    = undef;
$fd_map = _map_fds;
spit( $in_file, $emitter_script );
$r = run(
    \@perl,
    "<$in_file",
    '>',  sub { $out .= shift },
    '2>', sub { $err .= shift },
);
_unlink $in_file;
ok($r);
ok( !$? );
is( _map_fds, $fd_map );
eok( $out, $text );
eok( $err, uc($text) );

##
## reading input from a non standard fd
##
SKIP: {
    if ( IPC::Run::Win32_MODE() ) {
        skip( "$^O does not allow redirection of file descriptors > 2", 11 );
    }

    $out    = undef;
    $err    = undef;
    $fd_map = _map_fds;
    $r      = run(
        ## FreeBSD doesn't guarantee that fd 3 or 4 are available, so
        ## don't assume, go for 5.
        [ @perl, '-le', 'open( STDIN, "<&5" ) or die $!; print <STDIN>' ],
        "5<", \"Hello World",
        '>',  \$out,
        '2>', \$err,
    );
    ok($r);
    ok( !$? );
    is( _map_fds, $fd_map );
    eok( $out, $text );
    eok( $err, '' );

    ##
    ## duping input descriptors and an input descriptor > 0
    ##
    $in     = $emitter_script;
    $out    = 'REPLACE ME';
    $err    = 'REPLACE ME';
    $fd_map = _map_fds;
    $r      = run(
        \@perl,
        '>',  \$out,
        '2>', \$err,
        '3<', \$in,
        '0<&3',
    );
    ok($r);
    ok( !$? );
    is( _map_fds, $fd_map );
    eok( $in,  $emitter_script );
    eok( $out, $text );
    eok( $err, uc($text) );
}

##
## closing input descriptors
##
$out    = 'REPLACE ME';
$err    = 'REPLACE ME';
$fd_map = _map_fds;
spit( $in_file, $emitter_script );
$r = run(
    [ @perl, '-e', '$l = readline *STDIN or die $!; print $l' ],
    '>',  \$out,
    '2>', \$err,
    '<',  $in_file,
    '0<&-',
);
_unlink $in_file;
ok( !$r );
ok($?);
is( _map_fds, $fd_map );
eok( $out, '' );

#ok( $err =~ /file descriptor/i ? "Bad file descriptor error" : $err, "Bad file descriptor error" );
# XXX This should be use Errno; if $!{EBADF}. --rs
is( length $err ? "Bad file descriptor error" : $err, "Bad file descriptor error" );

##
## input redirection from a non-existent file
##
$out    = 'REPLACE ME';
$err    = 'REPLACE ME';
$fd_map = _map_fds;
my $bad_file = "$in_file.nonexistent";
_unlink $bad_file if -e $bad_file;
eval { $r = run \@perl, ">$out_file", "<$bad_file"; };
like $@, qr/\Q$bad_file\E/;
is( _map_fds, $fd_map );

##
## output redirection to a file w/ creation or truncation
##
$fd_map = _map_fds;
_unlink $out_file if -x $out_file;
_unlink $err_file if -x $err_file;
$r = run(
    \@emitter,
    ">$out_file",
    "2>$err_file",
);
$out = slurp($out_file);
$err = slurp($err_file);
ok($r);
ok( !$? );
is( _map_fds, $fd_map );

eok( $out, $text );
eok( $err, uc($text) );

##
## output file redirection, w/ truncation
##
$fd_map = _map_fds;
spit( $out_file, 'out: ' );
spit( $err_file, 'ERR: ' );
$r = run(
    \@emitter,
    ">$out_file",
    "2>$err_file",
);
$out = slurp($out_file);
_unlink $out_file;
$err = slurp($err_file);
_unlink $err_file;
ok($r);
ok( !$? );
is( _map_fds, $fd_map );

eok( $out, $text );
eok( $err, uc($text) );

##
## output file redirection w/ append
##
spit( $out_file, 'out: ' );
spit( $err_file, 'ERR: ' );
$fd_map = _map_fds;
$r      = run(
    \@emitter,
    ">>$out_file",
    "2>>$err_file",
);
$out = slurp($out_file);
_unlink $out_file;
$err = slurp($err_file);
_unlink $err_file;
ok($r);
ok( !$? );
is( _map_fds, $fd_map );

eok( $out, "out: $text" );
eok( $err, uc("err: $text") );
##
## dup()ing output descriptors
##
$out    = 'REPLACE ME';
$err    = 'REPLACE ME';
$fd_map = _map_fds;
$r      = run \@emitter, '>', \$out, '2>', \$err, '2>&1';
ok($r);
ok( !$? );
is( _map_fds, $fd_map );
like $out, qr/(?:$text){2}/i;
eok( $err, '' );

##
## stderr & stdout redirection to the same file via >&word
##
$fd_map = _map_fds;
_unlink $out_file if -x $out_file;
$r = run \@emitter, ">&$out_file";
$out = slurp($out_file);
ok($r);
ok( !$? );
is( _map_fds, $fd_map );

like $out, qr/(?:$text){2}/i;

##
## Non-zero exit value, command with args, no redirects.
##
$fd_map = _map_fds;
$r = run [ @perl, '-e', 'exit(42)' ];
ok( !$r );
is( $?,       42 << 8 );
is( _map_fds, $fd_map );

##
## Zero exit value, command with args, no redirects.
##
$fd_map = _map_fds;
$r = run [ @perl, qw{ -e exit } ];
ok($r);
ok( !$? );
is( _map_fds, $fd_map );

##
## dup()ing output descriptors that collide.
##
## This test assumes that our caller doesn't leave a lot of fds opened,
## and assumes that $out_file will be opened on fd 3, 4 or 5.
##
SKIP: {
    if ( IPC::Run::Win32_MODE() ) {
        skip( "$^O does not allow redirection of file descriptors > 2", 5 );
    }

    $out = 'REPLACE ME';
    $err = 'REPLACE ME';
    _unlink $out_file if -x $out_file;
    $fd_map = _map_fds;
    $r      = run(
        \@emitter,
        "<", \"",
        "3>&1", "4>&1", "5>&1",
        ">$out_file",
        '2>', \$err,
    );
    $out = slurp($out_file);
    _unlink $out_file;
    ok($r);
    ok( !$? );
    is( _map_fds, $fd_map );
    eok( $out, $text );
    eok( $err, uc($text) );
}

##
## Pipelining
##
$out    = 'REPLACE ME';
$err    = 'REPLACE ME';
$fd_map = _map_fds;
$r      = run(
    [ @perl, '-lane', 'print STDERR qq{1:$_}; print uc($F[0]), q{ },$F[1]' ],
    \q{Hello World},
    '|', [ @perl, '-lane', 'print STDERR qq{2:$_}; print $F[0], q{ },lc($F[1])' ],
    \$out,
    \$err,
);
ok($r);
ok( !$? );
is( _map_fds, $fd_map );
eok( $out, "HELLO world\n" );
eok( $err, "1:Hello World\n2:HELLO World\n" );

##
## Parallel (unpiplined) processes
##
$out    = 'REPLACE ME';
$err    = 'REPLACE ME';
$fd_map = _map_fds;
$r      = run(
    [ @perl, '-lane', 'print STDERR qq{1:$_}; print uc($F[0]),q{ },$F[1]' ],
    \q{Hello World},
    '&', [ @perl, '-lane', 'print STDERR "2:$_"; print $F[0],q{ },lc( $F[1] )' ],
    \q{Hello World},
    \$out,
    \$err,
);
ok($r);
ok( !$? );
is( _map_fds, $fd_map );
like $out, qr/^(?:HELLO World\n|Hello world\n){2}$/s;
like $err, qr/^(?:[12]:Hello World.*){2}$/s;

##
## A few error cases...
##
eval { $r = run \@perl, '<', [], [] };
like( $@, qr/not allowed/ );
eval { $r = run \@perl, '>', [], [] };
like( $@, qr/not allowed/ );
foreach my $foo (qw( | & < > >& 1>&2 >file <file 2<&1 <&- 3<&- )) {
    eval { $r = run $foo, [] };
    like( $@, qr/command/ );
}
$out    = 'REPLACE ME';
$err    = 'REPLACE ME';
$fd_map = _map_fds;
eval {
    $r = run(
        \@emitter, '>', \$out, '2>', \$err,
        _simulate_fork_failure => 1
    );
};
ok($@);
ok( !$? );
is( _map_fds, $fd_map );

eok( $out, '' );
eok( $err, '' );

$fd_map = _map_fds;
eval { $r = run \@perl, '<file', _simulate_open_failure => 1; };
ok($@);
ok( !$? );
is( _map_fds, $fd_map );

$fd_map = _map_fds;
eval { $r = run \@perl, '>file', _simulate_open_failure => 1; };
ok($@);
ok( !$? );
is( _map_fds, $fd_map );

##
## harness, pump, run
##
$in     = 'SHOULD BE UNCHANGED';
$out    = 'REPLACE ME';
$err    = 'REPLACE ME';
$?      = 99;
$fd_map = _map_fds;
$h      = start(
    [ @perl, '-pe', 'BEGIN { $| = 1 } print STDERR uc($_)' ],
    \$in, \$out, \$err,
);
isa_ok( $h, 'IPC::Run' );
is( $?, 99 );

eok( $in,  'SHOULD BE UNCHANGED' );
eok( $out, '' );
eok( $err, '' );
ok( $h->pumpable );

$in = '';
$?  = 0;
pump_nb $h for ( 1 .. 100 );
pass("after pump_nb");
eok( $in,  '' );
eok( $out, '' );
eok( $err, '' );
ok( $h->pumpable );

$in = $text;
$?  = 0;
pump $h until $out =~ /Hello World/;
pass("after pump");
ok( !$? );
eok( $in,  '' );
eok( $out, $text );
ok( $h->pumpable );

ok( $h->finish );
ok( !$? );
is( _map_fds, $fd_map );
eok( $out, $text );
eok( $err, uc($text) );
ok( !$h->pumpable );

##
## start, run, run, run.  See Tom run.  A do-run-run, a-do-run-run.
##
$in     = 'SHOULD BE UNCHANGED';
$out    = 'REPLACE ME';
$err    = 'REPLACE ME';
$fd_map = _map_fds;
$h      = start(
    [ @perl, '-pe', 'binmode STDOUT; binmode STDERR; BEGIN { $| = 1 } print STDERR uc($_)' ],
    \$in, \$out, \$err,
);
ok( $h->isa('IPC::Run') );

eok( $in,  'SHOULD BE UNCHANGED' );
eok( $out, '' );
eok( $err, '' );
ok( $h->pumpable );

$in = $text;
ok( $h->finish );
ok( !$? );
is( _map_fds, $fd_map );
eok( $in,  '' );
eok( $out, $text );
eok( $err, uc($text) );
ok( !$h->pumpable );

$in  = $text;
$out = 'REPLACE ME';
$err = 'REPLACE ME';
ok( $h->run );
ok( !$? );
is( _map_fds, $fd_map );
eok( $in,  $text );
eok( $out, $text );
eok( $err, uc($text) );
ok( !$h->pumpable );

$in  = $text;
$out = 'REPLACE ME';
$err = 'REPLACE ME';
ok( $h->run );
ok( !$? );
is( _map_fds, $fd_map );
eok( $in,  $text );
eok( $out, $text );
eok( $err, uc($text) );
ok( !$h->pumpable );

##
## Output filters
##
$out    = 'REPLACE ME';
$err    = 'REPLACE ME';
$fd_map = _map_fds;
$r      = run(
    \@emitter,
    '>',
    \&alt_casing_filter,
    \&case_inverting_filter,
    \$out,
    '2>', \$err,
);
ok($r);
ok( !$? );
is( _map_fds, $fd_map );

eok( $out, "HeLlO WoRlD\n" );
eok( $err, uc($text) );

##
## Input filters
##
$out    = 'REPLACE ME';
$err    = 'REPLACE ME';
$fd_map = _map_fds;
$in     = $text;
$r      = run(
    [ @perl, '-pe', 'binmode STDOUT; binmode STDERR; print STDERR uc $_' ],
    '0<',
    \&case_inverting_filter,
    \&alt_casing_filter,
    \$in,
    '1>', \$out,
    '2>', \$err,
);
ok($r);
ok( !$? );
is( _map_fds, $fd_map );

eok( $in,  $text );
eok( $out, "HeLlO WoRlD\n" );
eok( $err, uc($text) );

{    # no warnings for an empty path but it does die.
        # Some other OSes might not support find. Windows and UNIX do...
    my @simple_command = ('bogusprogram');

    local $ENV{PATH};
    delete $ENV{PATH};

    eval { $h = start \@simple_command, \$in, \$out; };
    ok( $@, "Error running bogus program when path is empty" );

    my ($message) = get_warnings();
    is( $message, undef, "No warnings found during program call with empty path" );
    finish $h;    # Close out the program call
}

