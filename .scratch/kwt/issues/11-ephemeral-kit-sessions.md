# 11: Sandboxed kit sessions are ephemeral

**What to build:** Every sandboxed kit launch runs with `--no-session`, and `kwt` mounts no session store at all. `$HOME/.kit` is no longer bound, and no longer pre-created. A sandboxed session keeps its conversation in memory, so nothing is written to a session directory and no other session's transcript is reachable from inside the Sandbox. This narrows ADR-0001 (see ADR-0002): the writable set becomes the Target directory and `/tmp`, with nothing else.

**Blocked by:** 05 — Run the kit launch inside the bwrap sandbox

**Status:** ready-for-agent

- [ ] The sandboxed kit launch passes `--no-session` alongside `--no-daemon`.
- [ ] No session store is bound: the Plan contains no `--bind` or `--ro-bind` for `$HOME/.kit`.
- [ ] `$HOME/.kit` is not created before the launch.
- [ ] A `PATH` directory under `$HOME/.kit` is still excluded from the read-only tool mounts.
- [ ] `kwt shell` is unaffected: it runs no kit, so it gains no `--no-session`.
- [ ] `CONTEXT.md`, `spec.md`, and ADR-0001 reflect the narrower policy.

## Why

`--no-session` is not just a smaller mount; it is the difference between kit
writing a transcript and not. Reading kit v0.139.0: `InitTreeSession` returns
`session.InMemoryTreeSession` when `NoSession` is set (`pkg/kit/kit.go:1771`),
before any `CreateTreeSession`; and `createSessionDirs` — the only thing that
mkdirs the store — has exactly one caller, `CreateTreeSession`
(`internal/session/tree_manager.go:112`). Kit's daemon state lives under
`$XDG_RUNTIME_DIR/kit` and `$XDG_CACHE_HOME/kit/daemon`, not under `~/.kit`, and
`--no-daemon` rules the daemon out regardless.

Kit offers no way to point the store elsewhere: `DefaultSessionDir`
(`internal/session/tree_manager.go:1638`) always joins `os.UserHomeDir()` with
`.kit/sessions/<encoded-cwd>` — no flag, no environment variable. So a
Target-local store can only be faked by remapping `$HOME/.kit`; that is recorded
as an alternative in ADR-0002 and left to an upstream kit change.

## Verification

A fresh `HOME` with credentials reachable, and the provider pointed at a dead
endpoint so the run fails at the model call — which is *after* session setup:

- a normal launch created `$HOME/.kit/sessions/home--…--kit-sandbox/*.jsonl`
  plus its `.lock` file;
- `--no-session` created nothing under `$HOME` at all.

## Comments

Implemented: `--no-session` added to the kit argv in `cmd_run`, the
`--bind "$HOME/.kit"` removed from `build_sandbox`, and both `mkdir -p
"$HOME/.kit"` calls dropped.

Covered by `t_sessions_are_ephemeral` in `test/05_sandbox_test.sh` (argv and
absence from the Plan) and by the `sessionstore=absent` probe in
`test/integration_bwrap_test.sh`, which proves it in a real `bwrap` run. The
kit-argv assertions in `test/01_resolution_test.sh` and
`test/integration_bwrap_test.sh` were updated for the new flag.
