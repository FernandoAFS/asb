# `asb`: one explicit command, no symlink dispatch, `--shell` as an option

## Status

Accepted. Supersedes the `kwt`/`pwt` invocation-name dispatch described in
ADR-0003 and the `shell` subcommand described in the original `kwt` spec.

## Context

The launcher began as `kwt` — kit only, with `kwt shell` as a subcommand. When
the pig profile arrived, the first implementation selected the profile from the
name the script was invoked by: `kwt` launched kit and `pwt`, a symlink, launched
pig.

That worked, but the name was doing two jobs at once. The agent became
invisible: `--help` could not say which agents existed, `asb`-style neutral
names had no way to be invoked at all, the install grew one symlink per agent,
and testing a profile meant invoking the script through a specially named path.
It also baked what is really a shell alias (`alias pwt='asb pig'`) into the
installed artifact.

The `shell` subcommand had a related problem: it competed with the agent for the
first positional and reserved a word that an agent could plausibly be called.
It was also presented as a peer of normal use, although it exists only to
inspect the sandbox.

## Decision

Rename the launcher to `asb` (agent sandbox) and make the agent an explicit
argument:

```
asb [<options>] <agent> [<dir>] [-- <args>...]
```

- The agent is a required positional, `kit` or `pig`. There is no agent-less
  sandbox: the profile decides the configuration mounts and launch payload.
- No symlinks and no invocation-name dispatch. If a developer wants muscle
  memory, a shell alias (`alias pig-sb='asb pig'`) is the right layer.
- `--shell` is an option, not a subcommand. It runs `$SHELL` in the same
  agent's sandbox, for debugging. The agent stays required; the shell keeps the
  profile's configuration mounts but does not pass the agent's launch flags or
  headless environment, and it does not resolve the agent binary, so the agent
  need not be on `PATH`.
- `--` separates the launcher's options from the agent's argv; everything after
  it is forwarded verbatim to the agent, or to the shell in `--shell` mode.
- A missing agent and an unknown agent are both errors.

## Consequences

- Breaking change: `kwt` and `pwt` are gone. Existing callers become `asb kit
  ...` and `asb pig ...`; per-agent aliases are the user's choice.
- The single command is directly runnable and testable, and `--help` can list
  the supported agents.
- Adding an agent is a profile plus a case in `select_agent`; no install
  artifact is added.
- The tests drive one executable with an explicit agent argument, which removes
  the invocation-name indirection from the seam.
- `--shell` no longer needs the agent binary on `PATH`, because shell mode does
  not bind the agent binary's directory. `PATH` still covers it when installed.
- The issue-tracker feature directory keeps its historical `.scratch/kwt/` name;
  renaming it would churn every issue path for no behavioural gain.

## Alternatives considered

- **Keep `kwt`/`pwt` symlinks.** Rejected: it hides the agent, leaves the
  neutral name uninhabitable, and adds an install artifact per agent.
- **Keep `shell` as a subcommand.** Rejected: it competes with `<agent>` for the
  first positional, reserves a word, and presents a debugging aid as normal use.
- **`--agent kit` instead of a positional.** Workable, but more verbose for a
  choice every invocation must make, and it reads as an optional modifier even
  though it is required.
- **Keep `kwt` as a compatibility alias.** Rejected: the project is young and
  has no installed callers worth carrying; a shell alias covers the same need
  without code.