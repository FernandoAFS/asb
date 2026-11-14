# nvim state is a private tmpfs, not a host mount

## Status

Accepted. Amends ADR-0001, which made nvim's state directory a writable host
bind and otherwise mounted the editor's XDG directories.

## Context

nvim keeps undo history, shada, and swap files under `XDG_STATE_HOME`, normally
`~/.local/state/nvim`. Undo files are named after the file path they belong to
(`%home%fafs%...`) and contain enough of the previous buffer to reconstruct
deleted or changed text. Shada records command history and marks. A sandboxed
agent that can read that directory can therefore recover content from files it
cannot otherwise reach — including files outside the Target directory.

ADR-0001 mounted `~/.local/state/nvim` writable because nvim writes its log,
shada, and undo files at startup and a read-only state directory stops nvim from
starting. A read-only bind has the same leak, and a copy-on-write overlay does
too: the overlay's lower layer is the host state directory, so the undo history
is still readable inside the sandbox.

## Decision

Do not mount the host's nvim state directory at all.

- Mount nvim's config, data, and cache directories read-only, as before, because
  nvim needs the developer's configuration and installed plugins.
- Mount a private tmpfs at `/tmp/asb-state` and set `XDG_STATE_HOME` to it.
  nvim creates `$XDG_STATE_HOME/nvim` afresh, so undo, shada, and swap start
  empty and every write stays in the sandbox.

## Consequences

- No undo history, shada, or swap from a previous session is reachable. The
  sandboxed session starts with a clean history.
- Nvim still starts and writes its state, because it has a writable state
  directory; nothing reaches the host.
- Undo history and command history do not persist across sandboxed sessions.
  That matches the ephemeral-session policy of ADR-0002.
- The tmpfs is private to each sandbox's mount namespace, so concurrent
  sessions do not share it even though the path is fixed.
- Other tools inherit `XDG_STATE_HOME=/tmp/asb-state` for the same reason: their
  state is ephemeral and not the host's.

## Alternatives considered

- **Keep the writable host bind.** Rejected: the agent can read the host's undo
  history.
- **Mount the host state read-only.** Rejected: the same read leak, and nvim
  would fail to start.
- **Mount a copy-on-write overlay over the host state.** Rejected: the overlay's
  lower layer is still the host state, so the undo history remains readable.
- **Point only `undodir` at a tmp path.** Rejected: shada and swap would still
  come from the host. Redirecting `XDG_STATE_HOME` covers all of them.
- **Point every XDG variable at tmp.** Rejected: nvim needs the host config and
  installed plugins from `XDG_CONFIG_HOME` and `XDG_DATA_HOME`. Those stay
  read-only host mounts.