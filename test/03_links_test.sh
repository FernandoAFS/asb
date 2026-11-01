#!/usr/bin/env bash
# 03: Link shared dependency and env paths into the Worktree.
. "$(dirname "$0")/lib.sh"

t_venv_linked_for_python() {
  mk_env
  echo 'print(1)' >pyproject.toml
  mkdir -p .venv
  echo v >.venv/marker
  run_kwt feature/one >/dev/null
  assert_symlink "$SB/proj/.worktrees/feature-one/.venv"
  assert_eq "$(readlink -f "$SB/proj/.worktrees/feature-one/.venv")" "$SB/proj/.venv"
}

t_node_modules_linked_for_node() {
  mk_env
  echo '{}' >package.json
  mkdir -p node_modules
  echo v >node_modules/marker
  run_kwt feature/one >/dev/null
  assert_symlink "$SB/proj/.worktrees/feature-one/node_modules"
  assert_eq "$(readlink -f "$SB/proj/.worktrees/feature-one/node_modules")" "$SB/proj/node_modules"
}

t_env_linked_always() {
  mk_env
  echo 'X=1' >.env
  run_kwt feature/one >/dev/null
  assert_symlink "$SB/proj/.worktrees/feature-one/.env"
}

t_no_detection_no_link() {
  mk_env
  mkdir -p .venv node_modules
  echo v >.venv/marker
  run_kwt feature/one >/dev/null
  assert_no_file "$SB/proj/.worktrees/feature-one/.venv"
  assert_no_file "$SB/proj/.worktrees/feature-one/node_modules"
}

t_existing_path_not_overwritten() {
  mk_env
  echo 'X=1' >.env
  project_commit env
  run_kwt feature/one >/dev/null
  assert_file "$SB/proj/.worktrees/feature-one/.env"
  if [ -L "$SB/proj/.worktrees/feature-one/.env" ]; then fail "existing .env was replaced by a symlink"; fi
}

t_missing_targets_skipped() {
  mk_env
  echo 'print(1)' >pyproject.toml
  run_kwt feature/one >/dev/null
  assert_no_file "$SB/proj/.worktrees/feature-one/.venv"
}

t_dry_run_lists_links() {
  mk_env
  echo 'print(1)' >pyproject.toml
  mkdir -p .venv
  echo v >.venv/marker
  echo 'X=1' >.env
  out=$(run_kwt feature/one --dry-run)
  assert_contains "$out" "link .venv $SB/proj/.venv"
  assert_contains "$out" "link .env $SB/proj/.env"
  assert_not_contains "$out" "link node_modules"
}

run_test ".venv is linked when the Main checkout looks Python" t_venv_linked_for_python
run_test "node_modules is linked when the Main checkout looks Node" t_node_modules_linked_for_node
run_test ".env is linked whenever present" t_env_linked_always
run_test "no link is made without detection" t_no_detection_no_link
run_test "an existing path in the Worktree is left untouched" t_existing_path_not_overwritten
run_test "targets missing from the Main checkout are skipped" t_missing_targets_skipped
run_test "links to create appear in the dry-run plan" t_dry_run_lists_links

finish
