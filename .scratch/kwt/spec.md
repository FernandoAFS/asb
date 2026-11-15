# Spec: `asb` — agent sandbox launcher

Feature: `asb`
Status: ready-for-agent
Date: 2026-11-09

## Problem Statement

An agent session runs an agent that can execute tools on the developer's
machine. Without isolation a mistake, or a prompt injection, can touch anything
the developer can. The developer wants to run an agent against one directory
while everything else on the machine stays out of reach.

## Solution

A single `asb` command that runs an agent inside a default-deny `bwrap` sandbox
rooted at a directory. Only that directory is persistently writable; `/tmp` is a
private tmpfs recreated for each execution. The Project's git state, the host's
tools, the agent's configuration, and the user's agent skills are mounted
read-only. The agent is chosen explicitly: `asb kit` or `asb pig`. `asb --shell`
runs a shell under the same policy for debugging.

## Command surface

```
asb [<options>] <agent> [<dir>] [-- <args>...]

agents:
  kit                   run kit
  pig                   run pig

options:
      --allow-git-write make git state writable inside the sandbox
      --dry-run         print the plan and perform no side effects
      --shell           run $SHELL in the agent's sandbox (debugging)
  -h, --help            show this help
```

- `<agent>` is required. There is no agent-less sandbox: the profile is what
  decides the configuration mounts and launch payload.
- `<dir>` defaults to the current directory when omitted. It must exist and is
  resolved to an absolute path and refused when it is `/`.
- `--allow-git-write` makes the Project's git state writable instead of
  read-only. The Target directory stays writable either way.
- `--dry-run` prints the plan and performs no side effects.
- `--shell` runs a shell instead of the agent, under the same profile.
- Everything after `--` is passed to the agent, or to the shell with `--shell`.
  This is the boundary between the launcher's own options and the agent's argv.

## Profiles

The sandbox policy below is shared; a profile supplies only the agent payload.

- **kit**: binary `kit`; configuration `$XDG_CONFIG_HOME/kit`,
  `$XDG_CONFIG_HOME/.kit`, and `~/.kit.yml`, all read-only; launch
  `--no-daemon --no-session`; sets `KIT_OPT_HEADLESS=true`.
- **pig**: binary `pig`; the configuration root resolved as Pig resolves it
  (`$PIG_HOME`, else `$XDG_CONFIG_HOME/pig`, else `~/.pig`) and the agent
  directory (`$PIG_CODING_AGENT_DIR`, or `~/.pi/agent` when `PIG_USE_PI_DIRS=1`),
  both mounted as copy-on-write overlays because Pig creates lock files
  (`trust.json.lock`) to read its configuration; the host session stores
  replaced with empty read-only directories; launch
  `--session-dir <Target>/.asb/pig/sessions`, a durable store the Target owns,
  so a run can be continued or resumed; no headless switch exists.

An unknown agent fails with a message naming the supported agents. A missing
agent fails with a message that one is required.

## Sandbox policy

A single `bwrap` invocation per launched process, default-deny:

- **Writable:** the Target directory persistently, and `/tmp` as a private
  tmpfs that exists only for the lifetime of that Sandbox. The host's `/tmp`
  (and anything in it, such as sockets) is not mounted.
- **Read-only:** the Project's git state when the Target directory is a git
  checkout root (the git dir and common dir when they differ), the system
  directories needed to run (`/usr`, `/bin`, `/lib`, `/lib64`), an
  allowlist of `/etc` entries (dynamic linking, account lookup, DNS, TLS trust,
  time/locale, shell startup, and small data files such as `mime.types`), every
  directory on `PATH` (so tools installed outside the system directories, such
  as `uvx`, are available; a tool that is itself a symlink has its real target
  mounted too), the directory containing the agent binary, kit's configuration
  (the pig profile overlays its configuration instead, see Profiles), and the
  user's agent skills (`~/.agents`, when present) so a session can read them but
  cannot rewrite its own instructions. `XDG_CONFIG_HOME` defaults to
  `~/.config`. `/etc` is never mounted wholesale: entries such as `shadow`,
  `ssh` host keys, and `machine-id` stay absent. The host's `/run` is not
  mounted either: it holds the session and system D-Bus sockets, the keyring
  and gpg-agent, and other user-service sockets. DNS does not need it, because
  bwrap resolves the `/etc/resolv.conf` symlink and binds the target's
  contents.
