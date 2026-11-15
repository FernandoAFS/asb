# asb

`asb` runs an AI coding agent inside a sandbox: a single command that launches a
process in a default-deny `bwrap` sandbox with one writable directory, read-only
git state, and the host's tools and the agent's configuration mounted read-only
or, where the agent writes lock files to read its configuration, as an ephemeral
copy-on-write overlay. The agent profile is explicit — `asb kit` and `asb pig` —
and `asb --shell` runs a shell in the same sandbox for debugging. This file fixes
the words the project uses for those things.

## Language

**Target directory**:
The one directory a Sandboxed process may write to. `asb` resolves it from the
optional `<dir>` argument, defaulting to the current directory when omitted,
makes it the sandbox's working directory, and mounts it writable.
_Avoid_: worktree, root, cwd

**Sandbox**:
The `bwrap` invocation that runs a process with a default-deny filesystem. Only
the Target directory and `/tmp` are persistently writable. An agent's
configuration may be a copy-on-write overlay: readable from the host, writable
in an invisible tmpfs, with every write discarded when the sandbox exits. The
editor's state directory is not the host's either: `XDG_STATE_HOME` points at a
private tmpfs, so undo history and shada stay out of reach.
_Avoid_: jail, container, chroot

**agent session**:
A running agent inside the Sandbox. Its durability is the agent profile's: a kit
session is ephemeral and keeps its conversation in memory, while a pig session
writes its transcript to a store the Target owns, so it can be continued or
resumed. `asb --shell` runs a shell under the same policy but is not an agent
session.
_Avoid_: agent, bot, daemon

**Project**:
The git repository that contains the Target directory, when there is one. Its
git state is mounted read-only unless `--allow-git-write` is given.
_Avoid_: repo, workspace