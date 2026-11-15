# Pig sessions persist in a store the Target owns

## Status

Accepted. Amends the pig profile of ADR-0003, which extended ADR-0002's
ephemeral-session policy from kit to pig.

## Context

ADR-0002 made sandboxed kit sessions ephemeral because kit's session store
lives at a fixed `$HOME/.kit` with no flag or environment variable to move it.
Mounting it would have made that host path writable, exposing every project's
transcript read-write. Ephemeral sessions were the only isolation kit allowed.

Pig is not kit. It stores sessions inside its configuration root by default,
but it also accepts an explicit store location: `--session-dir`, the
`PIG_CODING_AGENT_SESSION_DIR` environment variable, or the `sessionDir`
setting, in that order. That is the missing switch ADR-0002 wished kit had.
It lets the store live anywhere, including a directory the Target owns, so the
isolation argument no longer requires the session to be ephemeral.

Pig also resolves `--continue` by filtering on the session header's working
directory whenever the store is a custom, non-cwd-encoded directory, so a
store that holds several projects' sessions still resumes only the current
directory's conversation. A store that holds one Target's sessions is
therefore both safe and simple.

The cost of ephemerality is real: when a harness is interrupted — a crash, a
kill, a lost terminal — an in-memory session leaves no record. There is
nothing to inspect afterward and nothing to resume.

## Decision

Give the pig profile a durable session store inside the Target directory.

- Resolve the store as `<Target>/.asb/pig/sessions` and pass it to pig with
  `--session-dir`. The flag outranks the environment and the `sessionDir`
  setting, so a host store the developer configured is never consulted.
- Launch pig without `--no-session`. A run starts a new session and saves it;
  a later run reopens one by passing `--continue`, `--resume`, or `--session`
  through the launcher's `--` boundary.
- Keep hiding every host session store: the default under the agent directory
  and any store an environment variable names are still replaced with an empty
  read-only directory. A store the Target owns is exempt, because it is the
  launch's own store and is bound writable with the Target.

Kit is unchanged: `--no-daemon --no-session`.

## Consequences

- An interrupted pig run leaves a transcript under `<Target>/.asb/pig/sessions`
  that can be read, exported, or resumed.
- Isolation holds: a sandboxed pig can write only this Target's store, and can
  read no other project's sessions, because the host stores remain hidden.
- The Target is already the one writable source tree, so no new mount or
  writable host path is introduced.
- `.asb/` now sits inside the project. A repository that does not want session
  transcripts committed should ignore `<Target>/.asb/`.
- Sessions persist across launches while pig's configuration does not: the
  configuration root is still a copy-on-write overlay, so trust decisions and
  refreshed credentials are discarded. The store is the deliberate exception,
  because it is passed as an explicit path outside that overlay.
- `--continue` resumes the most recent session for the Target's working
  directory. With no prior session it starts a new one, so the default run is
  still a fresh session.

## Alternatives considered

- **Mount the host store `~/.pig/agent/sessions/<encoded-cwd>` writable.**
  Rejected: it is a host path, and the session would write into the same
  directory as the developer's own sessions and could read them.
- **Point the store at a shared host directory with `--session-dir`.** Rejected:
  `--continue` would still filter correctly by working directory, but the
  sandbox could read every other project's transcript in that directory.
- **Keep sessions ephemeral.** Rejected: pig offers an explicit store location,
  so the isolation that forced ephemerality for kit does not apply, and the
  operator loses the record exactly when a run goes wrong.
- **Persist the whole pig configuration.** Rejected: pig creates lock files to
  read its configuration, so it needs a writable overlay; making that overlay
  durable would let a sandboxed session rewrite settings and trust decisions.
  Only the transcript is meant to survive.
