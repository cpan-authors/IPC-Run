# CLAUDE.md — IPC::Run

## What is IPC::Run

IPC::Run is a Perl module for running child processes with advanced I/O redirection.
It supports pipes, pseudo-terminals (ptys), timeouts, and both synchronous (`run()`)
and asynchronous (`start()`/`pump()`/`finish()`) execution. Supports Unix and Win32.

Current version: defined in `lib/IPC/Run.pm` (`$VERSION` variable).

## Project structure

```
lib/IPC/Run.pm          # Main module (~5100 lines). Core logic: harness parsing,
                         # pipe/pty setup, fork/exec, pump loop (select-based I/O),
                         # signal handling, process reaping.
lib/IPC/Run/IO.pm       # I/O operation objects (pipe/file/pty redirections)
lib/IPC/Run/Timer.pm    # Timer objects for timeouts
lib/IPC/Run/Debug.pm    # Debug/trace infrastructure (IPCRUNDEBUG env var)
lib/IPC/Run/Win32*.pm   # Win32-specific implementations
t/                      # Test suite (~40 test files, ~870 tests)
xt/                     # Author tests (pod coverage, minimum perl version)
eg/                     # Example scripts
```

## Building and testing

```bash
perl Makefile.PL        # Generate Makefile
make                    # Build
make test               # Run test suite
prove -Ilib t/          # Run tests with prove (faster, parallel-capable)
prove -Ilib t/pty.t     # Run a single test file
```

Key dependencies: `IO::Pty` (optional, needed for pty tests), `POSIX`, `Fcntl`.

## Test conventions

- Tests use `Test::More`. Most set `$^W = 1` in BEGIN blocks.
- All code (including tests) must be compatible with Perl 5.8.8+. Avoid features
  added in later versions (e.g., `//=` requires 5.10, `say` requires 5.10).
  Use `print {$fh} $data` (block form) instead of `print $fh $data` for lexical
  filehandles to avoid indirect object ambiguity on older perls.
- Many tests are skipped on specific platforms (Win32, darwin/freebsd for pty deadlocks).
- The `$^X` variable is used to invoke perl subprocesses in tests.
- Helper function `_map_fds` (from `IPC::Run::Debug`) tracks open file descriptors.
- Tests should validate behavior, not implementation details.

## Key architectural concepts

### Harness parsing (line ~1980-2330)
Arguments to `run()`/`start()` are parsed into operations:
- **Succinct mode**: positional args auto-map to fd 0, 1, 2, 3...
- **Explicit mode**: redirect operators (`<`, `>`, `>pipe`, `<pty<`, `>pty>`, etc.)
- Operations become `IPC::Run::IO` objects stored in `$kid->{OPS}`

### Process lifecycle
1. `harness()` — parse args, create harness object
2. `start()` → `_open_pipes()` — create pipes/ptys, fork children
3. `_do_kid_and_exit()` — child process: close unneeded fds, dup2 to target fds, exec
4. `pump()` — parent: select() loop for I/O multiplexing
5. `finish()` — drain pipes, reap children, collect exit codes

### File descriptor management
- `%fds` hash tracks all open fds and their state (`{needed}`, `{lazy_close}`)
- `_pipe()` creates blocking pipes (child→parent), `_pipe_nb()` creates non-blocking (parent→child)
- `_dup2_gently()` safely moves fds around, avoiding conflicts
- In child: `close_terminal()` frees fds 0-2 for pty reassignment

### Signal handling
- `SIGPIPE` is locally set to `IGNORE` during pump to handle broken pipes gracefully
- `SIGCHLD` handler ensures child reaping
- `POSIX::_exit()` used in child (not `exit()`) to avoid DESTROY handlers

## Common pitfalls

- **`>pipe` with `run()`**: Deadlocks if child output exceeds kernel pipe buffer (~64KB).
  Use `start()`/`pump()`/`finish()` or `>` with scalar ref instead.
- **Pty tests on macOS/BSD**: Many pty tests skip on darwin/freebsd due to deadlock issues.
- **Win32**: Significantly different codepath. No signals, no ptys. Uses sockets instead of pipes.
- **`$^W = 1` in child**: Fd manipulation in child can trigger "Filehandle STDIN reopened" warnings.
  Fixed by `local $^W = 0` in the child eval block.

## Coding conventions

- Perl 5.8.8+ compatible. No Moose/Moo, minimal dependencies.
- Internal functions prefixed with `_` (e.g., `_write`, `_close`, `_dup2_rudely`).
- Debug output via `_debug` (controlled by `IPCRUNDEBUG` env var).
- Win32 code paths use `Win32_MODE` constant for conditional compilation.
- Method signatures use `my IPC::Run $self = shift` (pseudo-typing).
- Error handling: `croak` for user errors, `confess` for internal bugs.
