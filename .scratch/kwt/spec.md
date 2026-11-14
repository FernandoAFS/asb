# Spec: `kwt` — kit sandbox launcher

Feature: `kwt`
Status: ready-for-agent
Date: 2026-11-09

## Problem Statement

A kit session runs an agent that can execute tools on the developer's machine.
Without isolation a mistake, or a prompt injection, can touch anything the
developer can. The developer wants to run kit against one directory while
everything else on the machine stays out of reach.

## Solution

A single `kwt` command that runs kit inside a default-deny `bwrap` sandbox
rooted at a directory. Only that directory and `/tmp` are writable. The
Project's git state, the host's tools, kit's configuration, and the user's agent
skills are mounted read-only. A companion `kwt shell` runs a sandboxed shell
under the same policy.

## Command surface

```
kwt [<dir>] [--allow-git-write] [--dry-run] [-- <prompt>...]
kwt shell [<dir>] [--allow-git-write] [--dry-run]
```

- `<dir>` defaults to the current directory when omitted. It must exist and is
  resolved to an absolute path and refused when it is `/`.
- `--allow-git-write` makes the Project's git state writable instead of
  read-only. The Target directory stays writable either way.
- `--dry-run` prints the plan and performs no side effects.
- A trailing `-- <prompt>` is passed through to kit.

## Sandbox policy

A single `bwrap` invocation per launched process, default-deny:

- **Writable:** the Target directory and `/tmp`.
- **Read-only:** the Project's git state when the Target directory is a git
  checkout root (the git dir and common dir when they differ), the system
  directories needed to run (`/usr`, `/bin`, `/lib`,
  `/lib64`, `/etc`, `/run`), every directory on `PATH` (so tools installed
  outside the system directories, such as `uvx`, are available; a tool that is
  itself a symlink has its real target mounted too), the directory containing
  the kit binary, kit's config (`$XDG_CONFIG_HOME/kit`, and
  `$XDG_CONFIG_HOME/.kit` — the provider credentials and MCP tokens),
  `~/.kit.yml`, and the user's agent skills (`~/.agents`, when present) so a
  session can read them but cannot rewrite its own instructions.
  `XDG_CONFIG_HOME` defaults to `~/.config`.
- **Editor setup:** when `$EDITOR` is vim or nvim, that editor's configuration
  and runtime directories are mounted, so a sandboxed session edits with the
  developer's setup and plugins. They are read-only except nvim's state
  directory. For `nvim` these are the `nvim` directories under the XDG config,
  data, state, and cache bases (`$XDG_CONFIG_HOME`, `$XDG_DATA_HOME`,
  `$XDG_STATE_HOME`, `$XDG_CACHE_HOME`, each defaulting to its usual `~/.config`,
  `~/.local/share`, `~/.local/state`, `~/.cache`); config, data, and cache are
  read-only, and state is **writable** because nvim writes its log, shada, and
  undo files there at startup. For `vim` (or `vi`) these are
  `$XDG_CONFIG_HOME/vim`, `~/.vim`, and `~/.vimrc`, all read-only. Only
  directories that exist are mounted.
- **Network:** allowed (no network namespace isolation).
- The sandbox is `--die-with-parent`.
- `--allow-git-write` makes the git state writable instead of read-only.
- The sandboxed kit launch always passes `--no-daemon`, so kit never hands the
  session to the host daemon (which would run kit outside the sandbox).
- The sandboxed kit launch always passes `--no-session`, so the session stays in
  memory: no session store is mounted and no session record reaches disk.
- The kit launch sets `KIT_OPT_HEADLESS=true`, so kit's headless extension
  starts active and the worker cannot block on an interactive question or a
  privilege prompt. `kwt shell` does not set it.
- The sandboxed process runs with the Target directory as its working directory
  (`--chdir`).

## Shell subcommand

- `kwt shell <dir>` runs a shell (default `$SHELL`, falling back to `/bin/bash`)
  under the same sandbox policy. It is not a kit session and does not set
  headless mode.
- `--allow-git-write` applies to the shell too, so a developer can commit from a
  sandboxed shell when they explicitly allow it.

## Dry run

- `--dry-run` performs all resolution and prints the plan as deterministic,
  line-oriented records (`dir <absolute path>` and the full bwrap argv),
  performing no side effects. It exists both as a user feature and as the
  primary test seam.

## Invariants

- The Target directory is the only writable source tree.
- Git state is read-only unless `--allow-git-write`.
- Sandboxed kit launches are always `--no-daemon`.
- Sandboxed kit launches are always `--no-session`; no session store is mounted.

## Out of Scope

- Git worktree creation or management.
- tmux orchestration.
- Secret management of any kind. (Mounting the existing credentials store
  read-only so a sandboxed session can authenticate is in scope; creating,
  rotating, or storing secrets is not.)
- A per-repository configuration file (mounts, hooks, extra paths).
- Network proxying or egress filtering.
- Dependency installation inside the sandbox (dependencies are read-only there;
  installs happen outside the sandbox).
- Setting a kit session display name (kit can only rename live daemon sessions,
  and sandboxed launches are `--no-daemon` by design).
- Live sessions after exiting a sandboxed kit instance.
- Session persistence for sandboxed launches; they are ephemeral by design
  (`--no-session`), so there is nothing to resume.
- Remote/paired kit hosts.

## Testing Decisions

- Drive the `kwt` executable as a black box and assert only on externally
  observable results — the printed plan, filesystem state, and the recorded
  argv of external tools. Do not source the script or assert on internal
  functions or variable names.
- One seam: the `kwt` process boundary. Pure resolution is exercised via
  `--dry-run`; side-effectful behaviour is exercised by running the CLI with
  `bwrap` and `kit` replaced by PATH shims that append their argv to a log file,
  while `git` runs for real inside throwaway temporary repositories.
- The sandbox command construction is covered through the bwrap argv printed by
  `--dry-run`.

## Further Notes

- `kit`'s installed binary is newer than the locally cloned source: the binary
  supports `--no-daemon` and `kit session {ls,attach,kill,rename}`, while the
  clone under the developer's foss directory does not. The implementation should
  target the **installed binary's** interface.
- The bwrap policy is deliberately conservative; the proxy and a per-repo config
  file are the natural next features once this lands.
