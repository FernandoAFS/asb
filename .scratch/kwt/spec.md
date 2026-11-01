# Spec: `kwt` — kit worktree wrapper

Feature: `kwt`
Status: ready-for-agent
Date: 2026-11-01

## Problem Statement

When a developer wants to start a kit session on a focused piece of work, they
perform the same manual sequence every time: open tmux, open a window, rename
it, create a git worktree, symlink the dependency directory and env file for
the language in use, launch kit, and name the session. The sequence is slow,
error-prone, and easy to do inconsistently (wrong window name, forgotten
symlink, a worktree left behind). Separately, when kit runs it has free rein
over the whole machine, so an agent's mistake — or a prompt-injection — can
touch anything the developer can. The developer wants a single command that
performs the setup the same way every time and runs kit inside a sandbox that
can only write to the one Worktree it was started for.

## Solution

A single `kwt` command that, from anywhere inside a git Project, creates or
reuses a Worktree for a branch, links the shared dependency/env paths into it,
opens (or selects) a tmux window for it, and launches kit inside a
default-deny `bwrap` sandbox where only the Worktree is writable and all shared
state — git and the linked dependency paths — is read-only. A companion `kwt
shell` opens an unsandboxed host shell in the same Worktree for operations that
legitimately need to write (dependency installs, commits, pushes). `kwt ls` and
`kwt rm` manage and reap Worktrees.

## User Stories

1. As a developer, I want to create a Worktree for a branch with one command, so that I stop repeating the tmux/worktree/symlink steps by hand.
2. As a developer, I want the Worktree created at a predictable path, so that I can find it without guessing.
3. As a developer, I want the Worktree directory excluded from git's view, so that my Project's status stays clean without editing tracked files.
4. As a developer, I want an existing branch to be reused rather than recreated, so that I can run kit against a branch that already exists.
5. As a developer, I want to base a new branch on a chosen base branch, so that I can start from the commit I intend.
6. As a developer, I want a new branch to default to the current HEAD, so that the common case needs no extra flags.
7. As a developer, I want `kwt <branch>` to be idempotent, so that re-running it selects the existing window instead of starting a second kit session.
8. As a developer, I want the Project's Python dependencies available in the Worktree without reinstalling, so that kit starts fast.
9. As a developer, I want the Project's `.env` file available in the Worktree, so that the application runs from the Worktree.
10. As a developer, I want the Project's Node dependencies available in the Worktree, so that JS/TS projects work without a fresh install.
11. As a developer, I want to pass an initial prompt through to kit, so that a session starts already pointed at my task.
12. As a developer, I want kit to run sandboxed with only the Worktree writable, so that a mistake cannot damage the rest of my machine.
13. As a developer, I want the Worktree's git state read-only by default, so that kit cannot rewrite history unbidden.
14. As a developer, I want to opt into git writes for a Worktree, so that kit can commit when I explicitly allow it.
15. As a developer, I want shared dependency paths read-only inside the sandbox, so that two kit sessions can never write the same file.
16. As a developer, I want network access inside the sandbox, so that model API calls and MCP servers work.
17. As a developer, I want the sandboxed launch to never hand the session to the host daemon, so that isolation is not silently bypassed.
18. As a developer running outside tmux, I want `kwt` to attach me to the Project's tmux session, so that I land directly in the new window.
19. As a developer already inside tmux, I want to be switched to the correct window, so that I do not hunt for it across sessions.
20. As a developer, I want a detached mode that creates the Worktree and window without switching to them, so that I can queue several Worktrees at once.
21. As a developer, I want a plain host shell window in the Worktree, so that I can install dependencies, commit, and push (operations the sandbox denies).
22. As a developer, I want the shell window to be sandboxed on request, so that I can reproduce and debug sandbox behaviour.
23. As a developer, I want the shell subcommand to create the Worktree when explicitly asked, so that I do not have to pre-create it.
24. As a developer, I want the kit window to close when kit exits, so that I do not accumulate dead windows.
25. As a developer, I want to list the Project's Worktrees and see which ones have kit running, so that I can find my way back.
26. As a developer, I want to remove a Worktree with one command, so that finished work does not pile up.
27. As a developer, I want teardown to refuse while a kit session is active unless forced, so that I do not kill in-flight work by accident.
28. As a developer, I want teardown to never modify the Main checkout, so that cleanup is safe.
29. As a developer, I want a dry-run that prints exactly what would happen, so that I can verify before committing to side effects.
30. As an implementing agent, I want the dry-run plan to be deterministic and line-oriented, so that tests can assert on it without parsing prose.
31. As a developer, I want at most one kit session per Worktree, so that a Worktree's files always have a single writer.

## Implementation Decisions

### Form and delivery

- Implemented as a **single bash script** named `kwt`. No build step, no runtime
  dependency beyond `bash`, `git`, `tmux`, `bwrap`, and `kit`, all of which are
  present. Distributed by copying onto `PATH` (the user copies it into `~/bin`).
- No configuration file and no secret management in this iteration.

### Command surface

```
kwt <branch> [--base <branch>] [-d|--detached] [--allow-git-write] [--dry-run] [-- <prompt>...]
kwt shell <branch> [--create] [--sandboxed] [--dry-run]
kwt ls
kwt rm [<branch>] [--force]
```

- Bare `kwt` is not a command. The branch subcommand is the default action.
- `--base` defaults to the current HEAD; `--base` keeps short form `-b`; detached
  mode uses `-d`/`--detached`.

### Resolution

- **Project** is resolved from any subdirectory by walking up; when invoked from
  inside a Worktree, resolution yields the Main checkout (via the git common
  dir), not the Worktree.
