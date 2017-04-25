package IPC::Run::Test;

use strict;
use Test::More;
use Exporter;
use IPC::Run qw{ harness };
use IPC::Run::IO;

use vars qw{@ISA @EXPORT};

BEGIN {
    @ISA    = qw{ Exporter };
    @EXPORT = qw{ filter_tests };
}

## This is not needed by most users.  Should really move to IPC::Run::TestUtils
#=item filter_tests
#
#   my @tests = filter_tests( "foo", "in", "out", \&filter );
#   $_->() for ( @tests );
#
#This creates a list of test subs that can be used to test most filters
#for basic functionality.  The first parameter is the name of the
#filter to be tested, the second is sample input, the third is the
#test(s) to apply to the output(s), and the rest of the parameters are
#the filters to be linked and tested.
#
#If the filter chain is to be fed multiple inputs in sequence, the second
#parameter should be a reference to an array of those inputs:
#
#   my @tests = filter_tests( "foo", [qw(1 2 3)], "123", \&filter );
#
#If the filter chain should produce a sequence of outputs, then the
#third parameter should be a reference to an array of those outputs:
#
#   my @tests = filter_tests(
#      "foo",
#      "1\n\2\n",
#      [ qr/^1$/, qr/^2$/ ],
#      new_chunker
#   );
#
#See t/run.t and t/filter.t for an example of this in practice.
#
#=cut

##
## Filter testing routines
##
sub filter_tests($;@) {
    my ( $name, $in, $exp, @filters ) = @_;
    my @in  = ref $in eq 'ARRAY'  ? @$in  : ($in);
    my @exp = ref $exp eq 'ARRAY' ? @$exp : ($exp);
    my IPC::Run::IO $op;
    my $output;
    my @input;
    my $in_count = 0;
    my @out;
    my $h;

  SCOPE: {
        $h  = harness();
        $op = IPC::Run::IO->_new_internal(
            '<', 0, 0, 0, undef,
            IPC::Run::new_string_sink( \$output ),
            @filters,
            IPC::Run::new_string_source( \@input ),
        );
        $op->_init_filters;
        @input  = ();
        $output = '';
        is(
            !defined $op->_do_filters($h),
            1,
            "$name didn't pass undef (EOF) through"
        );
    }

    ## See if correctly does nothing on 0, (please try again)
  SCOPE: {
        $op->_init_filters;
        $output = '';
        @input  = ('');
        is(
            $op->_do_filters($h),
            0,
            "$name didn't return 0 (please try again) when given a 0"
        );
    }

  SCOPE: {
        @input = ('');
        is(
            $op->_do_filters($h),
            0,
            "$name didn't return 0 (please try again) when given a second 0"
        );
    }

  SCOPE: {
        for ( 1 .. 100 ) {
            last unless defined $op->_do_filters($h);
        }
        is(
            !defined $op->_do_filters($h),
            1,
            "$name didn't return undef (EOF) after two 0s and an undef"
        );
    }

    ## See if it can take @in and make @out
  SCOPE: {
        $op->_init_filters;
        $output = '';
        @input  = @in;
        while ( defined $op->_do_filters($h) && @input ) {
            if ( length $output ) {
                push @out, $output;
                $output = '';
            }
        }
        if ( length $output ) {
            push @out, $output;
            $output = '';
        }
        is(
            scalar @input,
            0,
            "$name didn't consume it's input"
        );
    }

  SCOPE: {
        for ( 1 .. 100 ) {
            last unless defined $op->_do_filters($h);
            if ( length $output ) {
                push @out, $output;
                $output = '';
            }
        }
        is(
            !defined $op->_do_filters($h),
            1,
            "$name didn't return undef (EOF), tried  100 times"
        );
    }

  SCOPE: {
        is(
            join( ', ', map "'$_'", @out ),
            join( ', ', map "'$_'", @exp ),
            $name
        );
    }

  SCOPE: {
        ## Force the harness to be cleaned up.
        $h = undef;
        ok(1);
    }
}

1;
