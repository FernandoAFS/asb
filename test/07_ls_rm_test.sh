#!/usr/bin/env bash
# 07: kwt ls and kwt rm.
. "$(dirname "$0")/lib.sh"

t_ls_lists_worktrees() {
  mk_env
  run_kwt feature/one >/dev/null
  run_kwt feature/two >/dev/null
  out=$(run_kwt ls)
  assert_contains "$out" "feature-one"
  assert_contains "$out" "feature-two"
}

t_ls_ignores_foreign_worktrees() {
  mk_env
  git -C "$SB/proj" worktree add -q "$SB/stray" -b stray
  out=$(run_kwt ls)
  assert_not_contains "$out" "stray"
}

t_ls_marks_running() {
  mk_env
  run_kwt feature/one >/dev/null
  assert_contains "$(run_kwt ls)" "running feature-one"
}

t_ls_marks_stopped_without_kit_window() {
  mk_env
  run_kwt feature/one >/dev/null
  kill_window feature-one
  assert_contains "$(run_kwt ls)" "stopped feature-one"
}

t_rm_removes_worktree() {
  mk_env
  run_kwt feature/one >/dev/null
  run_kwt rm feature/one --force
  assert_no_file "$SB/proj/.worktrees/feature-one"
  assert_eq "$(git -C "$SB/proj" worktree list --porcelain | grep -c '^worktree ')" "1"
}

t_rm_refuses_while_kit_running() {
  mk_env
  run_kwt feature/one >/dev/null
  if out=$(run_kwt rm feature/one 2>&1); then fail "expected refusal"; fi
  assert_contains "$out" "kit session is running"
  assert_dir "$SB/proj/.worktrees/feature-one"
}

t_rm_force_removes_while_kit_running() {
  mk_env
  run_kwt feature/one >/dev/null
  run_kwt rm feature/one --force
  assert_no_file "$SB/proj/.worktrees/feature-one"
}

t_rm_bare_offers_choices() {
  mk_env
  run_kwt feature/one >/dev/null
  printf '1\n' | run_kwt rm --force >/dev/null 2>&1
  assert_no_file "$SB/proj/.worktrees/feature-one"
}

t_rm_never_modifies_main() {
  mk_env
  echo main >a.txt
  project_commit a
  head_before=$(git -C "$SB/proj" rev-parse HEAD)
  branch_before=$(git -C "$SB/proj" symbolic-ref --short HEAD)
  run_kwt feature/one >/dev/null
  run_kwt rm feature/one --force
  assert_eq "$(git -C "$SB/proj" rev-parse HEAD)" "$head_before"
  assert_eq "$(git -C "$SB/proj" symbolic-ref --short HEAD)" "$branch_before"
  assert_eq "$(cat "$SB/proj/a.txt")" "main"
}

run_test "kwt ls lists every Worktree of the Project" t_ls_lists_worktrees
run_test "kwt ls ignores worktrees outside .worktrees" t_ls_ignores_foreign_worktrees
run_test "kwt ls marks Worktrees with a kit session" t_ls_marks_running
run_test "kwt ls marks Worktrees without a kit session stopped" t_ls_marks_stopped_without_kit_window
run_test "kwt rm removes the Worktree" t_rm_removes_worktree
run_test "kwt rm refuses while a kit session is running" t_rm_refuses_while_kit_running
run_test "kwt rm --force removes while a kit session is running" t_rm_force_removes_while_kit_running
run_test "bare kwt rm offers the available Worktrees" t_rm_bare_offers_choices
run_test "kwt rm never modifies the Main checkout" t_rm_never_modifies_main

finish
