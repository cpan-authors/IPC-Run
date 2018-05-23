#! perl

use strict;
use warnings;

use Test::More tests => 1;

use IPC::Run 'run';

use File::Temp;
use IO::Handle;

use POSIX ();

# trigger IPC::Run bug where parent has $fd open
# and child needs $fd & $fd+1

my $error;

sub parent {

    # dup stderr so we get some fd
    my $xfd = POSIX::dup( 2 );
    die $! if $xfd == -1;

    my @fds = ( $xfd, $xfd + 1 );

    # create input files to be attached to the fds
    my @tmp;
    @tmp[@fds] = map {
        my $tmp = File::Temp->new;
        $tmp->print( $_ );
        $tmp->close;
        $tmp
    } @fds;


    # child reads from fds and make sure that
    # it can open them and that they're attached
    # to the files it expects.
    my $child = sub {

        for my $fd ( @fds ) {

            my $io = IO::Handle->new_from_fd( $fd, '<' )
              or print( STDERR ( "error fdopening $fd\n" ) ), next;

            my $input = $io->getline;
            print STDERR "expected >$fd<.  got >$input<\n"
              unless $fd eq $input;

        }


    };

    run $child,(  map { $_ . '<', $tmp[$_]->filename } @fds, ), '2>', \$error;

    POSIX::close $xfd;
}

parent;
is ( $error, '', "child fd not closed" )
  or note $error;