- **Slug** is the branch name with `/` replaced by `-`.
- **Worktree path** is `<main>/.worktrees/<slug>`.
- `.worktrees` is appended to `.git/info/exclude` (never to the tracked
  `.gitignore`).
- Branch is create-or-reuse: an existing branch is checked out into the
  Worktree; a missing branch is created from `--base`.
- If the Worktree already exists, it is reused, never rebuilt.

### Symlinks

On Worktree creation, symlink from the Main checkout into the Worktree, if
present in the Main checkout and not already present in the Worktree (never
overwrite):

- `.venv` — when the Main checkout looks like Python (`pyproject.toml`,
  `requirements.txt`, `uv.lock`, `poetry.lock`, or `setup.py` present).
- `node_modules` — when the Main checkout looks like Node (`package.json` present).
- `.env` — always, when present.

Dependency changes are made from the `shell` window, which is unsandboxed.

### tmux orchestration

- **tmux session** name is the basename of the Main checkout (one per Project).
- **tmux window** names are `<slug>` (kit) and `<slug>~` (shell) (one per Worktree).
- The kit window runs the sandboxed kit launch and **closes when kit exits**.
- Navigation:
  - outside tmux → create the session if needed and attach (unless detached);
  - inside a different session → switch client to the Project session;
  - inside the Project session → select the target window;
  - detached mode → create the Worktree and window without switching; when
    outside tmux, create the session detached and print how to attach.

### Sandbox policy

A single `bwrap` invocation per launched process, default-deny:

- **Writable:** the Worktree, `/tmp`, `~/.kit` (session storage).
- **Read-only:** the git common dir (the Worktree's gitdir), the resolved target
  of each symlink created above, the system directories needed to run
  (`/usr`, `/bin`, `/lib`, `/lib64`, `/etc`), the directory containing the kit
  binary, `~/.config/kit`, and `~/.kit.yml`.
- **Network:** allowed (no network namespace isolation).
- The sandbox is `--die-with-parent`.
- `--allow-git-write` makes the git common dir writable instead of read-only.
- Symlink targets are always read-only regardless of other flags.
- The sandboxed launch always passes `--no-daemon`, so kit never hands the
  session to the host daemon (which would run kit outside the sandbox).
- The kit window's fallback after kit exits is to close; there is no sandboxed
  interactive shell left behind.

### Shell subcommand

- `kwt shell <branch>` opens an **unsandboxed host** shell window named
  `<slug>~` in the Worktree. It requires an existing Worktree unless `--create`
  is given.
- `--sandboxed` runs the same shell inside the sandbox (read-only git, no kit)
  for debugging/testing.
- The shell window is **not** a kit session and does not count against the
  one-kit-session-per-Worktree invariant.

### Management subcommands

- `kwt ls` lists the Project's Worktrees and marks which have a kit session running.
- `kwt rm [<branch>]` kills the Worktree's windows and runs the git worktree
  removal. It refuses while a kit session is running unless `--force`. It never
  modifies the Main checkout.
- Bare `kwt rm` chooses from the available Worktrees.

### Dry run

- `--dry-run` performs all resolution and prints the plan as deterministic,
  line-oriented records (worktree path, branch, base, symlinks to create, tmux
  session/window names, and the full bwrap argv), performing no side effects.
  It exists both as a user feature and as the primary test seam.

### Invariants

- At most one kit session per Worktree.
- Everything shared — symlink targets and git state — is read-only to the sandbox.
- Sandboxed launches are always `--no-daemon`.

### Accompanying documentation deliverables

- A root `CONTEXT.md` recording the glossary: **Project**, **Main checkout**,
  **Worktree**, **Slug**, **tmux session**, **tmux window**, **kit session**.
- An ADR recording the sandbox policy (read-only shared files, read-only git by
  default, `--no-daemon` inside bwrap), because it is hard to reverse, surprising
  without context, and a genuine trade-off.

## Testing Decisions

- **What makes a good test here:** drive the `kwt` executable as a black box and
  assert only on externally observable results — the printed plan, filesystem
  state, and the recorded argv of external tools. Do not source the script or
  assert on internal functions or variable names.
- **Seam:** one seam, the `kwt` process boundary. Pure resolution is exercised
  via `--dry-run`; side-effectful behaviour is exercised by running the CLI with
  `tmux`, `bwrap`, and `kit` replaced by PATH shims that append their argv to a
  log file, while `git` runs for real inside throwaway temporary repositories.
- **Modules under test:** the whole CLI. The sandbox command construction is
  covered through the bwrap argv printed by `--dry-run`.
- **Prior art:** none — this is greenfield; these tests establish the pattern.

## Out of Scope

- Secret management of any kind.
- A per-repository configuration file (mounts, hooks, extra symlinks).
- Network proxying or egress filtering.
- Dependency installation inside the sandbox (dependencies are read-only there;
  installs happen from the shell window).
- Setting a kit session display name (kit can only rename live daemon sessions,
  and sandboxed launches are `--no-daemon` by design).
- Live sessions after exiting a sandboxed kit instance.
- Language detection beyond Python and Node.
- Remote/paired kit hosts.

## Further Notes

- `kit`'s installed binary is newer than the locally cloned source: the binary
  supports `--no-daemon` and `kit session {ls,attach,kill,rename}`, while the
  clone under the developer's foss directory does not. The implementation should
  target the **installed binary's** interface.
- The one-kit-session-per-Worktree invariant is enforced by convention through
  the tmux window layout rather than by a lock file.
- The bwrap policy is deliberately conservative; the proxy and a per-repo config
  file are the natural next features once this lands.
