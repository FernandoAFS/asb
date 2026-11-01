# 06: `kwt shell <branch>`

**What to build:** `kwt shell <branch>` opens an unsandboxed host shell window named `<slug>~` in the Worktree, for the operations the sandbox denies — dependency installs, commits, and pushes. It requires an existing Worktree unless `--create` is passed, and `--sandboxed` runs the same shell under the sandbox policy instead. The shell window is not a kit session and does not count against the one-kit-session-per-Worktree invariant.

**Blocked by:** 04 — Open a tmux window per Worktree and launch kit; 05 — Run the kit launch inside the bwrap sandbox

**Status:** ready-for-agent

- [ ] `kwt shell <branch>` opens a shell window named `<slug>~` in the Worktree.
- [ ] The shell is unsandboxed by default and can install dependencies, commit, and push.
- [ ] Without `--create`, a missing Worktree produces a clear error pointing to `kwt <branch>`.
- [ ] With `--create`, a missing Worktree is created first.
- [ ] `--sandboxed` runs the shell under the sandbox policy (git read-only).
- [ ] The shell window is not treated as a kit session.

## Comments

Implemented; covered by `test/06_*_test.sh` (see `test/run.sh`).
