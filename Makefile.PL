use ExtUtils::MakeMaker;

sub pty_warn {
   warn "WARNING: $_[0].\nWARNING: '<pty<', '>pty>' $_[1] not work.\n\n";
   last ;
}

my @conditional_prereqs;

if ( $^O !~ /Win32/ ) {
   for ( eval { require IO::Pty ; IO::Pty->VERSION } ) {
      s/_//g if defined ;
      pty_warn "IO::Pty not found", "will" unless defined ;
      push @conditional_prereqs, "IO::Pty" => 1.00;
   }
}
else {
   push @conditional_prereqs, "Win32::Process" => 0.0;
   if ( ! eval "use Socket qw( IPPROTO_TCP TCP_NODELAY ); 1" ) {
      warn <<TOHERE;
$@
IPC::Run on Win32 requires a recent Sockets.pm in order to handle more
complex interactions with subprocesses.  They are not needed for most
casual uses of run(), but it's impossible to tell whether all uses of
IPC::Run in your installed modules meet the requirements, so IPC::Run
should not be installed on Win32 machines with older perls.

TOHERE

      ## Die nicely in case some install manager cares about the canonical
      ## error message for this.  Not that I've ever seen one, but those
      ## wacky CPANPLUSers might just do something cool in this case.

      require 5.006; ## Older perls' Socket.pm don't export IPPROTO_TCP
      ## Most of the time it's not needed (since IPC::Run tries not to
      ## use sockets), but the user is not likely to know what the hell
      ## went wrong running sb. else's program.

      exit 1;  ## If something really odd is happening...
   }
}

print <<'TOHERE' ;

   If you experience problems while running make test, please run
   the failing scripts using a command like:

      make test TEST_FILES=t/foo.t TEST_VERBOSE=1 IPCRUNDEBUG=4 > foo.out 2>&1

   (use nmake on Windows) and sending foo.out with your problem report.
   Bonus air miles awarded for writing a small, simple exploit script :).

   You may also use the IPCRUNDEBUG=1 (or 2, 3, or 4) trick with your own
   programs, see perldoc IPC::Run for details.

   See perldoc IPC::Run for details on the experimental nature of
   pty and Win32 support.

   <barbie tm="Mattel">Subprocesses are *HARD*.</barbie>

TOHERE

WriteMakefile(
    NAME          => 'IPC::Run',
    VERSION_FROM  => 'lib/IPC/Run.pm',
    PREREQ_PM => {
        @conditional_prereqs,
    }
);


sub MY::libscan {
   package MY ;
   my $self = shift ;
   my ( $path ) = @_ ;
   return '' if /\.sw[a-z]$/ ;
   return '' unless length $self->SUPER::libscan( $path ) ;
   return $path ;
}
