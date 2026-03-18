use strict;
use warnings;

use IPC::Run qw( start run finish );
use Test::More tests => 8;

# Issue #50 / rt.cpan.org #83000:
# Allow ordinary scalar ref for 'pipe' operators

# '>pipe' with scalar ref: child stdout
{
    my $child_out;
    my $h = start( [ $^X, '-le', 'for (1..3) { print $_ }' ], '>pipe', \$child_out );
    ok $h, '>pipe \\$scalar: start succeeds';
    ok defined fileno($child_out), '>pipe \\$scalar: scalar is now a readable filehandle';
    my @content = <$child_out>;
    is_deeply \@content, [ "1\n", "2\n", "3\n" ], '>pipe \\$scalar: correct output';
    ok $h->finish, '>pipe \\$scalar: finish succeeds';
}

# '<pipe' with scalar ref: caller writes to child stdin
{
    my $in_fh;
    my $out;
    my $h = start( [ $^X, '-pe', '1' ], '<pipe', \$in_fh, '>', \$out );
    ok $h, '<pipe \\$scalar: start succeeds';
    ok defined fileno($in_fh), '<pipe \\$scalar: scalar is now a writable filehandle';
    print $in_fh "hello\n";
    close $in_fh;
    ok $h->finish, '<pipe \\$scalar: finish succeeds';
    is $out, "hello\n", '<pipe \\$scalar: correct output';
}
