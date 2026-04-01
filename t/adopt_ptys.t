#!/usr/bin/perl

=pod

=head1 NAME

adopt_ptys.t - Test that adopt() correctly transfers PTYS between harnesses

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

## adopt() copies PTYS from the adoptee to the adopter.
## A typo (PYTS instead of PTYS) caused this to silently iterate
## over an empty hash, failing to transfer any PTY references.
## This test verifies the fix.

plan tests => 3;

use IPC::Run qw( harness );

## Build two minimal harness objects and directly set PTYS to test
## that adopt() transfers them correctly.  We don't need real IO::Pty
## objects — any truthy value proves the hash key was copied.
my $h1 = harness( [ $^X, '-e', '1' ] );
my $h2 = harness( [ $^X, '-e', '1' ] );

## Simulate the adoptee having a PTY registered
$h2->{PTYS} = { 'test_pty' => 'FAKE_PTY_OBJECT', 'other_pty' => 'ANOTHER_PTY' };

## Verify adopter starts with no PTYs
is( scalar keys %{ $h1->{PTYS} }, 0, 'adopter starts with no PTYs' );

## adopt should transfer PTYS from h2 to h1
$h1->adopt($h2);

is( $h1->{PTYS}->{'test_pty'},  'FAKE_PTY_OBJECT', 'adopt() transfers first PTY' );
is( $h1->{PTYS}->{'other_pty'}, 'ANOTHER_PTY',     'adopt() transfers second PTY' );
