requires 'IO::Pty'  => 0;
requires 'Readonly' => 0;
on 'develop' => sub {
    requires 'Readonly';
    requires 'Test::Pod::Coverage';
    requires 'Pod::Simple';
    requires 'Test::Pod';
    requires 'Perl::MinimumVersion';
    requires 'Test::MinimumVersion';
};
