#!/usr/bin/perl

=pod

=head1 NAME

redirect_init.t - Test coverage for &>pipe redirects, init subs, and stderr filters

=head1 DESCRIPTION

Exercises redirect features and init sub behavior that were previously
untested: combining stdout+stderr to a single pipe, init sub execution
and exception propagation, and filters applied to stderr.

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
use IPC::Run qw( run start pump finish timeout :filters :filter_imp );

BEGIN {
    if ( IPC::Run::Win32_MODE() ) {
        plan skip_all => 'Skipping on Win32';
        exit(0);
    }
    else {
        plan tests => 16;
    }
}

my @perl = ($^X);

##
## &>pipe — combine stdout and stderr to one destination
##

{
    my $out = '';
    ok(
        run(
            [ @perl, '-e', 'print "out\n"; print STDERR "err\n"' ],
            '>&', \$out,
        ),
        '>&  \\$out captures both stdout and stderr'
    );
    like( $out, qr/out/,  '>&  output contains stdout' );
    like( $out, qr/err/,  '>&  output contains stderr' );
}

##
## &>pipe with start/pump/finish
##

{
    my $out = '';
    my $h = start(
        [ @perl, '-e', 'print "async_out\n"; print STDERR "async_err\n"' ],
        '>&', \$out,
    );
    finish($h);
    like( $out, qr/async_out/, '>&  async captures stdout' );
    like( $out, qr/async_err/, '>&  async captures stderr' );
}

##
## &>pipe — combined stdout+stderr via pipe filehandle
##

{
    my $pipe_fh;
    my $h = start(
        [ @perl, '-e', '$| = 1; print "pipe_out\n"; print STDERR "pipe_err\n"' ],
        '&>pipe', \$pipe_fh,
    );
    ok( defined fileno($pipe_fh), '&>pipe  creates a readable filehandle' );
    my $combined = do { local $/; <$pipe_fh> };
    finish($h);
    like( $combined, qr/pipe_out/, '&>pipe  captures stdout via pipe' );
    like( $combined, qr/pipe_err/, '&>pipe  captures stderr via pipe' );
}

##
## init sub — runs in the child before exec
##

{
    my $out = '';
    ok(
        run(
            [ @perl, '-e', 'print $ENV{INIT_RAN} || "no"' ],
            'init', sub { $ENV{INIT_RAN} = 'yes' },
            '>', \$out,
        ),
        'init sub executes without error'
    );
    is( $out, 'yes', 'init sub sets env var visible to child' );
}

##
## init sub exception propagation
##

{
    my $out = '';
    my $ok = eval {
        run(
            [ @perl, '-e', 'exit 0' ],
            'init', sub { die "init_kaboom\n" },
            '>', \$out,
        );
        1;
    };
    my $err = $@;
    ok( !$ok, 'init sub die propagates as exception' );
    like( $err, qr/init_kaboom/, 'init sub exception message preserved' );
}

##
## Filters on stderr — verify filter functions work on fd 2
##

{
    sub uc_stderr_filter {
        my ( $in_ref, $out_ref ) = @_;
        return input_avail && do {
            $$out_ref .= uc($$in_ref);
            $$in_ref = '';
            1;
        };
    }
    my $out = '';
    my $err_out = '';
    ok(
        run(
            [ @perl, '-e', 'print STDERR "filter_me\n"' ],
            '>', \$out,
            '2>', \&uc_stderr_filter, \$err_out,
        ),
        'filter on stderr runs without error'
    );
    like( $err_out, qr/FILTER_ME/, 'stderr filter transforms data' );
}

##
## Numbered fd output redirect (3>)
##

{
    my $out3 = '';
    ok(
        run(
            [ @perl, '-e', 'open my $fh, ">&=3" or die $!; print {$fh} "fd3_data\n"' ],
            '3>', \$out3,
        ),
        '3> redirect captures fd 3 output'
    );
    is( $out3, "fd3_data\n", '3> redirect received correct data' );
}
