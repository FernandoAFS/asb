# 06: `kwt shell <dir>`

**What to build:** `kwt shell <dir>` runs a shell under the same sandbox policy as a kit launch: the Target directory writable, git read-only by default, and `--allow-git-write` available to open git. It is not a kit session and does not set headless mode.

**Blocked by:** 05 — Run the kit launch inside the bwrap sandbox

**Status:** ready-for-agent

- [ ] `kwt shell <dir>` runs a sandboxed shell in the Target directory.
- [ ] The shell runs with the Target directory as its working directory.
- [ ] The shell is not headless.
- [ ] `--allow-git-write` applies to the shell.
- [ ] A missing directory fails with a clear error.

## Comments

Implemented; covered by `test/06_*_test.sh` (see `test/run.sh`).
