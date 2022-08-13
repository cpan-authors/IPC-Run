# The cpanfile specification does not explicitly allow testing $^O or $].  cpanm
# tolerates this, but other cpanfile consumers might not.
if ( $^O ne 'MSWin32' ) {
    requires 'IO::Pty', '1.08';    # not entirely required; see Makefile.PL
}
else {
    requires 'Win32',          '0.27';
    requires 'Win32::Process', '0.14';
    requires 'Win32::ShellQuote';
    requires 'Win32API::File', '0.0901';
    if ( $] >= 5.021006 ) {
        requires 'Win32API::File', '0.1203';
    }
}
on 'test' => sub {
    requires 'Test::More', '0.47';
    recommends 'Readonly';
};
on 'develop' => sub {
    requires 'Test::Pod::Coverage';
    requires 'Pod::Simple';
    requires 'Test::Pod';
    requires 'Perl::MinimumVersion';
    requires 'Test::MinimumVersion';
};
