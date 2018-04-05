#!/usr/bin/perl

use strict;
use warnings;
use B 'perlstring';

sub lines { [ "ab", "\n", "\r", "\r\n", "\n\r" ] }

BEGIN {
    if ( defined $ENV{IPC_SUB_PROCESS} ) {
        binmode STDIN,  ":raw";
        binmode STDERR, ":raw";
        binmode STDOUT, ":raw";
        print $ENV{IPC_SUB_PROCESS_REPORT_IN}
          ? perlstring do { local $/; <STDIN> }
          : lines->[ $ENV{IPC_SUB_INDEX} ];
        exit;
    }
}

BEGIN {
    $|  = 1;
    $^W = 1;
    if ( $ENV{PERL_CORE} ) {
        chdir '../lib/IPC/Run' if -d '../lib/IPC/Run';
        unshift @INC, 'lib', '../..';
        $^X = '../../../t/' . $^X;
    }
}

use Test::More tests => 10;
use IPC::Run 'run';

$ENV{IPC_SUB_PROCESS} = 1;
for my $i ( 0 .. $#{ lines() } ) {
    my $line = lines->[$i];
    $ENV{IPC_SUB_INDEX} = $i;
    for my $report_in ( 1, 0 ) {
        $ENV{IPC_SUB_PROCESS_REPORT_IN} = $report_in;
        run [ "perl", __FILE__ ], "<", \$line, ">", \my $out;
        $out = perlstring $out if not $report_in;
        my $print_line = perlstring $line;
        is $out, $print_line,
          "$print_line - " . ( $report_in ? "child got clean input" : "parent received clean child output" );
    }
}
