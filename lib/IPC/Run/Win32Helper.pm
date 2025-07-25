package IPC::Run::Win32Helper;

=pod

=head1 NAME

IPC::Run::Win32Helper - helper routines for IPC::Run on Win32 platforms.

=head1 SYNOPSIS

    use IPC::Run::Win32Helper;   # Exports all by default

=head1 DESCRIPTION

IPC::Run needs to use sockets to redirect subprocess I/O so that the select() loop
will work on Win32. This seems to only work on WinNT and Win2K at this time, not
sure if it will ever work on Win95 or Win98. If you have experience in this area, please
contact me at barries@slaysys.com, thanks!.

=cut

use strict;
use warnings;
use Carp;
use IO::Handle;
use vars qw{ $VERSION @ISA @EXPORT };

BEGIN {
    $VERSION = '20250715.0_01';
    @ISA     = qw( Exporter );
    @EXPORT  = qw(
      win32_spawn
      win32_parse_cmd_line
      _dont_inherit
      _inherit
    );
}

require POSIX;

use File::Spec ();
use Text::ParseWords;
use Win32 ();
use Win32::Process;
use Win32::ShellQuote ();
use IPC::Run::Debug;
use Win32API::File qw(
  FdGetOsFHandle
  SetHandleInformation
  HANDLE_FLAG_INHERIT
);

# Replace Win32API::File::INVALID_HANDLE_VALUE, which does not match the C ABI
# on 64-bit builds (https://github.com/chorny/Win32API-File/issues/13).
use constant C_ABI_INVALID_HANDLE_VALUE => length( pack 'P', undef ) == 4
  ? 0xffffffff
  : 0xffffffff << 32 | 0xffffffff;

## Takes an fd or a GLOB ref, never never never a Win32 handle.
sub _dont_inherit {
    for (@_) {
        next unless defined $_;
        my $fd = $_;
        $fd = fileno $fd if ref $fd;
        _debug "disabling inheritance of ", $fd if _debugging_details;
        my $osfh = FdGetOsFHandle $fd;

        # Contrary to documentation, $! has the failure reason
        # (https://github.com/chorny/Win32API-File/issues/14)
        croak "$!: FdGetOsFHandle( $fd )"
          if !defined $osfh || $osfh == C_ABI_INVALID_HANDLE_VALUE;

        SetHandleInformation( $osfh, HANDLE_FLAG_INHERIT, 0 );
    }
}

sub _inherit {    #### REMOVE
    for (@_) {    #### REMOVE
        next unless defined $_;    #### REMOVE
        my $fd = $_;               #### REMOVE
        $fd = fileno $fd if ref $fd;    #### REMOVE
        _debug "enabling inheritance of ", $fd if _debugging_details;    #### REMOVE
        my $osfh = FdGetOsFHandle $fd;                                   #### REMOVE

        # Contrary to documentation, $! has the failure reason
        # (https://github.com/chorny/Win32API-File/issues/14)
        croak "$!: FdGetOsFHandle( $fd )"
          if !defined $osfh || $osfh == C_ABI_INVALID_HANDLE_VALUE;
        #### REMOVE
        SetHandleInformation( $osfh, HANDLE_FLAG_INHERIT, 1 );           #### REMOVE
    }    #### REMOVE
}    #### REMOVE
#### REMOVE
#sub _inherit {
#   for ( @_ ) {
#      next unless defined $_;
#      my $osfh = GetOsFHandle $_;
#      croak $^E if ! defined $osfh || $osfh == INVALID_HANDLE_VALUE;
#      SetHandleInformation( $osfh, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT );
#   }
#}

=pod

=head1 FUNCTIONS

=over

=item optimize()

Most common incantations of C<run()> (I<not> C<harness()>, C<start()>,
or C<finish()>) now use temporary files to redirect input and output
instead of pumper processes.

Temporary files are used when sending to child processes if input is
taken from a scalar with no filter subroutines.  This is the only time
we can assume that the parent is not interacting with the child's
redirected input as it runs.

Temporary files are used when receiving from children when output is
to a scalar or subroutine with or without filters, but only if
the child in question closes its inputs or takes input from 
unfiltered SCALARs or named files.  Normally, a child inherits its STDIN
from its parent; to close it, use "0<&-" or the C<< noinherit => 1 >> option.
If data is sent to the child from CODE refs, filehandles or from
scalars through filters than the child's outputs will not be optimized
because C<optimize()> assumes the parent is interacting with the child.
It is ok if the output is filtered or handled by a subroutine, however.

