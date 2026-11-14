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
  cat >"$SB/bin/kit" <<'PROBE'
#!/usr/bin/env bash
{
  echo "pwd=$(pwd)"
  echo "args=$*"
  if echo x >target-write.txt 2>/dev/null; then echo "target=writable"; else echo "target=readonly"; fi
  if echo x >"$PROBE_GITDIR/denied" 2>/dev/null; then echo "git=writable"; else echo "git=readonly"; fi
  if echo x >"$PROBE_KITDIR/denied" 2>/dev/null; then echo "kitdir=writable"; else echo "kitdir=readonly"; fi
  if [ -e "$HOME/.kit" ]; then echo "sessionstore=present"; else echo "sessionstore=absent"; fi
} >sandbox-probe.out 2>&1
exit 0
PROBE
  chmod +x "$SB/bin/kit"
  export PATH="$SB/bin:$PATH"
  export PROBE_GITDIR="$SB/proj/.git"
  export PROBE_KITDIR="$SB/bin"
}

t_real_sandbox_policy() {
  mk_env
  install_probe_kit
  run_kwt . >/dev/null 2>&1
  probe="$SB/proj/sandbox-probe.out"
  assert_file "$probe"
  out=$(cat "$probe")
  assert_contains "$out" "pwd=$SB/proj"
  assert_contains "$out" "target=writable"
  assert_contains "$out" "git=readonly"
  assert_contains "$out" "kitdir=readonly"
  assert_contains "$out" "sessionstore=absent"
  assert_contains "$out" "args=--no-daemon --no-session"
}

t_real_sandbox_git_writable_flag() {
  mk_env
  install_probe_kit
  run_kwt . --allow-git-write >/dev/null 2>&1
  probe="$SB/proj/sandbox-probe.out"
  assert_file "$probe"
  out=$(cat "$probe")
  assert_contains "$out" "git=writable"
  assert_contains "$out" "target=writable"
  assert_contains "$out" "kitdir=readonly"
}

run_test "the real sandbox allows target writes and denies git/kitdir writes" t_real_sandbox_policy
run_test "--allow-git-write opens git but keeps everything else contained" t_real_sandbox_git_writable_flag

finish
