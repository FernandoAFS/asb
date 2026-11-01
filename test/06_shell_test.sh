#!/usr/bin/env bash
# 06: kwt shell <branch>.
. "$(dirname "$0")/lib.sh"

t_shell_opens_unsandboxed_window() {
  mk_env
  run_kwt feature/one >/dev/null
  : >"$SHIM_LOG"
  run_kwt shell feature/one >/dev/null
  assert_log_contains "new-window -t proj -n feature-one~ -c $SB/proj/.worktrees/feature-one"
  assert_log_not_contains "bwrap"
}

t_shell_requires_existing_worktree() {
  mk_env
  if out=$(run_kwt shell feature/one 2>&1); then fail "expected failure"; fi
  assert_contains "$out" "no Worktree for 'feature/one'"
  assert_contains "$out" "kwt feature/one"
}

t_shell_create_creates_worktree() {
  mk_env
  run_kwt shell feature/one --create >/dev/null
  assert_dir "$SB/proj/.worktrees/feature-one"
}

t_shell_sandboxed_uses_policy() {
  mk_env
  run_kwt feature/one >/dev/null
  : >"$SHIM_LOG"
  run_kwt shell feature/one --sandboxed >/dev/null
  assert_log_contains "bwrap"
  assert_log_contains "--ro-bind $SB/proj/.git $SB/proj/.git"
  assert_log_contains "--chdir $SB/proj/.worktrees/feature-one"
  assert_log_not_contains "kit --no-daemon"
}

t_shell_window_is_not_a_kit_session() {
  mk_env
  run_kwt feature/one >/dev/null
  kill_window feature-one
  run_kwt shell feature/one >/dev/null
  assert_contains "$(run_kwt ls)" "stopped feature-one"
}

run_test "kwt shell opens an unsandboxed shell window in the Worktree" t_shell_opens_unsandboxed_window
run_test "without --create a missing Worktree is a clear error" t_shell_requires_existing_worktree
run_test "with --create a missing Worktree is created first" t_shell_create_creates_worktree
run_test "--sandboxed runs the shell under the sandbox policy" t_shell_sandboxed_uses_policy
run_test "the shell window is not a kit session" t_shell_window_is_not_a_kit_session

finish
