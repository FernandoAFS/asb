# Sandbox every kit launch with bwrap: shared state read-only, `--no-daemon`

## Status

Accepted.

## Context

A kit session runs an agent that can execute tools on the developer's machine.
Without isolation a mistake, or a prompt injection, can write anywhere the
developer can. `kwt` creates a Worktree per branch precisely so that work is
confined to one directory, so the launch should honour that boundary.

## Decision

Every kit launch runs inside a single `bwrap` invocation that is default-deny on
the filesystem. Only the Worktree, `/tmp`, and kit's session store are writable.
Everything shared is read-only: the Project's git state and every dependency or
env target linked into the Worktree. Git is read-only by default;
`--allow-git-write` makes the shared git directory writable instead, while the
linked targets stay read-only regardless. The system directories needed to run —
including `/run`, so that DNS resolution through the `/etc/resolv.conf` symlink
keeps working — the kit binary's directory, and kit's config are mounted
read-only. Network is allowed, and the sandbox is `--die-with-parent`. The launch
always passes `--no-daemon` so kit cannot hand the session to a host daemon that
would run outside the sandbox.

## Consequences

- Committing, pushing, and installing dependencies from a sandboxed session
  fail by design; they are done from an unsandboxed `kwt shell` window in the
  same Worktree.
- Read-only git stays usable for inspection: the launch clears
  `GIT_OPTIONAL_LOCKS`, so git does not fail trying to refresh the index.
- Two kit sessions can never write the same dependency file, because every
  symlink target is read-only.
- Isolation is not silently bypassed: a sandboxed session never becomes a host
  daemon session, so it cannot outlive its terminal.
- `--allow-git-write` is a deliberate, explicit escape hatch rather than the
  default.

## Alternatives considered

- **No sandbox.** Simplest, and what kit does by itself, but it gives an agent
  full access to the developer's files, which is what this tool exists to
  prevent.
- **Allow a normal daemon session.** More convenient (detach and reattach), but
  the daemon runs kit on the host, outside the sandbox, defeating the policy.
  Rejected in favour of always launching `--no-daemon` inside bwrap.
- **Writable git by default.** Convenient for agent-driven commits, but lets an
  agent rewrite history unbidden. Rejected in favour of read-only git with an
  explicit `--allow-git-write` opt-in.
- **Network namespace isolation or an egress proxy.** Stronger containment, but
  model calls and MCP servers need the network, so network is shared for now.
  An egress proxy is a plausible next step.