This assumes that all named files are real files (as opposed to named
pipes) and won't change; and that a process is not communicating with
the child indirectly (through means not visible to IPC::Run).
These can be an invalid assumptions, but are the 99% case.
Write me if you need an option to enable or disable optimizations; I
suspect it will work like the C<binary()> modifier.

To detect cases that you might want to optimize by closing inputs, try
setting the C<IPCRUNDEBUG> environment variable to the special C<notopt>
value:

   C:> set IPCRUNDEBUG=notopt
   C:> my_app_that_uses_IPC_Run.pl

=item optimizer() rationalizations

Only for that limited case can we be sure that it's ok to batch all the
input in to a temporary file.  If STDIN is from a SCALAR or from a named
file or filehandle (again, only in C<run()>), then outputs to CODE refs
are also assumed to be safe enough to batch through a temp file,
otherwise only outputs to SCALAR refs are batched.  This can cause a bit
of grief if the parent process benefits from or relies on a bit of
"early returns" coming in before the child program exits.  As long as
the output is redirected to a SCALAR ref, this will not be visible.
When output is redirected to a subroutine or (deprecated) filters, the
subroutine will not get any data until after the child process exits,
and it is likely to get bigger chunks of data at once.

The reason for the optimization is that, without it, "pumper" processes
are used to overcome the inconsistencies of the Win32 API.  We need to
use anonymous pipes to connect to the child processes' stdin, stdout,
and stderr, yet select() does not work on these.  select() only works on
sockets on Win32.  So for each redirected child handle, there is
normally a "pumper" process that connects to the parent using a
socket--so the parent can select() on that fd--and to the child on an
anonymous pipe--so the child can read/write a pipe.

Using a socket to connect directly to the child (as at least one MSDN
article suggests) seems to cause the trailing output from most children
to be lost.  I think this is because child processes rarely close their
stdout and stderr explicitly, and the winsock dll does not seem to flush
output when a process that uses it exits without explicitly closing
them.

Because of these pumpers and the inherent slowness of Win32
CreateProcess(), child processes with redirects are quite slow to
launch; so this routine looks for the very common case of
reading/writing to/from scalar references in a run() routine and
converts such reads and writes in to temporary file reads and writes.

Such files are marked as FILE_ATTRIBUTE_TEMPORARY to increase speed and
as FILE_FLAG_DELETE_ON_CLOSE so it will be cleaned up when the child
process exits (for input files).  The user's default permissions are
used for both the temporary files and the directory that contains them,
hope your Win32 permissions are secure enough for you.  Files are
created with the Win32API::File defaults of
FILE_SHARE_READ|FILE_SHARE_WRITE.

Setting the debug level to "details" or "gory" will give detailed
information about the optimization process; setting it to "basic" or
higher will tell whether or not a given call is optimized.  Setting
it to "notopt" will highlight those calls that aren't optimized.

=cut

