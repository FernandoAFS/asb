#!/usr/bin/env bash
# 05: Run the kit launch inside the bwrap sandbox.
. "$(dirname "$0")/lib.sh"

t_worktree_and_tmp_writable() {
  mk_env
  out=$(run_kwt feature/one --dry-run)
  assert_contains "$out" "--bind $SB/proj/.worktrees/feature-one $SB/proj/.worktrees/feature-one"
  assert_contains "$out" "--bind /tmp /tmp"
}

t_git_readonly_by_default() {
  mk_env
  out=$(run_kwt feature/one --dry-run)
  assert_contains "$out" "--ro-bind $SB/proj/.git $SB/proj/.git"
  assert_not_contains "$out" "--bind $SB/proj/.git $SB/proj/.git"
}

t_git_writable_with_flag() {
  mk_env
  out=$(run_kwt feature/one --allow-git-write --dry-run)
  assert_contains "$out" "--bind $SB/proj/.git $SB/proj/.git"
  assert_not_contains "$out" "--ro-bind $SB/proj/.git $SB/proj/.git"
}

t_linked_targets_readonly_even_with_flag() {
  mk_env
  make_python_project
  echo 'X=1' >.env
  out=$(run_kwt feature/one --allow-git-write --dry-run)
  assert_contains "$out" "--ro-bind $SB/proj/.venv $SB/proj/.venv"
  assert_contains "$out" "--ro-bind $SB/proj/.env $SB/proj/.env"
}

t_git_optional_locks_set() {
  mk_env
  out=$(run_kwt feature/one --dry-run)
  assert_contains "$out" "--setenv GIT_OPTIONAL_LOCKS 0"
}

t_die_with_parent_and_no_daemon() {
  mk_env
  out=$(run_kwt feature/one --dry-run)
  assert_contains "$out" "--die-with-parent"
  assert_contains "$out" "kit --no-daemon"
}

t_network_allowed() {
  mk_env
  out=$(run_kwt feature/one --dry-run)
  assert_not_contains "$out" "--unshare-net"
}

t_reused_worktree_binds_shared_targets() {
  mk_env
  make_python_project
  run_kwt feature/one >/dev/null
  # On reuse the Worktree is unchanged, but its symlink target is still bound.
  out=$(run_kwt feature/one --dry-run)
  assert_contains "$out" "--ro-bind $SB/proj/.venv $SB/proj/.venv"
  assert_not_contains "$out" "link .venv"
}

t_symlinked_kit_binds_real_directory() {
  mk_env
  mkdir -p "$SB/realbin" "$SB/linkbin"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$SB/realbin/realkit"
  chmod +x "$SB/realbin/realkit"
  ln -s "$SB/realbin/realkit" "$SB/linkbin/kit"
  export PATH="$SB/linkbin:$PATH"
  out=$(run_kwt feature/one --dry-run)
  assert_contains "$out" "--ro-bind $SB/realbin $SB/realbin"
  assert_contains "$out" "$SB/realbin/realkit --no-daemon"
  assert_not_contains "$out" "--ro-bind $SB/linkbin $SB/linkbin"
}

run_test "the Worktree and /tmp are the writable state" t_worktree_and_tmp_writable
run_test "git state is read-only by default" t_git_readonly_by_default
run_test "--allow-git-write makes git writable" t_git_writable_with_flag
run_test "linked targets stay read-only even with --allow-git-write" t_linked_targets_readonly_even_with_flag
run_test "GIT_OPTIONAL_LOCKS is cleared so read-only git works" t_git_optional_locks_set
run_test "the sandbox dies with its parent and kit runs --no-daemon" t_die_with_parent_and_no_daemon
run_test "network is not namespace-isolated" t_network_allowed
run_test "a reused Worktree still binds its shared targets" t_reused_worktree_binds_shared_targets
run_test "a symlinked kit binary resolves to its real directory" t_symlinked_kit_binds_real_directory

finish
