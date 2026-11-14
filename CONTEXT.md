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
the Target directory is persistently writable. `/tmp` is a private tmpfs
recreated for each Sandbox, so it is writable only for that Sandbox's lifetime
and the host's temporary files and sockets stay out of reach. The host's `/run`
is not mounted either, and the tmux and D-Bus rendezvous variables are dropped,
so host sockets are not reachable by path. An agent's configuration may be a
copy-on-write overlay: readable from the host, writable in an invisible tmpfs,
with every write discarded when the sandbox exits. The editor's state and cache
directories are not the host's either: `XDG_STATE_HOME` and `XDG_CACHE_HOME`
point at private tmpfs directories, so undo history, shada, and cached bytecode
stay out of reach. The Sandbox also has private PID, IPC, and UTS namespaces, so
it sees only its own processes and IPC objects and cannot rename the host. It
cannot create a new user namespace, so nested sandboxes and rootless containers
do not work inside it.
_Avoid_: jail, container, chroot

**agent session**:
A running agent inside the Sandbox. An agent session is ephemeral: the launcher
mounts no session store and starts the agent without a durable session, so it
keeps its conversation in memory and writes no session record. `asb --shell`
runs a shell under the same policy but is not an agent session.
_Avoid_: agent, bot, daemon

**Project**:
The git repository that contains the Target directory, when there is one. Its
git state is mounted read-only unless `--allow-git-write` is given.
_Avoid_: repo, workspace