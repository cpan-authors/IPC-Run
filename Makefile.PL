use ExtUtils::MakeMaker;

# Calculate the dependencies
my %PREREQ_PM;
if ( $^O ne 'MSWin32' ) {
	foreach ( eval { require IO::Pty; IO::Pty->VERSION } ) {
		s/_//g if defined $_;
		unless ( defined $_ ) {
			warn("WARNING: \"IO::Pty not found\".\nWARNING: '<pty<', '>pty>' will not work.\n\n");
			last;
		}
		$PREREQ_PM{'IO::Pty'} = '1.08';
	}
} else {
	$PREREQ_PM{'Win32::Process'} = '0.14';
	$PREREQ_PM{'Win32API::File'} = '0.0901';
	if ($] >= 5.021006) {
			$PREREQ_PM{'Win32API::File'} = '0.1203';
	}
	if ( ! eval "use Socket qw( IPPROTO_TCP TCP_NODELAY ); 1" ) {
		warn <<"TOHERE";
$@
IPC::Run on Win32 requires a recent Sockets.pm in order to handle more
complex interactions with subprocesses.  They are not needed for most
casual uses of run(), but it is impossible to tell whether all uses of
IPC::Run in your installed modules meet the requirements, so IPC::Run
should not be installed on Win32 machines with older perls.

TOHERE

		## Die nicely in case some install manager cares about the canonical
		## error message for this.  Not that I've ever seen one, but those
		## wacky CPANPLUSers might just do something cool in this case.
		## Older perls' Socket.pm don't export IPPROTO_TCP
		require 5.006;
		## Most of the time it's not needed (since IPC::Run tries not to
		## use sockets), but the user is not likely to know what the hell
		## went wrong running sb. else's program.

		## If something really odd is happening...
		exit 1;
	}
}

if ( $] < 5.008001 ) {
    # need Scalar::Util::looks_like_number
	$PREREQ_PM{'Scalar::List::Utils'} = '1.10';
}

WriteMakefile(
	NAME         => 'IPC::Run',
	ABSTRACT     => 'system() and background procs w/ piping, redirs, ptys (Unix, Win32)',	
	AUTHOR       => 'Barrie Slaymaker <barries@slaysys.com>',
	VERSION_FROM => 'lib/IPC/Run.pm',
	($ExtUtils::MakeMaker::VERSION >= 6.3002 ? ('LICENSE'        => 'perl', ) : ()),
	PREREQ_PM    => {
		Test::More => '0.47',
		%PREREQ_PM,
	},
        dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
        clean               => { FILES => 'IPC-Run-*' },
	META_MERGE  => {
	    recommends => {
		'IO::Pty' => '1.08',
	    },
	    build_requires => {
		'Test::More' => 0,  # For testing
	    },
	    resources => {
		license => 'http://dev.perl.org/licenses/',
		bugtracker => 'https://github.com/toddr/IPC-Run/issues',
		repository => 'https://github.com/toddr/IPC-Run',
	    }
	});
	  

sub MY::libscan {
	package MY;
	my $self = shift;
	my ($path) = @_;
	return '' if $path =~ m/\.sw[a-z]\z/msx;
	return '' unless length $self->SUPER::libscan($path);
	return $path;
}
