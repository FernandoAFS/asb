#!/usr/bin/env bash
# 04: Open a tmux window per Worktree and launch kit.
. "$(dirname "$0")/lib.sh"

t_session_and_window_names() {
  mk_env
  run_kwt feature/one >/dev/null
  assert_log_contains "new-session -d -s proj -n feature-one"
}

t_outside_tmux_attaches() {
  mk_env
  run_kwt feature/one >/dev/null
  assert_log_contains "attach -t proj"
  assert_log_not_contains "switch-client"
}

t_inside_other_session_switches() {
  mk_env
  inside_tmux_as other
  run_kwt feature/one >/dev/null
  assert_log_contains "switch-client -t proj"
}

t_inside_project_session_selects() {
  mk_env
  inside_tmux_as proj
  run_kwt feature/one >/dev/null
  assert_log_contains "select-window -t proj:feature-one"
  assert_log_not_contains "switch-client"
}

t_rerun_selects_existing_window() {
  mk_env
  run_kwt feature/one >/dev/null
  : >"$SHIM_LOG"
  run_kwt feature/one >/dev/null
  assert_log_not_contains "new-window"
  assert_log_not_contains "new-session"
  assert_log_contains "select-window -t proj:feature-one"
}

t_detached_creates_without_attach() {
  mk_env
  out=$(run_kwt feature/one --detached)
  assert_log_contains "new-session -d -s proj -n feature-one"
  assert_log_not_contains "attach -t proj"
  assert_contains "$out" "tmux attach -t proj"
}

t_prompt_passed_through() {
  mk_env
  run_kwt feature/one -- "fix the bug" >/dev/null
  assert_log_contains "kit --no-daemon fix\\ the\\ bug"
}

t_kit_window_closes_with_kit() {
  mk_env
  run_kwt feature/one >/dev/null
  # The window runs the launch command directly, so tmux closes it on exit.
  assert_log_contains "new-session -d -s proj -n feature-one bwrap"
}

run_test "the tmux session is the Project, the window is the slug" t_session_and_window_names
run_test "from outside tmux the session is created and attached" t_outside_tmux_attaches
run_test "from another session the client switches to the Project" t_inside_other_session_switches
run_test "inside the Project session the window is selected" t_inside_project_session_selects
run_test "re-running selects the window and starts no second kit" t_rerun_selects_existing_window
run_test "-d/--detached does not switch and prints how to attach" t_detached_creates_without_attach
run_test "a trailing -- <prompt> is passed through to kit" t_prompt_passed_through
run_test "the kit window runs kit directly so it closes on exit" t_kit_window_closes_with_kit

finish
