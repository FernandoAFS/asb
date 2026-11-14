#!/usr/bin/env bash
# Shared helpers for the kwt black-box tests.
#
# Tests drive the kwt executable as a subprocess and assert only on externally
# observable results: the printed plan, filesystem state, and the recorded argv
# of external tools. bwrap and kit are replaced by PATH shims; git runs for
# real inside throwaway repositories.
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KW="$ROOT/kwt"
SHIMDIR="$ROOT/test/shims"

PASS=0
FAIL=0

run_test() {
  local name=$1
  shift
  if ( "$@" ); then
    PASS=$((PASS + 1))
    printf 'ok   %s\n' "$name"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL %s\n' "$name" >&2
  fi
}

finish() {
  printf '\n%s:%s passed, %s failed\n' "$(basename "${BASH_SOURCE[1]:-suite}")" "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}

fail() {
  printf '  %s\n' "$*" >&2
  exit 1
}

assert_eq() { [ "$1" = "$2" ] || fail "assert_eq: expected [$2], got [$1]"; }
assert_ne() { [ "$1" != "$2" ] || fail "assert_ne: both [$1]"; }

assert_contains() {
  case "$1" in
    *"$2"*) : ;;
    *) fail "assert_contains: missing [$2] in: $1" ;;
  esac
}

assert_not_contains() {
  case "$1" in
    *"$2"*) fail "assert_not_contains: found [$2] in: $1" ;;
    *) : ;;
  esac
}

assert_file() { [ -e "$1" ] || fail "expected file: $1"; }
assert_no_file() { [ ! -e "$1" ] || fail "unexpected file: $1"; }
assert_dir() { [ -d "$1" ] || fail "expected dir: $1"; }
assert_symlink() { [ -L "$1" ] || fail "expected symlink: $1"; }
assert_success() { "$@" || fail "expected success: $*"; }
assert_failure() { if "$@"; then fail "expected failure: $*"; fi }

assert_log_contains() { assert_contains "$(cat "$SHIM_LOG" 2>/dev/null || true)" "$1"; }
assert_log_not_contains() { assert_not_contains "$(cat "$SHIM_LOG" 2>/dev/null || true)" "$1"; }

# Create an isolated sandbox: a temporary HOME, a shim PATH, and a project git
# repository. Leaves the shell cd'd into the project.
mk_env() {
  SB=$(mktemp -d)
  mkdir -p "$SB/home/.config/kit"
  export SB
  export HOME="$SB/home"
  export SHIM_LOG="$SB/log"
  export SHELL=/bin/bash
  : >"$SHIM_LOG"
  export PATH="$SHIMDIR:$PATH"
  unset EDITOR VISUAL 2>/dev/null || true
  mkdir -p "$SB/proj"
  (
    cd "$SB/proj" || exit 1
    git init -q .
    git config user.email test@example.com
    git config user.name Test
    git commit -q --allow-empty -m init
  )
  cd "$SB/proj" || exit 1
}

# Commit everything currently in the project.
project_commit() {
  git -C "$SB/proj" add -A
  git -C "$SB/proj" commit -q -m "${1:-commit}"
}

run_kwt() { "$KW" "$@"; }
