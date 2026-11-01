# 07: `kwt ls` and `kwt rm`

**What to build:** `kwt ls` lists the Project's Worktrees and marks which have a kit session running. `kwt rm [<branch>]` kills the Worktree's windows and removes the Worktree; it refuses while a kit session is running unless `--force` is passed; bare `kwt rm` chooses from the available Worktrees. It never modifies the Main checkout.

**Blocked by:** 04 — Open a tmux window per Worktree and launch kit

**Status:** ready-for-agent

- [ ] `kwt ls` lists every Worktree of the Project.
- [ ] `kwt ls` marks which Worktrees currently have a kit session running.
- [ ] `kwt rm <branch>` kills that Worktree's windows and removes the Worktree.
- [ ] `kwt rm <branch>` refuses while a kit session is running unless `--force` is passed.
- [ ] Bare `kwt rm` offers the available Worktrees to choose from.
- [ ] `kwt rm` never modifies the Main checkout.

## Comments

Implemented; covered by `test/07_*_test.sh` (see `test/run.sh`).
