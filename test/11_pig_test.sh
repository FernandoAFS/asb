#!/usr/bin/env bash
# 11: the pig profile — `asb pig` runs pig under the shared sandbox policy.
. "$(dirname "$0")/lib.sh"

# Create a minimal Pig configuration at a root (default: the no-XDG root,
# ~/.pig). mk_env clears XDG_CONFIG_HOME and PIG_HOME, so the defaults apply.
mk_pig_config() {
  local root=${1:-$HOME/.pig}
  mkdir -p "$root/agent/sessions"
  : >"$root/agent/settings.json"
}

t_pig_config_is_a_copy_on_write_overlay() {
  mk_env
  mk_pig_config
  out=$(run_pig . --dry-run)
  assert_contains "$out" "--overlay-src $HOME/.pig --tmp-overlay $HOME/.pig"
  assert_not_contains "$out" "--ro-bind $HOME/.pig $HOME/.pig"
}

t_pig_launches_ephemeral_without_kit_flags() {
  mk_env
  mk_pig_config
  out=$(run_pig . --dry-run)
  assert_contains "$out" "pig --no-session"
  assert_not_contains "$out" "--no-daemon"
  assert_not_contains "$out" "KIT_OPT_HEADLESS"
}

t_pig_sessions_are_hidden_read_only() {
  mk_env
  mk_pig_config
  out=$(run_pig . --dry-run)
  assert_contains "$out" "--tmpfs $HOME/.pig/agent/sessions --remount-ro $HOME/.pig/agent/sessions"
}

t_pig_config_follows_xdg_config_home() {
  mk_env
  export XDG_CONFIG_HOME="$SB/xdg"
  mk_pig_config "$XDG_CONFIG_HOME/pig"
  out=$(run_pig . --dry-run)
  assert_contains "$out" "--overlay-src $XDG_CONFIG_HOME/pig --tmp-overlay $XDG_CONFIG_HOME/pig"
  assert_not_contains "$out" "$HOME/.pig"
}

t_pig_home_overrides_xdg() {
  mk_env
  export XDG_CONFIG_HOME="$SB/xdg"
  export PIG_HOME="$SB/pighome"
  mk_pig_config "$PIG_HOME"
  mk_pig_config "$XDG_CONFIG_HOME/pig"
  out=$(run_pig . --dry-run)
  assert_contains "$out" "--overlay-src $PIG_HOME --tmp-overlay $PIG_HOME"
  assert_not_contains "$out" "--overlay-src $XDG_CONFIG_HOME/pig"
}

t_pig_agent_dir_moves_independently() {
  mk_env
  mk_pig_config
  export PIG_CODING_AGENT_DIR="$SB/agentdir"
  mkdir -p "$PIG_CODING_AGENT_DIR/sessions"
  out=$(run_pig . --dry-run)
  assert_contains "$out" "--overlay-src $PIG_CODING_AGENT_DIR --tmp-overlay $PIG_CODING_AGENT_DIR"
  assert_contains "$out" "--tmpfs $PIG_CODING_AGENT_DIR/sessions --remount-ro $PIG_CODING_AGENT_DIR/sessions"
}

t_pig_shared_pi_dirs() {
  mk_env
  mk_pig_config
  export PIG_USE_PI_DIRS=1
  mkdir -p "$HOME/.pi/agent/sessions"
  out=$(run_pig . --dry-run)
  assert_contains "$out" "--overlay-src $HOME/.pi/agent --tmp-overlay $HOME/.pi/agent"
  assert_contains "$out" "--tmpfs $HOME/.pi/agent/sessions --remount-ro $HOME/.pi/agent/sessions"
}

t_pig_explicit_session_dir_is_hidden() {
  mk_env
  mk_pig_config
  export PIG_CODING_AGENT_SESSION_DIR="$SB/sessions"
  mkdir -p "$PIG_CODING_AGENT_SESSION_DIR"
  out=$(run_pig . --dry-run)
  assert_contains "$out" "--tmpfs $PIG_CODING_AGENT_SESSION_DIR --remount-ro $PIG_CODING_AGENT_SESSION_DIR"
}

t_pig_prompt_passthrough() {
  mk_env
  mk_pig_config
  out=$(run_pig . --dry-run -- "hello world")
  assert_contains "$out" "pig --no-session hello\\ world"
}

t_pig_shell_is_not_a_pig_session() {
  mk_env
  mk_pig_config
  out=$(run_pig --shell . --dry-run)
  assert_contains "$out" "/bin/bash"
  assert_not_contains "$out" "pig --no-session"
}

t_pig_dry_run_performs_no_side_effects() {
  mk_env
  mk_pig_config
  run_pig . --dry-run >/dev/null
  assert_log_not_contains "bwrap"
  assert_log_not_contains "pig"
}

t_agent_runs_pig_in_the_current_directory() {
  mk_env
  mk_pig_config
  : >"$SHIM_LOG"
  run_pig >/dev/null
  assert_log_contains "bwrap"
  assert_log_contains "pig --no-session"
}

run_test "pig configuration is a copy-on-write overlay" t_pig_config_is_a_copy_on_write_overlay
run_test "pig launches ephemeral without kit's flags" t_pig_launches_ephemeral_without_kit_flags
run_test "the pig session store is hidden and read-only" t_pig_sessions_are_hidden_read_only
run_test "the pig config root follows XDG_CONFIG_HOME" t_pig_config_follows_xdg_config_home
run_test "PIG_HOME overrides XDG_CONFIG_HOME" t_pig_home_overrides_xdg
run_test "the pig agent directory can move independently" t_pig_agent_dir_moves_independently
run_test "shared Pi directories are mounted and hidden" t_pig_shared_pi_dirs
run_test "an explicit pig session directory is hidden" t_pig_explicit_session_dir_is_hidden
run_test "a trailing prompt is passed through to pig" t_pig_prompt_passthrough
run_test "asb pig shell is not a pig session" t_pig_shell_is_not_a_pig_session
run_test "a pig dry run performs no side effects" t_pig_dry_run_performs_no_side_effects
run_test "asb pig runs in the current directory" t_agent_runs_pig_in_the_current_directory

finish
