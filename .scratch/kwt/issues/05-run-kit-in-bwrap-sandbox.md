# 05: Run the kit launch inside the bwrap sandbox

**What to build:** The kit launch runs inside a default-deny `bwrap` sandbox: the Target directory, `/tmp`, and kit's session store are writable; the Project's git state is read-only; the system directories needed to run, the kit binary's directory, and kit's config are read-only; network is allowed; the sandbox dies with its parent; and kit is always launched `--no-daemon` so the session cannot escape to the host daemon. `--allow-git-write` makes git writable instead of read-only.

**Blocked by:** 01 — Foundation

**Status:** ready-for-agent

- [ ] The sandboxed kit launch cannot write outside the Target directory, `/tmp`, and kit's session store.
- [ ] Git state is read-only inside the sandbox by default.
- [ ] Network access is available inside the sandbox (model calls and MCP servers work).
- [ ] The sandbox dies with its parent process.
- [ ] Kit is always launched `--no-daemon` under the sandbox and never becomes a host daemon session.
- [ ] `--allow-git-write` makes git writable.
- [ ] The full sandbox command line appears in the dry-run Plan.

## Comments

Implemented; covered by `test/05_*_test.sh` (see `test/run.sh`).

**Amended by 11 — Sandboxed kit sessions are ephemeral.** The acceptance
criterion that a session cannot write outside the Target, `/tmp`, and kit's
session store is now stronger: no session store is mounted at all. See ADR-0002.
