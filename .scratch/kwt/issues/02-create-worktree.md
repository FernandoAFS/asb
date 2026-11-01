# 02: Create-or-reuse a Worktree for a branch

**What to build:** Running `kwt <branch>` in a real Project creates the Worktree at `<main checkout>/.worktrees/<slug>` for the given branch, adding `.worktrees` to git's exclude so the Main checkout stays clean. A missing branch is created from `--base` (default: current HEAD); an existing branch is checked out into the Worktree. If the Worktree already exists it is reused, never destroyed.

**Blocked by:** 01 — Foundation — CLI, Project resolution, and the `--dry-run` plan

**Status:** ready-for-agent

- [ ] `kwt <branch>` creates a Worktree at `.worktrees/<slug>` and that Worktree is a usable git working tree.
- [ ] `.worktrees` is excluded through git's own exclude mechanism, not the tracked ignore file.
- [ ] A branch that does not exist is created from `--base`, defaulting to the current HEAD.
- [ ] A branch that already exists is checked out into the Worktree rather than recreated.
- [ ] Re-running `kwt <branch>` for an existing Worktree reuses it and changes nothing.
- [ ] The Worktree path, branch, and base appear in the dry-run Plan.

## Comments

Implemented; covered by `test/02_*_test.sh` (see `test/run.sh`).
