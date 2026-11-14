# One sandbox core with agent profiles

## Status

Accepted. Extends ADR-0001 (the sandbox policy) and ADR-0002 (ephemeral
sessions) from one agent to several. ADR-0004 records the command name and
interface these profiles are reached through.

## Context

The launcher was written for kit, but almost all of it is not about kit. The
sandbox policy — a default-deny `bwrap` invocation, one writable Target
directory, read-only git state, read-only `PATH` tool directories with symlink
targets resolved, the editor configuration mounts, `/run` for DNS — is the part
that is hard to get right and the part every agent needs unchanged. Only a small
payload differs per agent: the binary to launch, the configuration it may read,
the arguments it starts with, and whether it has a headless mode.

Adding pig by copying the launcher would duplicate the security-critical part,
leave the copy outside the test seam that drives the launcher executable, and
let the two sandboxes drift. The payload is where the real work is, and none of
it is saved by copying.

## Decision

Keep one script with one sandbox core and a profile per agent. The agent is an
explicit part of the command line, and a profile supplies four things, all keyed
on the selected profile:

- the agent binary, resolved once and followed through symlinks
  (`agent_binary`);
- the configuration mount (`bind_agent_config`);
- the launch arguments (`agent_launch_argv`);
- the headless environment, when one exists (`agent_headless_env`).

Everything else — resolution, the `PATH` tool mounts, the editor mounts, the
git binds, the plan, `--shell` — is shared and unchanged.

The kit profile preserves ADR-0001 and ADR-0002 exactly: `$XDG_CONFIG_HOME/kit`
and `$XDG_CONFIG_HOME/.kit` read-only, `--no-daemon --no-session`, and
`KIT_OPT_HEADLESS=true`.

The pig profile:

- **Configuration root** resolved the way Pig resolves it — `$PIG_HOME`, else
  `$XDG_CONFIG_HOME/pig`, else `~/.pig` — and mounted as a copy-on-write
  overlay: reads come from the host, writes go to an invisible tmpfs, and the
  host tree is never modified. A read-only bind does not work: Pig creates
  `trust.json.lock` in its agent directory even to *read* a project trust
  decision, so it fails with `EROFS`. Pig divergence D157 covers only the
  quieter SDK-staging and Piglet-verification writes, not trust resolution.
- **Agent directory** resolved the way Pig resolves it —
  `$PIG_CODING_AGENT_DIR`, or `~/.pi/agent` when `PIG_USE_PI_DIRS=1`. It can
  move independently of the root, so it is overlaid in its own right when the
  root does not already cover it.
- **Session store** replaced with an empty read-only directory
  (`--tmpfs` then `--remount-ro`). Pig keeps sessions inside its configuration,
  so unlike kit's separate `~/.kit` they would otherwise be mounted along with
  the config. Hiding them keeps every other session's transcript out of reach
  without making anything outside the Target writable. An explicit
  `PIG_CODING_AGENT_SESSION_DIR` / `PI_CODING_AGENT_SESSION_DIR` is hidden too.
- **Launch arguments** are `--no-session`. Pig has no daemon and no
  `--no-daemon`; its sessions are the only durable state to suppress.
- **Headless mode** is not set. Kit's headless extension answers a kit-specific
  problem (a worker blocking on `ask_question` or a sudo prompt from other
  extensions). Pig's default tool set has no such prompt, so a profile with no
  headless switch adds nothing rather than inventing one.

There is no agent-less profile. The profile is what decides the configuration
mounts and the launch payload, so the sandbox is always configured for an agent.

## Consequences

- One sandbox implementation and one test seam cover every agent. A policy
  change lands for kit and pig together; a new agent is a profile, not a fork.
- A sandboxed pig can create lock files, write settings, and refresh
  credentials, but every write lands in the overlay's tmpfs and is discarded
  when the sandbox exits. The host configuration is never modified. The cost is
  that a trust decision or a refreshed token does not persist across launches;
  that is the same ephemeral-session trade-off ADR-0002 makes for transcripts.
- The overlay is per launch, so a sandboxed pig sees the host configuration as
  it was when the launch started.
- The pig overlay requires a bubblewrap that supports `--overlay-src` and
  `--tmp-overlay`. An older bwrap fails at launch rather than silently
  weakening the profile.
- `PIG_HOME`, `PIG_CODING_AGENT_DIR`, `PIG_USE_PI_DIRS` and the session-dir
  variables are read from the environment, so the profile follows whichever
  configuration root the developer has selected.

## Alternatives considered

- **Mounting pig's configuration read-only.** The first attempt. Rejected:
  pig creates `trust.json.lock` even to read a trust decision, so the launch
  fails with `EROFS` before the agent starts.
- **A separate script per agent.** Rejected: it duplicates the sandbox core,
  which is the security boundary, and leaves the copy outside the tests that
  pin it, so the two policies drift silently.
- **Selecting the profile from the invocation name.** Used briefly
  (`kwt`/`pwt` as symlinks). Rejected in ADR-0004: the agent becomes invisible,
  and the neutral command name has no way to be invoked.
- **A shared library sourced by thin per-agent wrappers.** Equivalent in effect
  to the profile functions, with more files and a changed test seam. The profile
  keeps the whole policy in one file a reader can audit top to bottom.