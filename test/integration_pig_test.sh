#!/usr/bin/env bash
# Integration test: run the real bwrap sandbox produced by the pig profile.
#
# Like integration_bwrap_test.sh, this runs actual bwrap with the argv asb
# builds, and has a probe "pig" report what the sandbox allowed. It skips
# itself when bwrap cannot be run (e.g. no unprivileged user namespaces).
. "$(dirname "$0")/lib.sh"

if ! bwrap --ro-bind / / true >/dev/null 2>&1; then
  printf 'skip: bwrap cannot run here\n'
  exit 0
fi

REAL_BWRAP=$(command -v bwrap)

install_probe_pig() {
  mkdir -p "$SB/bin"
  ln -sf "$REAL_BWRAP" "$SB/bin/bwrap"
  cat >"$SB/bin/pig" <<'PROBE'
#!/usr/bin/env bash
{
  echo "pwd=$(pwd)"
  echo "args=$*"
  if echo x >target-write.txt 2>/dev/null; then echo "target=writable"; else echo "target=readonly"; fi
  if echo x >"$PROBE_GITDIR/denied" 2>/dev/null; then echo "git=writable"; else echo "git=readonly"; fi
  if [ -e "$PROBE_CONFIG/settings.json" ]; then echo "config=readable"; else echo "config=absent"; fi
  if mkdir "$PROBE_CONFIG/trust.json.lock" 2>/dev/null; then echo "lock=ok"; else echo "lock=FAILED"; fi
  if echo x >"$PROBE_CONFIG/settings.json" 2>/dev/null; then echo "config=writable"; else echo "config=readonly"; fi
  if [ -r "$PROBE_SESSIONS/secret.jsonl" ]; then echo "sessions=readable"; else echo "sessions=hidden"; fi
  if echo x >"$PROBE_SESSIONS/denied" 2>/dev/null; then echo "sessions=writable"; else echo "sessions=readonly"; fi
} >sandbox-probe.out 2>&1
exit 0
PROBE
  chmod +x "$SB/bin/pig"
  export PATH="$SB/bin:$PATH"
}

t_real_pig_sandbox_allows_ephemeral_config_writes() {
  mk_env
  # mk_env clears XDG_CONFIG_HOME, so pig's root defaults to ~/.pig.
  mkdir -p "$HOME/.pig/agent/sessions"
  echo '{"theme":"system"}' >"$HOME/.pig/agent/settings.json"
  echo '{"secret":true}' >"$HOME/.pig/agent/sessions/secret.jsonl"
  install_probe_pig
  export PROBE_GITDIR="$SB/proj/.git"
  export PROBE_CONFIG="$HOME/.pig/agent"
  export PROBE_SESSIONS="$HOME/.pig/agent/sessions"

  run_pig . >/dev/null 2>&1

  probe="$SB/proj/sandbox-probe.out"
  assert_file "$probe"
  out=$(cat "$probe")
  assert_contains "$out" "pwd=$SB/proj"
  assert_contains "$out" "target=writable"
  assert_contains "$out" "git=readonly"
  assert_contains "$out" "config=readable"
  # Pig resolves project trust by creating trust.json.lock; a read-only config
  # made that fail with EROFS. The overlay lets it write, to a tmpfs.
  assert_contains "$out" "lock=ok"
  assert_contains "$out" "config=writable"
  assert_contains "$out" "sessions=hidden"
  assert_contains "$out" "sessions=readonly"
  assert_contains "$out" "args=--no-session"

  # Everything the probe wrote stayed inside the sandbox.
  assert_eq "$(cat "$HOME/.pig/agent/settings.json")" '{"theme":"system"}'
  assert_no_file "$HOME/.pig/agent/trust.json.lock"
}

run_test "the real pig sandbox allows ephemeral config writes and hides sessions" \
  t_real_pig_sandbox_allows_ephemeral_config_writes

finish