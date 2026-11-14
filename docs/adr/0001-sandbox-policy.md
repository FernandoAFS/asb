# Sandbox every kit launch with bwrap: one writable directory, shared state read-only, `--no-daemon`

## Status

Accepted. Amended by ADR-0002 (kit's session store is no longer mounted, and
sandboxed kit sessions are ephemeral), ADR-0005 (nvim's state and cache
directories are private tmpfs, not the host's), and ADR-0006 (private `/tmp`, an
`/etc` allowlist, no `/run`, a PID namespace, and tmux and D-Bus variables
dropped).

## Context

A kit session runs an agent that can execute tools on the developer's machine.
Without isolation a mistake, or a prompt injection, can write anywhere the
developer can. `kwt` runs kit in one directory, so the launch should honour that
boundary.

## Decision

Every kit launch runs inside a single `bwrap` invocation that is default-deny on
the filesystem. Only the Target directory, `/tmp`, and kit's session store are
writable. Everything shared is read-only: the Project's git state, the system
directories needed to run (excluding `/run`, which ADR-0006 removes), the kit
binary's directory, and kit's
config are mounted read-only. Every directory on `PATH` is mounted read-only as
well, so a sandboxed session can run the same tools the host can even when they
are installed outside the system directories (`uvx`, cargo, pnpm and the like); a
tool that is a symlink into another directory has its real target mounted too,
so the link does not dangle. Because kit keeps provider credentials and MCP
tokens in `$XDG_CONFIG_HOME/.kit`, that directory is mounted read-only too; a
sandboxed session can authenticate but cannot write secrets. `XDG_CONFIG_HOME`
defaults to `~/.config`, so the mount follows the environment kit itself reads.
The user's agent skills in `~/.agents` are mounted read-only when present, so
the session can load them but cannot rewrite its own instructions. When the
developer's `$EDITOR` is vim or nvim, that editor's configuration and runtime
directories are also mounted — the `nvim` config and data directories under the
XDG base directories for nvim, and `$XDG_CONFIG_HOME/vim`, `~/.vim`, and
`~/.vimrc` for vim — so a session edits with the developer's setup and plugins
but cannot rewrite them. nvim's state and cache directories are not mounted:
the sandbox points `XDG_STATE_HOME` and `XDG_CACHE_HOME` at private tmpfs
directories, so undo history, shada, swap, and compiled bytecode stay out of
reach and nvim still starts.
Network is allowed, and the sandbox is `--die-with-parent`. The launch always
passes `--no-daemon` so kit cannot hand the session to a host daemon that would
run outside the sandbox.

Git is read-only by default; `--allow-git-write` makes the Project's git
directory writable instead. The Target directory stays writable regardless.

## Consequences

- Committing, pushing, and installing dependencies from a sandboxed kit session
  fail by design; they are done outside the sandbox.
- Read-only git stays usable for inspection: the launch clears
  `GIT_OPTIONAL_LOCKS`, so git does not fail trying to refresh the index.
- Tools are available but frozen: anything on `PATH` can be executed, none of it
  can be overwritten, so a sandboxed session cannot upgrade or replace a host
  tool.
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