- **Configuration writes:** kit's configuration is read-only. Pig's
  configuration is a copy-on-write overlay: reads come from the host, writes go
  to an invisible tmpfs, and the host tree is never modified. Pig needs this
  because it creates `trust.json.lock` even to read a project trust decision,
  so a read-only bind fails with `EROFS`.
- **Editor setup:** when `$EDITOR` is vim or nvim, that editor's configuration
  and runtime directories are mounted, so a sandboxed session edits with the
  developer's setup and plugins. For `nvim` these are the `nvim` config and
  data directories under `$XDG_CONFIG_HOME` and `$XDG_DATA_HOME` (defaulting to
  `~/.config` and `~/.local/share`), read-only. nvim's state and cache
  directories are not mounted: the sandbox mounts private tmpfs directories at
  `/tmp/asb-state` and `/tmp/asb-cache` and sets `XDG_STATE_HOME` and
  `XDG_CACHE_HOME` to them. nvim starts with no undo history, shada, or swap
  and writes no compiled Lua bytecode or plugin cache back to the host. The
  cache must be writable because nvim compiles Lua bytecode there at startup;
  a read-only host cache fails with `EROFS`. The tmpfs mounts are private to the
  sandbox's mount namespace, so concurrent sessions do not share them. For
  `vim` (or `vi`) these are `$XDG_CONFIG_HOME/vim`, `~/.vim`, and `~/.vimrc`,
  all read-only. Only directories that exist are mounted.
- **Network:** allowed (no network namespace isolation).
- **Processes and IPC:** the sandbox has private PID, IPC, and UTS namespaces
  (`--unshare-pid`, `--unshare-ipc`, `--unshare-uts`). `/proc` lists only
  processes inside the Sandbox, not the host's process table; host System V IPC
  objects and POSIX message queues are not reachable; and the sandbox cannot
  rename the host. Nested user namespaces are disabled (`--unshare-user
  --disable-userns`), so a sandboxed process cannot create a new user namespace
  to remount the filesystem or reach namespace-based escape primitives. The
  sandbox is `--die-with-parent`.
- **tmux:** `TMUX` and `TMUX_TMPDIR` are removed from the environment, and the
  host's `/tmp` is not mounted, so a sandboxed process cannot attach to a host
  tmux server. A sandboxed tmux starts its own server inside the private
  `/tmp`.
- **D-Bus:** `/run` is not mounted, so no host bus socket is reachable, and
  `DBUS_SESSION_BUS_ADDRESS` and `XDG_RUNTIME_DIR` are removed from the
  environment, so a sandboxed process does not even try the host's session bus
  or runtime tree.
- `--allow-git-write` makes the git state writable instead of read-only.
- The sandboxed kit launch always passes `--no-daemon`, so kit never hands the
  session to the host daemon (which would run kit outside the sandbox).
- Kit's sandboxed launch passes `--no-session`, so its session stays in
  memory: no session store is mounted and no session record reaches disk.
- Pig's sandboxed launch passes `--session-dir <Target>/.asb/pig/sessions`, so
  its transcript persists in a store the Target owns. The host's session stores
  are still hidden, so no other project's session is reachable.
- The kit launch sets `KIT_OPT_HEADLESS=true`, so kit's headless extension
  starts active and the worker cannot block on an interactive question or a
  privilege prompt. `--shell` does not set it, and the pig profile has no
  headless switch.
- The sandboxed process runs with the Target directory as its working directory
  (`--chdir`).

## Shell mode

- `asb --shell <agent> [<dir>]` runs a shell (default `$SHELL`, falling back to
  `/bin/bash`) under the same sandbox policy and the same agent profile. It is a
  debugging mode, not a second kind of session.
- It mounts the agent's configuration (as a copy-on-write overlay for pig),
  because the profile is still the one being inspected, but it does not pass
  the agent's launch flags or headless environment.
- It does not resolve or mount the agent binary's directory: a debug shell does
  not need the agent, and `PATH` already covers the binary when it is installed.
  The agent therefore does not need to be on `PATH` for `--shell`.
- `--allow-git-write` applies to the shell too, so a developer can commit from a
  sandboxed shell when they explicitly allow it.
- Arguments after `--` are passed to the shell, so `asb --shell kit . -- -c
  'mount | grep kit'` works.