sub optimize {
    my ($h) = @_;

    my @kids = @{ $h->{KIDS} };

    my $saw_pipe;

    my ( $ok_to_optimize_outputs, $veto_output_optimization );

    for my $kid (@kids) {
        ( $ok_to_optimize_outputs, $veto_output_optimization ) = ()
          unless $saw_pipe;

        _debug "Win32 optimizer: (kid $kid->{NUM}) STDIN piped, carrying over ok of non-SCALAR output optimization"
          if _debugging_details && $ok_to_optimize_outputs;
        _debug "Win32 optimizer: (kid $kid->{NUM}) STDIN piped, carrying over veto of non-SCALAR output optimization"
          if _debugging_details && $veto_output_optimization;

        if ( $h->{noinherit} && !$ok_to_optimize_outputs ) {
            _debug "Win32 optimizer: (kid $kid->{NUM}) STDIN not inherited from parent oking non-SCALAR output optimization"
              if _debugging_details && $ok_to_optimize_outputs;
            $ok_to_optimize_outputs = 1;
        }

        for ( @{ $kid->{OPS} } ) {
            if ( substr( $_->{TYPE}, 0, 1 ) eq "<" ) {
                if ( $_->{TYPE} eq "<" ) {
                    if ( @{ $_->{FILTERS} } > 1 ) {
                        ## Can't assume that the filters are idempotent.
                    }
                    elsif (ref $_->{SOURCE} eq "SCALAR"
                        || ref $_->{SOURCE} eq "GLOB"
                        || UNIVERSAL::isa( $_, "IO::Handle" ) ) {
                        if ( $_->{KFD} == 0 ) {
                            _debug
                              "Win32 optimizer: (kid $kid->{NUM}) 0$_->{TYPE}",
                              ref $_->{SOURCE},
                              ", ok to optimize outputs"
                              if _debugging_details;
                            $ok_to_optimize_outputs = 1;
                        }
                        $_->{SEND_THROUGH_TEMP_FILE} = 1;
                        next;
                    }
                    elsif ( !ref $_->{SOURCE} && defined $_->{SOURCE} ) {
                        if ( $_->{KFD} == 0 ) {
                            _debug
                              "Win32 optimizer: (kid $kid->{NUM}) 0<$_->{SOURCE}, ok to optimize outputs",
                              if _debugging_details;
                            $ok_to_optimize_outputs = 1;
                        }
                        next;
                    }
                }
                _debug
                  "Win32 optimizer: (kid $kid->{NUM}) ",
                  $_->{KFD},
                  $_->{TYPE},
                  defined $_->{SOURCE}
                  ? ref $_->{SOURCE}
                      ? ref $_->{SOURCE}
                      : $_->{SOURCE}
                  : defined $_->{FILENAME} ? $_->{FILENAME}
                  : "",
                  @{ $_->{FILTERS} } > 1 ? " with filters" : (),
                  ", VETOING output opt."
                  if _debugging_details || _debugging_not_optimized;
                $veto_output_optimization = 1;
            }
            elsif ( $_->{TYPE} eq "close" && $_->{KFD} == 0 ) {
                $ok_to_optimize_outputs = 1;
                _debug "Win32 optimizer: (kid $kid->{NUM}) saw 0<&-, ok to optimize outputs"
                  if _debugging_details;
            }
            elsif ( $_->{TYPE} eq "dup" && $_->{KFD2} == 0 ) {
                $veto_output_optimization = 1;
                _debug "Win32 optimizer: (kid $kid->{NUM}) saw 0<&$_->{KFD2}, VETOING output opt."
                  if _debugging_details || _debugging_not_optimized;
            }
            elsif ( $_->{TYPE} eq "|" ) {
                $saw_pipe = 1;
            }
        }

        if ( !$ok_to_optimize_outputs && !$veto_output_optimization ) {
            _debug "Win32 optimizer: (kid $kid->{NUM}) child STDIN not redirected, VETOING non-SCALAR output opt."
              if _debugging_details || _debugging_not_optimized;
            $veto_output_optimization = 1;
        }

        if ( $ok_to_optimize_outputs && $veto_output_optimization ) {
            $ok_to_optimize_outputs = 0;
            _debug "Win32 optimizer: (kid $kid->{NUM}) non-SCALAR output optimizations VETOed"
              if _debugging_details || _debugging_not_optimized;
        }

        ## SOURCE/DEST ARRAY means it's a filter.
        ## TODO: think about checking to see if the final input/output of
        ## a filter chain (an ARRAY SOURCE or DEST) is a scalar...but
        ## we may be deprecating filters.

        for ( @{ $kid->{OPS} } ) {
            if ( $_->{TYPE} eq ">" ) {
                if (
                    ref $_->{DEST} eq "SCALAR"
                    || (
                        (
                               @{ $_->{FILTERS} } > 1
                            || ref $_->{DEST} eq "CODE"
                            || ref $_->{DEST} eq "ARRAY"    ## Filters?
                        )
                        && ( $ok_to_optimize_outputs && !$veto_output_optimization )
                    )
                  ) {
                    $_->{RECV_THROUGH_TEMP_FILE} = 1;
                    next;
                }
                _debug
                  "Win32 optimizer: NOT optimizing (kid $kid->{NUM}) ",
                  $_->{KFD},
                  $_->{TYPE},
                  defined $_->{DEST}
                  ? ref $_->{DEST}
                      ? ref $_->{DEST}
                      : $_->{SOURCE}
                  : defined $_->{FILENAME} ? $_->{FILENAME}
                  : "",
                  @{ $_->{FILTERS} } ? " with filters" : (),
                  if _debugging_details;
            }
        }
    }

}

=pod

