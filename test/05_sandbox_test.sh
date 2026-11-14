#!/usr/bin/env bash
# 05: Run the kit launch inside the bwrap sandbox.
. "$(dirname "$0")/lib.sh"

t_target_and_tmp_writable() {
  mk_env
  out=$(run_kit . --dry-run)
  assert_contains "$out" "--bind $SB/proj $SB/proj"
  assert_contains "$out" "--bind /tmp /tmp"
}

t_git_readonly_by_default() {
  mk_env
  out=$(run_kit . --dry-run)
  assert_contains "$out" "--ro-bind $SB/proj/.git $SB/proj/.git"
  assert_not_contains "$out" "--bind $SB/proj/.git $SB/proj/.git"
}

t_git_writable_with_flag() {
  mk_env
  out=$(run_kit . --allow-git-write --dry-run)
  assert_contains "$out" "--bind $SB/proj/.git $SB/proj/.git"
  assert_not_contains "$out" "--ro-bind $SB/proj/.git $SB/proj/.git"
}

t_no_git_bind_outside_a_repo() {
  mk_env
  mkdir -p "$SB/plain"
  out=$(run_kit "$SB/plain" --dry-run)
  assert_contains "$out" "--bind $SB/plain $SB/plain"
  assert_not_contains "$out" "$SB/plain/.git"
}

t_git_optional_locks_set() {
  mk_env
  out=$(run_kit . --dry-run)
  assert_contains "$out" "--setenv GIT_OPTIONAL_LOCKS 0"
}

t_headless_option_is_set_for_the_kit_launch() {
  mk_env
  out=$(run_kit . --dry-run)
  assert_contains "$out" "--setenv KIT_OPT_HEADLESS true"
}

t_sandboxed_shell_is_not_headless() {
  mk_env
  out=$(run_kit --shell . --dry-run)
  assert_not_contains "$out" "KIT_OPT_HEADLESS"
}

t_die_with_parent_and_no_daemon() {
  mk_env
  out=$(run_kit . --dry-run)
  assert_contains "$out" "--die-with-parent"
  assert_contains "$out" "kit --no-daemon"
}

t_sessions_are_ephemeral() {
  mk_env
  out=$(run_kit . --dry-run)
  assert_contains "$out" "--no-session"
  assert_not_contains "$out" "$HOME/.kit"
}

t_network_allowed() {
  mk_env
  out=$(run_kit . --dry-run)
  assert_not_contains "$out" "--unshare-net"
}

t_symlinked_kit_binds_real_directory() {
  mk_env
  mkdir -p "$SB/realbin" "$SB/linkbin"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$SB/realbin/realkit"
  chmod +x "$SB/realbin/realkit"
  ln -s "$SB/realbin/realkit" "$SB/linkbin/kit"
  export PATH="$SB/linkbin:$PATH"
  out=$(run_kit . --dry-run)
  assert_contains "$out" "$SB/realbin/realkit --no-daemon"
  assert_contains "$out" "--ro-bind $SB/realbin $SB/realbin"
}

t_path_tool_directory_is_mounted_readonly() {
  mk_env
  mkdir -p "$SB/tools"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$SB/tools/mytool"
  chmod +x "$SB/tools/mytool"
  export PATH="$SB/tools:$PATH"
  out=$(run_kit . --dry-run)
  assert_contains "$out" "--ro-bind $SB/tools $SB/tools"
  assert_not_contains "$out" "--bind $SB/tools $SB/tools"
}

t_symlinked_path_tool_binds_real_target() {
  mk_env
  mkdir -p "$SB/tools" "$SB/realtools"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$SB/realtools/mytool"
  chmod +x "$SB/realtools/mytool"
  ln -s "$SB/realtools/mytool" "$SB/tools/mytool"
  export PATH="$SB/tools:$PATH"
  out=$(run_kit . --dry-run)
  assert_contains "$out" "--ro-bind $SB/realtools $SB/realtools"
}

