#!/usr/bin/env bash
# 06: kwt shell <dir>.
. "$(dirname "$0")/lib.sh"

t_shell_runs_a_sandboxed_shell() {
  mk_env
  : >"$SHIM_LOG"
  run_kwt shell . >/dev/null
  assert_log_contains "bwrap"
  assert_log_contains "--chdir $SB/proj"
  assert_log_contains "/bin/bash"
  assert_log_not_contains "kit --no-daemon"
}

t_shell_is_not_headless() {
  mk_env
  out=$(run_kwt shell . --dry-run)
  assert_not_contains "$out" "KIT_OPT_HEADLESS"
}

t_shell_git_readonly_by_default() {
  mk_env
  out=$(run_kwt shell . --dry-run)
  assert_contains "$out" "--ro-bind $SB/proj/.git $SB/proj/.git"
}

t_shell_allow_git_write() {
  mk_env
  out=$(run_kwt shell . --allow-git-write --dry-run)
  assert_contains "$out" "--bind $SB/proj/.git $SB/proj/.git"
}

t_shell_missing_dir_fails() {
  mk_env
  if out=$(run_kwt shell nope --dry-run 2>&1); then fail "expected failure"; fi
  assert_contains "$out" "not a directory"
}

t_shell_bare_invocation_defaults_to_current_dir() {
  mk_env
  out=$(run_kwt shell --dry-run)
  assert_contains "$out" "dir $SB/proj"
}

run_test "kwt shell runs a sandboxed shell in the Target directory" t_shell_runs_a_sandboxed_shell
run_test "kwt shell defaults to the current directory" t_shell_bare_invocation_defaults_to_current_dir
run_test "the shell window is not a kit session" t_shell_is_not_headless
run_test "the shell keeps git read-only by default" t_shell_git_readonly_by_default
run_test "--allow-git-write applies to the shell" t_shell_allow_git_write
run_test "a missing directory fails clearly" t_shell_missing_dir_fails

finish
