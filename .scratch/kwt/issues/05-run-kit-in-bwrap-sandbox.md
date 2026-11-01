# 05: Run the kit launch inside the bwrap sandbox

**What to build:** The kit launch runs inside a default-deny `bwrap` sandbox: the Worktree, `/tmp`, and kit's session store are writable; git state and every linked dependency/env target are read-only; the system directories needed to run, the kit binary's directory, and kit's config are read-only; network is allowed; the sandbox dies with its parent; and kit is always launched `--no-daemon` so the session cannot escape to the host daemon. `--allow-git-write` makes git writable instead of read-only; linked targets stay read-only regardless.

**Blocked by:** 03 — Link shared dependency and env paths into the Worktree; 04 — Open a tmux window per Worktree and launch kit

**Status:** ready-for-agent

- [ ] The sandboxed kit launch cannot write outside the Worktree, `/tmp`, and kit's session store.
- [ ] Git state is read-only inside the sandbox by default.
- [ ] Every linked dependency/env target is read-only inside the sandbox.
- [ ] Network access is available inside the sandbox (model calls and MCP servers work).
- [ ] The sandbox dies with its parent process.
- [ ] Kit is always launched `--no-daemon` under the sandbox and never becomes a host daemon session.
- [ ] `--allow-git-write` makes git writable; linked targets remain read-only.
- [ ] The full sandbox command line appears in the dry-run Plan.

## Comments

Implemented; covered by `test/05_*_test.sh` (see `test/run.sh`).