t_path_tools_does_not_override_writable_target() {
  mk_env
  mkdir -p "$SB/proj/bin"
  export PATH="$SB/proj/bin:$PATH"
  out=$(run_kit . --dry-run)
  assert_not_contains "$out" "--ro-bind $SB/proj/bin"
}

t_provider_credentials_readonly() {
  mk_env
  mkdir -p "$HOME/.config/.kit"
  echo '{}' >"$HOME/.config/.kit/credentials.json"
  out=$(run_kit . --dry-run)
  assert_contains "$out" "--ro-bind $HOME/.config/.kit $HOME/.config/.kit"
  assert_not_contains "$out" "--bind $HOME/.config/.kit $HOME/.config/.kit"
}

t_config_follows_xdg_config_home() {
  mk_env
  export XDG_CONFIG_HOME="$SB/xdg"
  mkdir -p "$XDG_CONFIG_HOME/kit" "$XDG_CONFIG_HOME/.kit"
  echo '{}' >"$XDG_CONFIG_HOME/.kit/credentials.json"
  out=$(run_kit . --dry-run)
  assert_contains "$out" "--ro-bind $XDG_CONFIG_HOME/kit $XDG_CONFIG_HOME/kit"
  assert_contains "$out" "--ro-bind $XDG_CONFIG_HOME/.kit $XDG_CONFIG_HOME/.kit"
}

t_user_skills_readonly() {
  mk_env
  mkdir -p "$HOME/.agents/skills/demo"
  out=$(run_kit . --dry-run)
  assert_contains "$out" "--ro-bind $HOME/.agents $HOME/.agents"
  assert_not_contains "$out" "--bind $HOME/.agents $HOME/.agents"
}

t_no_bind_without_user_skills() {
  mk_env
  out=$(run_kit . --dry-run)
  assert_not_contains "$out" "$HOME/.agents"
}

t_nvim_state_is_a_private_tmpfs() {
  mk_env
  export EDITOR=nvim
  mkdir -p "$HOME/.config/nvim" "$HOME/.local/share/nvim" \
    "$HOME/.local/state/nvim" "$HOME/.cache/nvim"
  out=$(run_kit . --dry-run)
  assert_contains "$out" "--ro-bind $HOME/.config/nvim $HOME/.config/nvim"
  assert_contains "$out" "--ro-bind $HOME/.local/share/nvim $HOME/.local/share/nvim"
  assert_contains "$out" "--ro-bind $HOME/.cache/nvim $HOME/.cache/nvim"
  assert_contains "$out" "--tmpfs /tmp/asb-state --setenv XDG_STATE_HOME /tmp/asb-state"
  assert_not_contains "$out" "$HOME/.local/state/nvim"
  assert_not_contains "$out" "--bind $HOME/.config/nvim $HOME/.config/nvim"
}

t_nvim_dirs_follow_xdg() {
  mk_env
  export EDITOR=nvim
  export XDG_CONFIG_HOME="$SB/xdg/config" XDG_DATA_HOME="$SB/xdg/data"
  export XDG_STATE_HOME="$SB/xdg/state" XDG_CACHE_HOME="$SB/xdg/cache"
  mkdir -p "$XDG_CONFIG_HOME/nvim" "$XDG_DATA_HOME/nvim" \
    "$XDG_STATE_HOME/nvim" "$XDG_CACHE_HOME/nvim"
  out=$(run_kit . --dry-run)
  assert_contains "$out" "--ro-bind $XDG_CONFIG_HOME/nvim $XDG_CONFIG_HOME/nvim"
  assert_contains "$out" "--ro-bind $XDG_DATA_HOME/nvim $XDG_DATA_HOME/nvim"
  assert_contains "$out" "--tmpfs /tmp/asb-state --setenv XDG_STATE_HOME /tmp/asb-state"
  assert_not_contains "$out" "$XDG_STATE_HOME/nvim"
  assert_contains "$out" "--ro-bind $XDG_CACHE_HOME/nvim $XDG_CACHE_HOME/nvim"
}