=item win32_parse_cmd_line

   @words = win32_parse_cmd_line( q{foo bar 'baz baz' "bat bat"} );

returns 4 words. This parses like the bourne shell (see
the bit about shellwords() in L<Text::ParseWords>), assuming we're
trying to be a little cross-platform here.  The only difference is
that "\" is *not* treated as an escape except when it precedes 
punctuation, since it's used all over the place in DOS path specs.

TODO: strip caret escapes?

TODO: use
https://docs.microsoft.com/en-us/cpp/cpp/main-function-command-line-args#parsing-c-command-line-arguments

TODO: globbing? probably not (it's unDOSish).

TODO: shebang emulation? Probably, but perhaps that should be part
of Run.pm so all spawned processes get the benefit.

LIMITATIONS: shellwords dies silently on malformed input like 

   a\"

=cut

sub win32_parse_cmd_line {
    my $line = shift;
    $line =~ s{(\\[\w\s])}{\\$1}g;
    return shellwords $line;
}

=pod

=item win32_spawn

Spawns a child process, possibly with STDIN, STDOUT, and STDERR (file descriptors 0, 1, and 2, respectively) redirected.

B<LIMITATIONS>.

Cannot redirect higher file descriptors due to lack of support for this in the
Win32 environment.

This can be worked around by marking a handle as inheritable in the
parent (or leaving it marked; this is the default in perl), obtaining its
Win32 handle with C<Win32API::GetOSFHandle(FH)> or
C<Win32API::FdGetOsFHandle($fd)> and passing it to the child using the command
line, the environment, or any other IPC mechanism (it's a plain old integer).
The child can then use C<OsFHandleOpen()> or C<OsFHandleOpenFd()> and possibly
C<<open FOO ">&BAR">> or C<<open FOO ">&$fd>> as need be.  Ach, the pain!

=cut

sub _save {
    my ( $saved, $saved_as, $fd ) = @_;

    ## We can only save aside the original fds once.
    return if exists $saved->{$fd};

    my $saved_fd = IPC::Run::_dup($fd);
    _dont_inherit $saved_fd;

    $saved->{$fd}          = $saved_fd;
    $saved_as->{$saved_fd} = $fd;

    _dont_inherit $saved->{$fd};
}

sub _dup2_gently {
    my ( $saved, $saved_as, $fd1, $fd2 ) = @_;
    _save $saved, $saved_as, $fd2;

    if ( exists $saved_as->{$fd2} ) {
        ## The target fd is colliding with a saved-as fd, gotta bump
        ## the saved-as fd to another fd.
        my $orig_fd  = delete $saved_as->{$fd2};
        my $saved_fd = IPC::Run::_dup($fd2);
        _dont_inherit $saved_fd;

        $saved->{$orig_fd}     = $saved_fd;
        $saved_as->{$saved_fd} = $orig_fd;
    }
    _debug "moving $fd1 to kid's $fd2" if _debugging_details;
    IPC::Run::_dup2_rudely( $fd1, $fd2 );
}

sub win32_spawn {
    my ( $cmd, $ops ) = @_;

    my ( $app, $cmd_line );
    my $need_pct = 0;
    if ( UNIVERSAL::isa( $cmd, 'IPC::Run::Win32Process' ) ) {
        $app      = $cmd->{lpApplicationName};
        $cmd_line = $cmd->{lpCommandLine};
    }
    elsif ( $cmd->[0] !~ /\.(bat|cmd) *$/i ) {
        $app      = $cmd->[0];
        $cmd_line = Win32::ShellQuote::quote_native(@$cmd);
    }
    else {
        # Batch file, so follow the batch-specific guidance of
        # https://docs.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessa
        # There's no one true way to locate cmd.exe.  In the unlikely event that
        # %COMSPEC% is missing, fall back on a Windows API.  We could search
        # %PATH% like _wsystem() does.  That would be prone to security bugs,
        # and one fallback is enough.
        $app = (
            $ENV{COMSPEC}
              || File::Spec->catfile(
                Win32::GetFolderPath(Win32::CSIDL_SYSTEM),
                'cmd.exe'
              )
        );

        # Win32 rejects attempts to create files with names containing certain
        # characters.  Ignore most, but reject the subset that might otherwise
        # cause us to execute the wrong file instead of failing cleanly.
        if ( $cmd->[0] =~ /["\r\n\0]/ ) {
            croak "invalid batch file name";
        }

        # Make cmd.exe see the batch file name as quoted.  Suppose we instead
        # used caret escapes, as we do for arguments.  cmd.exe could then "break
        # the command token at the first occurrence of <space> , ; or ="
        # (https://stackoverflow.com/a/4095133).
        my @parts = qq{"$cmd->[0]"};

        # cmd.exe will strip escapes once when parsing our $cmd_line and again
        # where the batch file injects the argument via %*, %1, etc.  Compensate
        # by adding one extra cmd_escape layer.
        if ( @$cmd > 1 ) {
            my @q = Win32::ShellQuote::quote_cmd( @{$cmd}[ 1 .. $#{$cmd} ] );
            push @parts, map { Win32::ShellQuote::cmd_escape($_) } @q;
        }

        # One can't stop cmd.exe from expanding %var%, so inject each literal %
        # via an environment variable.  Delete that variable before the real
        # child can see it.  See
        # https://www.dostips.com/forum/viewtopic.php?f=3&t=10131 for more on
        # this technique and the limitations of alternatives.
        $cmd_line = join ' ', @parts;
        if ( $cmd_line =~ s/%/%ipcrunpct%/g ) {
            $cmd_line = qq{/c "set "ipcrunpct=" & $cmd_line"};
            $need_pct = 1;
        }
        else {
            $cmd_line = qq{/c "$cmd_line"};
        }
    }
    _debug "app: ", $app
      if _debugging;
    _debug "cmd line: ", $cmd_line
      if _debugging;

    ## NOTE: The debug pipe write handle is passed to pump processes as STDOUT.
    ## and is not to the "real" child process, since they would not know
    ## what to do with it...unlike Unix, we have no code executing in the
    ## child before the "real" child is exec()ed.

    my %saved;       ## Map of parent's orig fd -> saved fd
    my %saved_as;    ## Map of parent's saved fd -> orig fd, used to
    ## detect collisions between a KFD and the fd a
    ## parent's fd happened to be saved to.

    for my $op (@$ops) {
        _dont_inherit $op->{FD} if defined $op->{FD};

        if ( defined $op->{KFD} && $op->{KFD} > 2 ) {
            ## TODO: Detect this in harness()
            ## TODO: enable temporary redirections if ever necessary, not
            ## sure why they would be...
            ## 4>&1 1>/dev/null 1>&4 4>&-
            croak "Can't redirect fd #", $op->{KFD}, " on Win32";
        }

        ## This is very similar logic to IPC::Run::_do_kid_and_exit().
        if ( defined $op->{TFD} ) {
            unless ( $op->{TFD} == $op->{KFD} ) {
                _dup2_gently \%saved, \%saved_as, $op->{TFD}, $op->{KFD};
                _dont_inherit $op->{TFD};
            }
        }
        elsif ( $op->{TYPE} eq "dup" ) {
            _dup2_gently \%saved, \%saved_as, $op->{KFD1}, $op->{KFD2}
              unless $op->{KFD1} == $op->{KFD2};
        }
        elsif ( $op->{TYPE} eq "close" ) {
            _save \%saved, \%saved_as, $op->{KFD};
            IPC::Run::_close( $op->{KFD} );
        }
        elsif ( $op->{TYPE} eq "init" ) {
            ## TODO: detect this in harness()
            croak "init subs not allowed on Win32";
        }
    }

    local $ENV{ipcrunpct} = '%' if $need_pct;
    my $process;
    Win32::Process::Create(
        $process,
        $app,
        $cmd_line,
        1,    ## Inherit handles
        0,    ## Inherit parent priority class. Was NORMAL_PRIORITY_CLASS
        ".",
      )
      or do {
        my $err = Win32::FormatMessage( Win32::GetLastError() );
        $err =~ s/\r?\n$//s;
        croak "$err: Win32::Process::Create()";
      };

    for my $orig_fd ( keys %saved ) {
        IPC::Run::_dup2_rudely( $saved{$orig_fd}, $orig_fd );
        IPC::Run::_close( $saved{$orig_fd} );
    }

    return ( $process->GetProcessID(), $process );
}

1;

=pod

=back

=head1 AUTHOR

Barries Slaymaker <barries@slaysys.com>.  Funded by Perforce Software, Inc.

=head1 COPYRIGHT

Copyright 2001, Barrie Slaymaker, All Rights Reserved.

You may use this under the terms of either the GPL 2.0 or the Artistic License.

=cut
