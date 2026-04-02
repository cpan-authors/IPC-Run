#!/usr/bin/perl

=pod

=head1 NAME

win32_parse.t - Test win32_parse_cmd_line and batch file path handling

=head1 DESCRIPTION

Tests for Windows command-line parsing (win32_parse_cmd_line) and batch file
execution with various path forms (forward slashes, spaces in paths).

See also: GH#142, GH#143, GH#147.

=cut

use strict;
use warnings;

BEGIN {
    $| = 1;
    $^W = 1;
    if ( $ENV{PERL_CORE} ) {
        chdir '../lib/IPC/Run' if -d '../lib/IPC/Run';
        unshift @INC, 'lib', '../..';
        $^X = '../../../t/' . $^X;
    }
}

use Test::More;

BEGIN {
    plan skip_all => 'Windows-specific tests'
      unless $^O eq 'MSWin32';
}

use IPC::Run::Win32Helper qw(win32_parse_cmd_line);

## ======================================================================
## win32_parse_cmd_line tests
## ======================================================================

# Basic whitespace splitting
is_deeply [ win32_parse_cmd_line('foo bar baz') ],
  [qw(foo bar baz)],
  'basic whitespace splitting';

# Double-quoted argument preserves spaces
is_deeply [ win32_parse_cmd_line('foo "bar baz" qux') ],
  [ 'foo', 'bar baz', 'qux' ],
  'double quotes group words';

# Single quotes are NOT grouping on Windows — they are literal characters
is_deeply [ win32_parse_cmd_line(q{foo 'bar baz' qux}) ],
  [ 'foo', "'bar", "baz'", 'qux' ],
  'single quotes are literal (not grouping) on Windows';

# Backslash in Windows paths — literal, not escape
is_deeply [ win32_parse_cmd_line('C:\\Users\\test\\script.bat arg') ],
  [ 'C:\\Users\\test\\script.bat', 'arg' ],
  'backslashes in paths are literal';

# Backslash before double quote — escape
is_deeply [ win32_parse_cmd_line('foo \\"bar') ],
  [ 'foo', '"bar' ],
  'backslash before double quote is escape';

# Even backslashes before double quote — halved, quote toggles
is_deeply [ win32_parse_cmd_line('foo \\\\"bar baz"') ],
  [ 'foo', '\\bar baz' ],
  'even backslashes before quote: halved + quote toggles';

# Odd backslashes before double quote — halved + literal quote
is_deeply [ win32_parse_cmd_line('foo \\\\\\"bar') ],
  [ 'foo', '\\"bar' ],
  'odd backslashes before quote: halved + literal quote';

# Empty double-quoted argument
is_deeply [ win32_parse_cmd_line('foo "" bar') ],
  [ 'foo', '', 'bar' ],
  'empty double-quoted argument';

# Tab as whitespace
is_deeply [ win32_parse_cmd_line("foo\tbar") ],
  [ 'foo', 'bar' ],
  'tab separates arguments';

# Leading and trailing whitespace
is_deeply [ win32_parse_cmd_line('  foo  bar  ') ],
  [ 'foo', 'bar' ],
  'leading/trailing whitespace stripped';

# Empty string
is_deeply [ win32_parse_cmd_line('') ],
  [],
  'empty string returns empty list';

# Only whitespace
is_deeply [ win32_parse_cmd_line('   ') ],
  [],
  'whitespace-only string returns empty list';

# Mixed quotes and paths
is_deeply [ win32_parse_cmd_line('C:\\Program" "Files\\app.exe "hello world"') ],
  [ 'C:\\Program Files\\app.exe', 'hello world' ],
  'mid-argument quoting (Program" "Files pattern)';

# Forward slashes (relevant to GH#147 — batch file paths)
is_deeply [ win32_parse_cmd_line('./script.bat arg1 arg2') ],
  [ './script.bat', 'arg1', 'arg2' ],
  'forward slashes in relative path';

is_deeply [ win32_parse_cmd_line('"dir with spaces/script.bat" arg') ],
  [ 'dir with spaces/script.bat', 'arg' ],
  'quoted path with forward slashes and spaces';

# Practical cmd.exe invocation pattern
is_deeply [ win32_parse_cmd_line('script.bat "hello world" %USERNAME%') ],
  [ 'script.bat', 'hello world', '%USERNAME%' ],
  'typical batch file invocation';

## ======================================================================
## Batch file path forms (Windows-only, GH#147)
## ======================================================================

{
    require IPC::Run;
    require Cwd;
    require File::Spec;
    require File::Temp;
    require Win32::ShellQuote;

    my $perl = $^X;

    my $parent_dir = File::Temp::tempdir( CLEANUP => 1 );
    my $space_dir = File::Spec->catdir( $parent_dir, 'dir with spaces' );
    mkdir $space_dir or die "mkdir $space_dir: $!";
    my $no_space_dir = File::Spec->catdir( $parent_dir, 'nospace' );
    mkdir $no_space_dir or die "mkdir $no_space_dir: $!";

    my $bat_source = sprintf(
        qq{\@echo off\n"%s" -e %s %%*},
        $perl,
        Win32::ShellQuote::quote_cmd('binmode STDOUT; print join "\0", @ARGV')
    );

    # Create batch files in both directories.
    for my $dir ( $space_dir, $no_space_dir ) {
        for my $name ( 'simple.bat', 'script file.bat' ) {
            my $path = File::Spec->catfile( $dir, $name );
            open my $fh, '>', $path or die "open $path: $!";
            print {$fh} $bat_source;
            close $fh;
        }
    }

    my $initial_cwd = Cwd::getcwd();
    chdir $parent_dir or die "chdir $parent_dir: $!";

    my $out;
    my @path_forms;

    # Test forward slashes in relative paths (GH#147 failures).
    push @path_forms, (
        [ 'nospace/simple.bat',           'forward slash, no spaces' ],
        [ 'dir with spaces/simple.bat',   'forward slash, space in dir' ],
        [ './nospace/simple.bat',          'dot-slash prefix, no spaces' ],
    );

    # Test backslash equivalents (these already work, confirming parity).
    push @path_forms, (
        [ 'nospace\\simple.bat',          'backslash, no spaces' ],
        [ 'dir with spaces\\simple.bat',  'backslash, space in dir' ],
    );

    # Test space in executable name.
    push @path_forms, (
        [ 'nospace/script file.bat',            'forward slash, space in filename' ],
        [ 'dir with spaces/script file.bat',    'forward slash, spaces everywhere' ],
        [ 'dir with spaces\\script file.bat',   'backslash, spaces everywhere' ],
    );

    for my $case (@path_forms) {
        my ( $path, $desc ) = @$case;
        my $ok = eval {
            IPC::Run::run( [ $path, 'test_arg' ], '>', \$out );
            1;
        };
        if ( !$ok ) {
            fail "run died for $desc ($path): $@";
        }
        else {
            $out =~ s/\r\n/\n/g;
            is $out, "test_arg", "$desc: $path";
        }
    }

    chdir $initial_cwd;
}

done_testing;
