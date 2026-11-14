#!/usr/bin/env bash
# 01: Foundation — directory resolution and the --dry-run plan.
. "$(dirname "$0")/lib.sh"

t_dry_run_prints_the_resolved_dir() {
  mk_env
  out=$(run_kwt . --dry-run)
  assert_contains "$out" "dir $SB/proj"
}

t_relative_dir_resolves_to_absolute() {
  mk_env
  mkdir -p sub
  out=$(cd sub && run_kwt .. --dry-run)
  assert_contains "$out" "dir $SB/proj"
}

t_dry_run_from_subdir_targets_the_subdir() {
  mk_env
  mkdir -p a/b
  out=$(run_kwt a/b --dry-run)
  assert_contains "$out" "dir $SB/proj/a/b"
}

t_dry_run_performs_no_side_effects() {
  mk_env
  run_kwt . --dry-run >/dev/null
  assert_log_not_contains "bwrap"
  assert_log_not_contains "kit"
  assert_eq "$(git -C "$SB/proj" status --porcelain)" ""
}

t_missing_dir_fails() {
  mk_env
  if out=$(run_kwt nope --dry-run 2>&1); then fail "expected failure"; fi
  assert_contains "$out" "not a directory"
}

t_root_dir_refused() {
  mk_env
  if out=$(run_kwt / --dry-run 2>&1); then fail "expected failure"; fi
  assert_contains "$out" "refusing to sandbox the filesystem root"
}

t_bare_invocation_defaults_to_current_dir() {
  mk_env
  out=$(run_kwt --dry-run)
  assert_contains "$out" "dir $SB/proj"
}

t_bare_invocation_runs_kit() {
  mk_env
  : >"$SHIM_LOG"
  run_kwt >/dev/null
  assert_log_contains "bwrap"
  assert_log_contains "kit --no-daemon --no-session"
}

t_argument_parsing() {
  mk_env
  out=$(run_kwt . --allow-git-write --dry-run)
  assert_contains "$out" "--bind $SB/proj/.git $SB/proj/.git"

  out=$(run_kwt . --dry-run -- "hello world")
  assert_contains "$out" "kit --no-daemon --no-session hello\\ world"
}

t_unknown_option_fails() {
  mk_env
  if out=$(run_kwt . --nope 2>&1); then fail "expected failure"; fi
  assert_contains "$out" "unknown option"
}

run_test "dry-run prints the resolved directory" t_dry_run_prints_the_resolved_dir
run_test "a relative directory resolves to an absolute path" t_relative_dir_resolves_to_absolute
run_test "a subdirectory target is resolved as given" t_dry_run_from_subdir_targets_the_subdir
run_test "dry-run performs no side effects" t_dry_run_performs_no_side_effects
run_test "a missing directory fails clearly" t_missing_dir_fails
run_test "the filesystem root is refused" t_root_dir_refused
run_test "bare kwt defaults to the current directory" t_bare_invocation_defaults_to_current_dir
run_test "bare kwt runs kit in the current directory" t_bare_invocation_runs_kit
run_test "argument parsing accepts the documented flags" t_argument_parsing
run_test "unknown options fail" t_unknown_option_fails

finish
