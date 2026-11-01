# 04: Open a tmux window per Worktree and launch kit

**What to build:** Launching opens a tmux window named `<slug>` in a session named after the Project and runs kit in it. From outside tmux the session is created and attached; from inside a different session the client switches to the Project session; from inside the Project session the window is selected. Re-running selects the existing window instead of starting a second kit session. `-d`/`--detached` creates the Worktree and window without switching (and, when outside tmux, prints how to attach). A trailing `-- <prompt>` is passed through to kit. The window closes when kit exits.

**Blocked by:** 02 — Create-or-reuse a Worktree for a branch

**Status:** ready-for-agent

- [ ] The tmux session is named after the Project and the kit window is named `<slug>`.
- [ ] From outside tmux, the session is created and attached.
- [ ] From inside a different session, the client switches to the Project session.
- [ ] From inside the Project session, the matching window is selected.
- [ ] Re-running for a Worktree whose window exists selects it and starts no second kit session.
- [ ] `-d`/`--detached` creates the Worktree and window without switching, printing attach instructions when outside tmux.
- [ ] A trailing `-- <prompt>` is passed through to kit.
- [ ] The kit window closes when kit exits.

## Comments

Implemented; covered by `test/04_*_test.sh` (see `test/run.sh`).
