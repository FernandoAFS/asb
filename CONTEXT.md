# kwt

`kwt` is a kit worktree wrapper: a single command that gives a branch its own
git Worktree, links the shared dependency and env paths into it, opens a tmux
window for it, and runs kit there inside a sandbox. This file fixes the words
the project uses for those things.

## Language

**Project**:
A git repository together with its Main checkout, identified by the repository's
common git directory.
_Avoid_: repo, workspace

**Main checkout**:
The working tree that owns the repository's shared git directory, whichever
directory `kwt` was invoked from, including from inside a Worktree.
_Avoid_: primary branch, source tree, root

**Worktree**:
A second working tree of a Project, created for one branch and living under the
Main checkout's `.worktrees` directory.
_Avoid_: checkout, clone, sandbox

**Slug**:
A branch name with every `/` replaced by `-`, used to name the Worktree
directory and the tmux windows for that branch.
_Avoid_: handle, id

**tmux session**:
The tmux session for a Project, named after the Main checkout, which holds every
window opened for that Project's Worktrees.
_Avoid_: server, group

**tmux window**:
A single window inside a tmux session, named for the Worktree it belongs to:
the Slug for the kit launch and the Slug followed by `~` for a shell.
_Avoid_: pane, tab

**kit session**:
A running kit instance in a Worktree. There is at most one per Worktree; the
shell window is not one.
_Avoid_: agent, daemon
