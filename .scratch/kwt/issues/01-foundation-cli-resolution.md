# 01: Foundation — CLI, Target directory resolution, and the `--dry-run` plan

**What to build:** A single runnable `kwt` that parses its arguments, resolves the Target directory from the optional `<dir>` argument (defaulting to the current directory), and prints a deterministic, line-oriented Plan when `--dry-run` is given, performing no side effects. This establishes the seam every later ticket is tested through.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `kwt <dir> --dry-run` resolves the directory to an absolute path and prints it.
- [ ] `kwt --dry-run` with no `<dir>` defaults to the current directory.
- [ ] A missing directory fails with a clear non-zero error.
- [ ] `/` is refused.
- [ ] The Plan is deterministic and line-oriented — stable records, no prose to parse.
- [ ] `--dry-run` performs no bwrap, kit, or filesystem side effects.
- [ ] Argument parsing accepts `<dir>`, `--allow-git-write`, `--dry-run`, and `-- <prompt>`.
- [ ] `kwt shell <dir>` is dispatched to the shell subcommand.

## Comments

Implemented; covered by `test/01_*_test.sh` (see `test/run.sh`).
