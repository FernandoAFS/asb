#!/usr/bin/env bash
# 06: asb --shell — a debugging shell in the agent's sandbox.
. "$(dirname "$0")/lib.sh"

t_shell_runs_a_sandboxed_shell() {
  mk_env
  : >"$SHIM_LOG"
  run_kit --shell . >/dev/null
  assert_log_contains "bwrap"
  assert_log_contains "--chdir $SB/proj"
  assert_log_contains "/bin/bash"
  assert_log_not_contains "kit --no-daemon"
}

t_shell_is_not_headless() {
  mk_env
  out=$(run_kit --shell . --dry-run)
  assert_not_contains "$out" "KIT_OPT_HEADLESS"
}

t_shell_mounts_the_agent_config() {
  mk_env
  out=$(run_kit --shell . --dry-run)
  assert_contains "$out" "--ro-bind $HOME/.config/kit $HOME/.config/kit"
}

t_shell_git_readonly_by_default() {
  mk_env
  out=$(run_kit --shell . --dry-run)
  assert_contains "$out" "--ro-bind $SB/proj/.git $SB/proj/.git"
}

t_shell_allow_git_write() {
  mk_env
  out=$(run_kit --shell . --allow-git-write --dry-run)
  assert_contains "$out" "--bind $SB/proj/.git $SB/proj/.git"
}

t_shell_missing_dir_fails() {
  mk_env
  if out=$(run_kit --shell nope --dry-run 2>&1); then fail "expected failure"; fi
  assert_contains "$out" "not a directory"
}

t_shell_defaults_to_current_dir() {
  mk_env
  out=$(run_kit --shell --dry-run)
  assert_contains "$out" "dir $SB/proj"
}

t_shell_forwards_args_after_separator() {
  mk_env
  out=$(run_kit --shell . --dry-run -- -c 'echo hi')
  assert_contains "$out" "/bin/bash -c"
}

t_shell_does_not_need_the_agent_on_path() {
  mk_env
  # Shell mode never resolves the agent binary; the profile still supplies the
  # configuration mounts.
  if ! out=$(PATH=/usr/bin:/bin run_asb --shell kit . --dry-run 2>&1); then
    fail "shell mode should not require kit on PATH: $out"
  fi
  assert_contains "$out" "/bin/bash"
  assert_contains "$out" "--ro-bind $HOME/.config/kit $HOME/.config/kit"
}

run_test "asb --shell runs a sandboxed shell in the Target directory" t_shell_runs_a_sandboxed_shell
run_test "asb --shell defaults to the current directory" t_shell_defaults_to_current_dir
run_test "the shell is not a headless agent session" t_shell_is_not_headless
run_test "the shell still uses the agent profile's config" t_shell_mounts_the_agent_config
run_test "the shell keeps git read-only by default" t_shell_git_readonly_by_default
run_test "--allow-git-write applies to the shell" t_shell_allow_git_write
run_test "arguments after -- are passed to the shell" t_shell_forwards_args_after_separator
run_test "the shell does not need the agent on PATH" t_shell_does_not_need_the_agent_on_path
run_test "a missing directory fails clearly" t_shell_missing_dir_fails

finish