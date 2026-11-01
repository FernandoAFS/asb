#!/usr/bin/env bash
# Integration test: run the real bwrap sandbox produced by kwt.
#
# Unlike the other suites, this one runs actual bwrap with the argv kwt builds,
# and has a probe "kit" report what the sandbox allowed. It skips itself when
# bwrap cannot be run (e.g. no unprivileged user namespaces).
. "$(dirname "$0")/lib.sh"

if ! bwrap --ro-bind / / true >/dev/null 2>&1; then
  printf 'skip: bwrap cannot run here\n'
  exit 0
fi

REAL_BWRAP=$(command -v bwrap)

install_probe_kit() {
  mkdir -p "$SB/bin"
  ln -sf "$REAL_BWRAP" "$SB/bin/bwrap"
  ln -sf "$SHIMDIR/tmux" "$SB/bin/tmux"
  cat >"$SB/bin/kit" <<'PROBE'
#!/usr/bin/env bash
{
  echo "pwd=$(pwd)"
  echo "args=$*"
  if echo x >worktree-write.txt 2>/dev/null; then echo "worktree=writable"; else echo "worktree=readonly"; fi
  if echo x >"$PROBE_GITDIR/denied" 2>/dev/null; then echo "git=writable"; else echo "git=readonly"; fi
  if echo x >"$PROBE_VENV/denied" 2>/dev/null; then echo "venv=writable"; else echo "venv=readonly"; fi
} >sandbox-probe.out 2>&1
exit 0
PROBE
  chmod +x "$SB/bin/kit"
  export PATH="$SB/bin:$PATH"
  export TMUX_EXEC=1
  export PROBE_GITDIR="$SB/proj/.git"
  export PROBE_VENV="$SB/proj/.venv"
}

t_real_sandbox_policy() {
  mk_env
  make_python_project
  echo 'X=1' >.env
  install_probe_kit
  run_kwt feature/one >/dev/null 2>&1
  probe="$SB/proj/.worktrees/feature-one/sandbox-probe.out"
  assert_file "$probe"
  out=$(cat "$probe")
  assert_contains "$out" "worktree=writable"
  assert_contains "$out" "git=readonly"
  assert_contains "$out" "venv=readonly"
  assert_contains "$out" "args=--no-daemon"
}

t_real_sandbox_git_writable_flag() {
  mk_env
  make_python_project
  install_probe_kit
  run_kwt feature/two --allow-git-write >/dev/null 2>&1
  probe="$SB/proj/.worktrees/feature-two/sandbox-probe.out"
  assert_file "$probe"
  out=$(cat "$probe")
  assert_contains "$out" "git=writable"
  assert_contains "$out" "venv=readonly"
  assert_contains "$out" "worktree=writable"
}

run_test "the real sandbox allows Worktree writes and denies git/venv writes" t_real_sandbox_policy
run_test "--allow-git-write opens git but keeps linked targets read-only" t_real_sandbox_git_writable_flag

finish
