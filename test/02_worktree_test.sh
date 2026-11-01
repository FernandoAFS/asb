#!/usr/bin/env bash
# 02: Create-or-reuse a Worktree for a branch.
. "$(dirname "$0")/lib.sh"

t_creates_worktree() {
  mk_env
  run_kwt feature/one >/dev/null
  assert_dir "$SB/proj/.worktrees/feature-one"
  assert_success git -C "$SB/proj/.worktrees/feature-one" rev-parse --is-inside-work-tree
}

t_exclude_not_tracked_ignore() {
  mk_env
  run_kwt feature/one >/dev/null
  assert_contains "$(cat "$SB/proj/.git/info/exclude")" ".worktrees"
  assert_no_file "$SB/proj/.gitignore"
  status=$(git -C "$SB/proj" status --porcelain)
  assert_not_contains "$status" ".worktrees"
}

t_new_branch_from_base() {
  mk_env
  echo one >one.txt
  project_commit one
  echo two >two.txt
  project_commit two
  run_kwt feature/one --base HEAD~1 >/dev/null
  assert_eq "$(git -C "$SB/proj" rev-parse feature/one)" "$(git -C "$SB/proj" rev-parse HEAD~1)"
}

t_new_branch_defaults_to_head() {
  mk_env
  echo one >one.txt
  project_commit one
  run_kwt feature/two >/dev/null
  assert_eq "$(git -C "$SB/proj" rev-parse feature/two)" "$(git -C "$SB/proj" rev-parse HEAD)"
}

t_existing_branch_checked_out() {
  mk_env
  git -C "$SB/proj" branch existing
  run_kwt existing >/dev/null
  assert_dir "$SB/proj/.worktrees/existing"
  assert_eq "$(git -C "$SB/proj/.worktrees/existing" symbolic-ref --short HEAD)" "existing"
}

t_rerun_reuses_worktree() {
  mk_env
  run_kwt feature/one >/dev/null
  : >"$SHIM_LOG"
  run_kwt feature/one >/dev/null
  assert_dir "$SB/proj/.worktrees/feature-one"
  assert_log_not_contains "new-window"
  assert_log_not_contains "new-session"
  assert_eq "$(git -C "$SB/proj" worktree list --porcelain | grep -c '^worktree ')" "2"
}

t_dry_run_has_worktree_branch_base() {
  mk_env
  out=$(run_kwt feature/one --dry-run)
  assert_contains "$out" "worktree $SB/proj/.worktrees/feature-one"
  assert_contains "$out" "branch feature/one"
  assert_contains "$out" "base $(git rev-parse HEAD)"
}

t_default_base_is_main_head_from_worktree() {
  mk_env
  echo one >one.txt
  project_commit one
  git worktree add -q .worktrees/other -b other
  git -C .worktrees/other commit -q --allow-empty -m wt-only
  out=$(cd .worktrees/other && run_kwt feature/new --dry-run)
  assert_contains "$out" "base $(git -C "$SB/proj" rev-parse HEAD)"
  assert_not_contains "$out" "base $(git -C "$SB/proj/.worktrees/other" rev-parse HEAD)"
}

run_test "kwt <branch> creates a usable Worktree" t_creates_worktree
run_test ".worktrees goes into git's exclude, not the tracked ignore" t_exclude_not_tracked_ignore
run_test "a new branch is created from --base" t_new_branch_from_base
run_test "a new branch defaults to the current HEAD" t_new_branch_defaults_to_head
run_test "an existing branch is checked out, not recreated" t_existing_branch_checked_out
run_test "re-running reuses the Worktree and changes nothing" t_rerun_reuses_worktree
run_test "the dry-run plan carries worktree, branch, and base" t_dry_run_has_worktree_branch_base
run_test "--base defaults to the Main checkout's HEAD from inside a Worktree" t_default_base_is_main_head_from_worktree

finish
