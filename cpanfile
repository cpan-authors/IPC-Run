requires 'IO::Pty' unless $^O eq 'MSWin32';
on 'develop' => sub {
    requires 'Readonly';
};

