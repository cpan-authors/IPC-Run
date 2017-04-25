#!/usr/bin/perl

=pod

=head1 NAME

signal.t - Test suite IPC::Run->signal

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

use Test::More;
use IPC::Run qw( :filters :filter_imp start run );

require './t/lib/Test.pm';
IPC::Run::Test->import();

BEGIN {
    if ( IPC::Run::Win32_MODE() ) {
        plan skip_all => 'Skipping on Win32';
        exit(0);
    }
    else {
        plan tests => 3;
    }
}

my @receiver = (
    $^X,
    '-e',
    <<'END_RECEIVER',
      my $which = "          ";
      sub s{ $which = $_[0] };
      $SIG{$_}=\&s for (qw(USR1 USR2));
      $| = 1;
      print "Ok\n";
      for (1..10) { sleep 1; print $which, "\n" }
END_RECEIVER
);

my $h;
my $out;

$h = start \@receiver, \undef, \$out;
pump $h until $out =~ /Ok/;
ok 1;
$out = "";
$h->signal("USR2");
pump $h;
$h->signal("USR1");
pump $h;
$h->signal("USR2");
pump $h;
$h->signal("USR1");
pump $h;
ok $out, "USR2\nUSR1\nUSR2\nUSR1\n";
$h->signal("TERM");
finish $h;
ok(1);
