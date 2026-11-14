#!/usr/bin/env bash
# 10: the Makefile installs the launcher and its kit extension.
. "$(dirname "$0")/lib.sh"

t_install_places_script_and_extension() {
  mk_env
  make -C "$ROOT" install DESTDIR="$SB/stage" >/dev/null
  local bin="$SB/stage$HOME/.local/bin/kwt"
  local ext="$SB/stage$HOME/.config/kit/extensions/00-headless.go"
  assert_file "$bin"
  assert_file "$ext"
  [ -x "$bin" ] || fail "installed kwt is not executable"
  cmp -s "$ROOT/kwt" "$bin" || fail "installed kwt differs from the source"
  cmp -s "$ROOT/extensions/00-headless.go" "$ext" || fail "installed extension differs from the source"
}

t_install_follows_path_overrides() {
  mk_env
  make -C "$ROOT" install PREFIX="$SB/prefix" EXT_DIR="$SB/ext" >/dev/null
  assert_file "$SB/prefix/bin/kwt"
  assert_file "$SB/ext/00-headless.go"
}

t_uninstall_removes_both() {
  mk_env
  make -C "$ROOT" install DESTDIR="$SB/stage" >/dev/null
  make -C "$ROOT" uninstall DESTDIR="$SB/stage" >/dev/null
  assert_no_file "$SB/stage$HOME/.local/bin/kwt"
  assert_no_file "$SB/stage$HOME/.config/kit/extensions/00-headless.go"
}

run_test "make install places the script and the extension" t_install_places_script_and_extension
run_test "make install honours PREFIX and EXT_DIR overrides" t_install_follows_path_overrides
run_test "make uninstall removes what install created" t_uninstall_removes_both

finish
