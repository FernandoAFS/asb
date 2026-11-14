# Sandboxed kit sessions are ephemeral: `--no-session`, and no session store mounted

## Status

Accepted. Amends ADR-0001, which made kit's session store a writable mount.

## Context

ADR-0001 made kit's session store at `~/.kit` the one writable path outside the
Target directory, so a sandboxed session could persist, and `kwt` bound it with
`--bind "$HOME/.kit" "$HOME/.kit"` on every launch.

That mount is the furthest reach any part of the policy has outside the Target,
and it points at the host's live store rather than anything the Target owns:

- It is where kit writes the whole conversation — every prompt, every tool call,
  and the arguments they carried. A session that can write there can therefore
  append to a record the developer may later treat as trustworthy.
- Because it is the host store, a sandboxed session writes into the same
  directory as the developer's non-sandboxed sessions, and reads every other
  session's transcript — including sessions for other Projects.

Kit's store location is not configurable. `DefaultSessionDir`
(`internal/session/tree_manager.go:1638`) joins `os.UserHomeDir()` with
`.kit/sessions/<encoded-cwd>`; there is no flag and no environment variable, and
kit's own tests relocate the store by setting `HOME`. Pointing a store at a
directory inside the Target would therefore have meant remapping `$HOME/.kit`
with `--bind`, making the Target the source of a path whose meaning is otherwise
fixed by kit.

## Decision

Launch kit with `--no-session` and mount no session store. `$HOME/.kit` is
neither bound nor pre-created, and `--no-session` is passed alongside
`--no-daemon` on every sandboxed kit launch.

`--no-session` routes session setup to an in-memory tree
(`pkg/kit/kit.go:1771`), which never calls `CreateTreeSession` — the sole caller
of the directory-creating `createSessionDirs`
(`internal/session/tree_manager.go:112`). Kit's daemon keeps its own state under
`$XDG_RUNTIME_DIR/kit` and `$XDG_CACHE_HOME/kit/daemon`, not under `~/.kit`, and
`--no-daemon` rules the daemon out anyway, so nothing else writes there either.
The store is the only thing `~/.kit` holds for a normal launch, which is why not
mounting it is safe.

## Consequences

- Nothing about a sandboxed session reaches disk, and no other session's
  transcript is reachable from inside the Sandbox.
- A sandboxed session cannot be continued or resumed: `--continue`,
  `--resume`, the session picker, and `kit attach` have nothing to open. A
  session already could not outlive its terminal, because ADR-0001 launches
  `--no-daemon`.
- There is no transcript to inspect after a run. This is the real cost: the
  operator loses the after-the-fact record of what an agent did, which is
  exactly the evidence wanted when a run was prompt-injected or went wrong. A
  record must now be reintroduced deliberately rather than inherited from the
  host store.
- Prompt templates under `~/.kit/prompts` are no longer visible. Templates in
  `$XDG_CONFIG_HOME/kit` stay readable, since that directory is still mounted
  read-only.
- A `PATH` directory under `~/.kit` stays excluded from the read-only tool
  mounts, so the session store cannot re-enter the Sandbox through the tool
  mounts.

## Alternatives considered

- **Mount a store inside the Target over `$HOME/.kit`.** Keeps persistence and
  puts the transcript inside the Target. Rejected for now: kit exposes no switch
  for where it stores sessions, so the only mechanism is remapping a
  `$HOME`-relative path, and the resulting directory doubles as kit's
  project-local `.kit` when the Target is a checkout root.
- **Leave the shared host store writable (status quo).** Rejected: it is the
  only writable path outside the Target, and it exposes every other Project's
  transcripts read-write.
- **Point `HOME` at the Target.** Also relocates config, credentials, and skill
  discovery, each of which would then need re-pinning. The blast radius is far
  larger than the one path that needs to move.
- **A sessions-directory option in kit.** The durable fix: kit gains a flag or
  environment variable for the store root, and `kwt` points it inside the
  Target. Out of `kwt`'s control; to be pursued upstream. Ephemeral sessions
  hold the policy until then.
