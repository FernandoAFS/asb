#!/usr/bin/env bash
# Integration test: run the real bwrap sandbox produced by asb.
#
# Unlike the other suites, this one runs actual bwrap with the argv asb builds,
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
  if echo x >/tmp/sandbox-probe.tmp 2>/dev/null; then echo "tmp=writable"; else echo "tmp=readonly"; fi
  if [ -e "$PROBE_HOST_TMP" ]; then echo "tmp=host-visible"; else echo "tmp=private"; fi
  if [ -e /etc/passwd ] && [ -e /etc/resolv.conf ]; then echo "etc=allowlisted"; else echo "etc=missing"; fi
  if [ -e /etc/shadow ] || [ -e /etc/ssh/ssh_host_ed25519_key ]; then echo "etc=leaked"; else echo "etc=restricted"; fi
  if [ -n "${TMUX+x}" ] || [ -n "${TMUX_TMPDIR+x}" ]; then echo "tmux=env-present"; else echo "tmux=env-absent"; fi
  if [ -n "${DBUS_SESSION_BUS_ADDRESS+x}" ] || [ -n "${XDG_RUNTIME_DIR+x}" ]; then echo "dbus=env-present"; else echo "dbus=env-absent"; fi
  if [ -e /run/user ] || [ -e /run/dbus ]; then echo "run=visible"; else echo "run=hidden"; fi
  if [ -n "${PROBE_HOST_PID:-}" ] && [ -e "/proc/$PROBE_HOST_PID" ]; then echo "hostpid=visible"; else echo "hostpid=hidden"; fi
  echo "ipcns=$(readlink /proc/self/ns/ipc 2>/dev/null)"
  echo "utsns=$(readlink /proc/self/ns/uts 2>/dev/null)"
  if unshare --user true >/dev/null 2>&1; then echo "userns=nested-allowed"; else echo "userns=disabled"; fi
  if [ -n "${XDG_CACHE_HOME:-}" ] && echo x >"$XDG_CACHE_HOME/probe" 2>/dev/null; then echo "cache=writable"; else echo "cache=not-writable"; fi
  if [ -e "$HOME/.cache/nvim/host-cache-marker" ]; then echo "cache=host-visible"; else echo "cache=private"; fi
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
  PROBE_HOST_TMP=$(mktemp /tmp/asb-host-tmp.XXXXXX)
  export PROBE_HOST_TMP
}

t_real_sandbox_policy() {
  mk_env
  install_probe_kit
  export TMUX="/tmp/tmux-1000/default,1,0" TMUX_TMPDIR="/tmp/tmux-1000"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus" XDG_RUNTIME_DIR="/run/user/1000"
  run_kit . >/dev/null 2>&1
  rm -f "$PROBE_HOST_TMP"
  probe="$SB/proj/sandbox-probe.out"
  assert_file "$probe"
  out=$(cat "$probe")
  assert_contains "$out" "pwd=$SB/proj"
  assert_contains "$out" "target=writable"
  assert_contains "$out" "tmp=writable"
  assert_contains "$out" "tmp=private"
  assert_contains "$out" "etc=allowlisted"
  assert_contains "$out" "etc=restricted"
  assert_contains "$out" "tmux=env-absent"
  assert_contains "$out" "dbus=env-absent"
  assert_contains "$out" "run=hidden"
  assert_contains "$out" "git=readonly"
  assert_contains "$out" "kitdir=readonly"
  assert_contains "$out" "sessionstore=absent"
  assert_contains "$out" "args=--no-daemon --no-session"
}

t_real_sandbox_hides_host_processes() {
  mk_env
  install_probe_kit
  sleep 30 &
  host_sleeper=$!
  export PROBE_HOST_PID=$host_sleeper
  run_kit . >/dev/null 2>&1
  kill "$host_sleeper" 2>/dev/null || true
  wait "$host_sleeper" 2>/dev/null || true
  rm -f "$PROBE_HOST_TMP"
  probe="$SB/proj/sandbox-probe.out"
  assert_file "$probe"
  out=$(cat "$probe")
  assert_contains "$out" "hostpid=hidden"
}

t_real_sandbox_git_writable_flag() {
  mk_env
  install_probe_kit
  run_kit . --allow-git-write >/dev/null 2>&1
  probe="$SB/proj/sandbox-probe.out"
  assert_file "$probe"
  out=$(cat "$probe")
  assert_contains "$out" "git=writable"
  assert_contains "$out" "target=writable"
  assert_contains "$out" "kitdir=readonly"
}

run_test "the real sandbox allows target writes and denies git/kitdir writes" t_real_sandbox_policy
t_real_sandbox_has_writable_private_cache() {
  mk_env
  install_probe_kit
  export EDITOR=nvim
  mkdir -p "$HOME/.cache/nvim"
  : >"$HOME/.cache/nvim/host-cache-marker"
  run_kit . >/dev/null 2>&1
  rm -f "$PROBE_HOST_TMP"
  probe="$SB/proj/sandbox-probe.out"
  assert_file "$probe"
  out=$(cat "$probe")
  assert_contains "$out" "cache=writable"
  assert_contains "$out" "cache=private"
}

t_real_sandbox_isolates_ipc_uts_and_user_namespaces() {
  mk_env
  install_probe_kit
  run_kit . >/dev/null 2>&1
  rm -f "$PROBE_HOST_TMP"
  probe="$SB/proj/sandbox-probe.out"
  assert_file "$probe"
  out=$(cat "$probe")
  sandbox_ipc=$(printf '%s\n' "$out" | sed -n 's/^ipcns=//p')
  sandbox_uts=$(printf '%s\n' "$out" | sed -n 's/^utsns=//p')
  assert_ne "$sandbox_ipc" "$(readlink /proc/self/ns/ipc)"
  assert_ne "$sandbox_uts" "$(readlink /proc/self/ns/uts)"
  assert_contains "$out" "userns=disabled"
}

run_test "the real sandbox hides the host process table" t_real_sandbox_hides_host_processes
run_test "the real sandbox isolates IPC, UTS, and nested user namespaces" t_real_sandbox_isolates_ipc_uts_and_user_namespaces
run_test "the real sandbox gives nvim a writable private cache" t_real_sandbox_has_writable_private_cache
run_test "--allow-git-write opens git but keeps everything else contained" t_real_sandbox_git_writable_flag

finish