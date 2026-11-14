#!/usr/bin/env bash
# 08: Domain documentation — CONTEXT.md and the sandbox-policy ADR.
. "$(dirname "$0")/lib.sh"

t_context_glossary() {
  assert_file "$ROOT/CONTEXT.md"
  local c
  c=$(cat "$ROOT/CONTEXT.md")
  local term
  for term in "Target directory" Sandbox "agent session" Project; do
    assert_contains "$c" "$term"
  done
}

t_context_is_glossary_only() {
  local c
  c=$(cat "$ROOT/CONTEXT.md")
  assert_not_contains "$c" 'bwrap --'
  assert_not_contains "$c" 'git worktree add'
}

t_adr_records_sandbox_policy() {
  local f
  f=$(ls "$ROOT"/docs/adr/*sandbox* 2>/dev/null | head -1)
  [ -n "$f" ] || fail "sandbox-policy ADR is missing"
  local c
  c=$(cat "$f")
  assert_contains "$c" "read-only"
  assert_contains "$c" "--no-daemon"
  assert_contains "$c" "bwrap"
  assert_contains "$c" "Alternatives"
}

run_test "CONTEXT.md defines the glossary terms" t_context_glossary
run_test "CONTEXT.md is a glossary, not implementation detail" t_context_is_glossary_only
run_test "the ADR records the sandbox policy and alternatives" t_adr_records_sandbox_policy

finish
