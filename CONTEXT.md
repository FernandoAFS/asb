# kwt

`kwt` runs kit inside a sandbox: a single command that launches a process in a
default-deny `bwrap` sandbox with one writable directory, read-only git state,
and the host's tools and kit configuration mounted read-only. This file fixes
the words the project uses for those things.

## Language

**Target directory**:
The one directory a Sandboxed process may write to. `kwt` resolves it from the
optional `<dir>` argument, defaulting to the current directory when omitted,
makes it the sandbox's working directory, and mounts it writable.
_Avoid_: worktree, root, cwd

**Sandbox**:
The `bwrap` invocation that runs a process with a default-deny filesystem. Only
the Target directory and `/tmp` are writable.
_Avoid_: jail, container, chroot

**kit session**:
A running kit instance inside the Sandbox. A kit session is ephemeral: `kwt`
launches it with `--no-session`, so it keeps its conversation in memory and
writes no session record. `kwt shell` runs a shell under the same policy but is
not a kit session.
_Avoid_: agent, daemon

**Project**:
The git repository that contains the Target directory, when there is one. Its
git state is mounted read-only unless `--allow-git-write` is given.
_Avoid_: repo, workspace
