#!/usr/bin/env bash
# 01: Foundation — CLI, Project resolution, and the --dry-run plan.
. "$(dirname "$0")/lib.sh"

t_dry_run_from_root() {
  mk_env
  echo 'print(1)' >pyproject.toml
  out=$(run_kwt feature/one --dry-run)
  assert_contains "$out" "worktree $SB/proj/.worktrees/feature-one"
  assert_contains "$out" "branch feature/one"
  assert_contains "$out" "base $(git rev-parse HEAD)"
  assert_contains "$out" "session proj"
  assert_contains "$out" "window feature-one"
}

t_dry_run_from_subdir() {
  mk_env
  mkdir -p a/b/c
  out=$(cd a/b/c && run_kwt feature/one --dry-run)
  assert_contains "$out" "worktree $SB/proj/.worktrees/feature-one"
  assert_contains "$out" "session proj"
}

t_dry_run_inside_worktree_yields_main() {
  mk_env
  git worktree add -q .worktrees/existing -b existing
  out=$(cd .worktrees/existing && run_kwt feature/two --dry-run)
  assert_contains "$out" "worktree $SB/proj/.worktrees/feature-two"
  assert_contains "$out" "session proj"
  assert_not_contains "$out" ".worktrees/existing/.worktrees"
}

t_dry_run_performs_no_side_effects() {
  mk_env
  echo 'print(1)' >pyproject.toml
  run_kwt feature/one --dry-run >/dev/null
  assert_no_file "$SB/proj/.worktrees"
  assert_log_not_contains "tmux"
  assert_log_not_contains "bwrap"
  assert_log_not_contains "kit"
  assert_not_contains "$(cat "$SB/proj/.git/info/exclude" 2>/dev/null || true)" ".worktrees"
}

t_outside_git_repo_fails() {
  mk_env
  mkdir -p "$SB/notgit"
  if out=$(cd "$SB/notgit" && run_kwt feature/one --dry-run 2>&1); then
    fail "expected a non-zero exit outside a git repository"
  fi
  assert_contains "$out" "not inside a git repository"
}

t_bare_invocation_is_not_a_command() {
  mk_env
  if run_kwt >/dev/null 2>&1; then fail "bare kwt should fail"; fi
}

t_argument_parsing() {
  mk_env
  base=$(git rev-parse HEAD)
  out=$(run_kwt b1 --base "$base" --detached --allow-git-write --dry-run)
  assert_contains "$out" "branch b1"
  assert_contains "$out" "base $base"
  assert_contains "$out" "attach proj"
  assert_contains "$out" "--bind $SB/proj/.git $SB/proj/.git"

  out=$(run_kwt b2 -b "$base" -d --dry-run)
  assert_contains "$out" "base $base"
  assert_contains "$out" "attach proj"

  out=$(run_kwt b3 --dry-run -- "hello world")
  assert_contains "$out" "kit --no-daemon hello\\ world"
}

t_unknown_option_fails() {
  mk_env
  if out=$(run_kwt feature/one --nope 2>&1); then fail "expected failure"; fi
  assert_contains "$out" "unknown option"
}

run_test "dry-run prints the resolved plan" t_dry_run_from_root
run_test "resolution works from a subdirectory" t_dry_run_from_subdir
run_test "resolution inside a Worktree yields the Main checkout" t_dry_run_inside_worktree_yields_main
run_test "dry-run performs no side effects" t_dry_run_performs_no_side_effects
run_test "running outside a git repository fails clearly" t_outside_git_repo_fails
run_test "bare kwt is not a command" t_bare_invocation_is_not_a_command
run_test "argument parsing accepts the documented flags" t_argument_parsing
run_test "unknown options fail" t_unknown_option_fails

finish
