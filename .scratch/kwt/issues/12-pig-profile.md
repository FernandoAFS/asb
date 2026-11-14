# 12: pig profile (`asb pig`)

**What to build:** A pig profile for the sandbox launcher. `asb pig` runs pig under the same sandbox policy as `asb kit`; the agent is an explicit argument and there is one sandbox core. Kit keeps its behavior exactly.

**Blocked by:** 05 — Run the kit launch inside the bwrap sandbox

**Status:** ready-for-agent

- [ ] The agent payload (binary, configuration, launch arguments, headless environment) is selected by a profile from the explicit `<agent>` argument, so `asb kit` and `asb pig` share one sandbox core.
- [ ] `asb pig` mounts pig's configuration read-only, resolving the root as pig does: `$PIG_HOME`, else `$XDG_CONFIG_HOME/pig`, else `~/.pig`.
- [ ] The pig agent directory is mounted read-only and honored when relocated (`PIG_CODING_AGENT_DIR`, or `~/.pi/agent` with `PIG_USE_PI_DIRS=1`).
- [ ] The pig session store is replaced with an empty read-only directory, including any store named by a session-dir environment variable.
- [ ] The pig launch is ephemeral (`--no-session`) and passes no kit flags (`--no-daemon`, `KIT_OPT_HEADLESS`).
- [ ] `asb --shell pig` runs a shell under the same policy, with the agent required, and is not a pig session.
- [ ] An unknown or missing agent fails with a clear error.
- [ ] The tests do not inherit the developer's XDG or pig/Pi configuration variables.

## Comments

Implemented; covered by `test/11_pig_test.sh` and `test/integration_pig_test.sh`.
The profile decision is recorded in `docs/adr/0003-agent-profiles.md`; the
command name and `--shell` interface in `docs/adr/0004-rename-to-asb.md`.