t_vim_dirs_readonly_when_editor_is_vim() {
  mk_env
  export EDITOR=vim
  mkdir -p "$HOME/.config/vim" "$HOME/.vim"
  : >"$HOME/.vimrc"
  out=$(run_kit . --dry-run)
  assert_contains "$out" "--ro-bind $HOME/.config/vim $HOME/.config/vim"
  assert_contains "$out" "--ro-bind $HOME/.vim $HOME/.vim"
  assert_contains "$out" "--ro-bind $HOME/.vimrc $HOME/.vimrc"
  assert_not_contains "$out" "--bind $HOME/.vim $HOME/.vim"
}

t_editor_program_read_from_path_with_args() {
  mk_env
  export EDITOR="/opt/editors/nvim -f"
  mkdir -p "$HOME/.config/nvim"
  out=$(run_kit . --dry-run)
  assert_contains "$out" "--ro-bind $HOME/.config/nvim $HOME/.config/nvim"
}

t_no_editor_mounts_for_other_editor() {
  mk_env
  export EDITOR=nano
  mkdir -p "$HOME/.config/nvim" "$HOME/.config/vim" "$HOME/.vim"
  out=$(run_kit . --dry-run)
  assert_not_contains "$out" "$HOME/.config/nvim"
  assert_not_contains "$out" "$HOME/.config/vim"
  assert_not_contains "$out" "$HOME/.vim"
}

t_no_editor_mounts_when_dirs_absent() {
  mk_env
  export EDITOR=nvim
  out=$(run_kit . --dry-run)
  assert_not_contains "$out" "$HOME/.config/nvim"
  assert_not_contains "$out" "$HOME/.local/share/nvim"
}

run_test "the Target is writable and /tmp is a private tmpfs" t_target_and_tmp_writable
run_test "git state is read-only by default" t_git_readonly_by_default
run_test "--allow-git-write makes git writable" t_git_writable_with_flag
run_test "a directory outside a repo adds no git binds" t_no_git_bind_outside_a_repo
run_test "GIT_OPTIONAL_LOCKS is cleared so read-only git works" t_git_optional_locks_set
run_test "the kit launch starts headless" t_headless_option_is_set_for_the_kit_launch
run_test "a sandboxed shell is not headless" t_sandboxed_shell_is_not_headless
run_test "the sandbox dies with its parent and kit runs --no-daemon" t_die_with_parent_and_no_daemon
run_test "sandboxed sessions are ephemeral and mount no session store" t_sessions_are_ephemeral
run_test "network is not namespace-isolated" t_network_allowed
run_test "a symlinked kit binary resolves to its real directory" t_symlinked_kit_binds_real_directory
run_test "a PATH tool directory is mounted read-only" t_path_tool_directory_is_mounted_readonly
run_test "a symlinked PATH tool binds its real target" t_symlinked_path_tool_binds_real_target
run_test "PATH tools never make the Target directory read-only" t_path_tools_does_not_override_writable_target
run_test "provider credentials are mounted read-only" t_provider_credentials_readonly
run_test "kit config follows XDG_CONFIG_HOME" t_config_follows_xdg_config_home
run_test "user skills are mounted read-only" t_user_skills_readonly
run_test "user skills are not mounted when absent" t_no_bind_without_user_skills
run_test "nvim config/data/cache are read-only and state is a private tmpfs" t_nvim_state_is_a_private_tmpfs
run_test "nvim dirs follow XDG base directories" t_nvim_dirs_follow_xdg
run_test "vim dirs are mounted read-only when EDITOR is vim" t_vim_dirs_readonly_when_editor_is_vim
run_test "the editor program is read from a path with arguments" t_editor_program_read_from_path_with_args
run_test "a non-vim editor mounts nothing" t_no_editor_mounts_for_other_editor
run_test "absent editor dirs add no mounts" t_no_editor_mounts_when_dirs_absent

finish
