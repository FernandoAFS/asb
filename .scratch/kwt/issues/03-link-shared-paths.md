# 03: Link shared dependency and env paths into the Worktree

**What to build:** When a Worktree is created, the shared dependency and environment paths present in the Main checkout are linked into it: `.venv` when the Main checkout looks like Python, `node_modules` when it looks like Node, and `.env` always when present. Paths that already exist in the Worktree are never overwritten, and the links appear in the dry-run Plan.

**Blocked by:** 02 — Create-or-reuse a Worktree for a branch

**Status:** ready-for-agent

- [ ] `.venv` is linked into the Worktree when the Main checkout is detected as Python.
- [ ] `node_modules` is linked into the Worktree when the Main checkout is detected as Node.
- [ ] `.env` is linked into the Worktree whenever it is present in the Main checkout.
- [ ] Python and Node detection use the file set defined in the spec and do not link when absent.
- [ ] A path that already exists in the Worktree is left untouched.
- [ ] Only paths present in the Main checkout are linked; missing ones are silently skipped.
- [ ] The links to be created appear in the dry-run Plan.

## Comments

Implemented; covered by `test/03_*_test.sh` (see `test/run.sh`).
