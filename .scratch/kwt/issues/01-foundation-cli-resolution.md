# 01: Foundation — CLI, Project resolution, and the `--dry-run` plan

**What to build:** A single runnable `kwt` whose branch subcommand parses its arguments and resolves the Project, Main checkout, Slug, and Worktree path from anywhere inside a git repository — including from inside an existing Worktree — and prints a deterministic, line-oriented Plan when `--dry-run` is given, performing no side effects. This establishes the seam every later ticket is tested through.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `kwt <branch> --dry-run` runs from any subdirectory of a Project and prints the resolved Plan.
- [ ] When run from inside a Worktree, resolution yields the Main checkout, not the Worktree.
- [ ] The Plan is deterministic and line-oriented — stable records, no prose to parse.
- [ ] `--dry-run` performs no git, tmux, filesystem, or process side effects.
- [ ] Running outside a git repository fails with a clear non-zero error.
- [ ] Argument parsing accepts `<branch>`, `--base`, `-d`/`--detached`, `--allow-git-write`, `--dry-run`, and `-- <prompt>`.

## Comments

Implemented; covered by `test/01_*_test.sh` (see `test/run.sh`).