## Dry run

- `--dry-run` performs all resolution and prints the plan as deterministic,
  line-oriented records (`dir <absolute path>` and the full bwrap argv),
  performing no side effects. It exists both as a user feature and as the
  primary test seam.

## Invariants

- The Target directory is the only persistently writable source tree. `/tmp`
  is a private tmpfs whose contents are discarded when the sandbox exits. A pig
  configuration overlay is ephemeral: its writes go to an invisible tmpfs and
  are discarded when the sandbox exits.
- `/etc` is an allowlist of read-only entries; the rest of the host's system
  configuration is absent.
- The sandboxed process sees only its own PID, IPC, and UTS namespaces; host
  process metadata, IPC objects, and hostname changes are not reachable.
- A sandboxed process cannot create a new user namespace, so nested bwrap and
  rootless containers do not work inside the Sandbox.
- The tmux rendezvous environment is absent and the host's `/tmp` is not
  mounted, so no host tmux socket is reachable.
- The host's `/run` is not mounted and the D-Bus rendezvous environment is
  absent, so no host D-Bus or user-service socket is reachable.
- nvim's state and cache directories are not mounted. `XDG_STATE_HOME` and
  `XDG_CACHE_HOME` point at private tmpfs directories, so undo history, shada,
  swap, and cached bytecode from the host are not reachable and nothing nvim
  writes reaches the host.
- Git state is read-only unless `--allow-git-write`.
- The agent is always explicit; there is no agent-less sandbox.
- Sandboxed kit launches are always `--no-daemon`.
- Sandboxed kit launches are always `--no-session`; no session store is
  mounted or readable.
- Sandboxed pig launches use a durable store inside the Target
  (`<Target>/.asb/pig/sessions`) and never the host's store. Every host session
  store is replaced with an empty read-only directory, so no other project's
  session is reachable.
- `--shell` is a debugging mode of a named agent profile, not a separate policy.

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
- Setting an agent session display name.
- Live sessions after exiting a sandboxed agent instance.
- Session persistence for sandboxed kit launches; they remain ephemeral by
  design (`--no-session`), so there is nothing to resume. Pig launches persist
  in a store the Target owns.
- Remote/paired agent hosts.

## Testing Decisions

- Drive the `asb` executable as a black box and assert only on externally
  observable results — the printed plan, filesystem state, and the recorded
  argv of external tools. Do not source the script or assert on internal
  functions or variable names.
- One seam: the `asb` process boundary. Pure resolution is exercised via
  `--dry-run`; side-effectful behaviour is exercised by running the CLI with
  `bwrap` and the agent binary replaced by PATH shims that append their argv to a
  log file, while `git` runs for real inside throwaway temporary repositories.
- The sandbox command construction is covered through the bwrap argv printed by
  `--dry-run`.
- The tests clear the XDG and pig/Pi configuration variables before each case,
  so the ambient environment never changes the resolved paths.

## Further Notes

- The `asb` command was originally `kwt` (kit-only) and then briefly `kwt`/`pwt`
  selected by symlink. ADR-0004 records the move to an explicit agent argument.
  The feature directory keeps its historical `.scratch/kwt/` name.
- Pig creates `trust.json.lock` in its agent directory even to *read* a project
  trust decision, so a read-only bind failed with `EROFS`. The pig profile
  therefore overlays its configuration; writes never reach the host. The
  overlay uses `--overlay-src` and `--tmp-overlay`, so it needs a bubblewrap
  that supports them.
- `kit`'s installed binary is newer than the locally cloned source: the binary
  supports `--no-daemon` and `kit session {ls,attach,kill,rename}`, while the
  clone under the developer's foss directory does not. The implementation should
  target the **installed binary's** interface.
- `/etc` cannot be removed entirely without breaking basic runtime needs: the
  dynamic linker, account lookup, DNS resolution, and TLS trust all read from
  it. The sandbox therefore mounts an explicit allowlist and leaves everything
  else absent.
- `--unshare-pid` hides the host process table from the sandbox. It does not
  hide the sandbox from the host: a same-user process outside the sandbox can
  still inspect the sandboxed processes. Hiding process metadata from the host
  would need a different isolation model and is not a goal of `asb`.
- The bwrap policy is deliberately conservative; the proxy and a per-repo config
  file are the natural next features once this lands.