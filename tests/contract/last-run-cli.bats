#!/usr/bin/env bats
# P5 — _meta/last-run.json whitelist enforcement on the CLI side.
#
# The linter agent is permitted exactly ONE write inside the vault:
# `_meta/last-run.json`. Every other path is a contract violation and the
# CLI's authoritative invariant check (see bin/kunskap cmd_lint) refuses.
# This suite asserts the source-level shape of that whitelist; behavioral
# verification (a real linter run) lives in linter-behavioral.bats.

load helpers

# ---------- source surface (catches refactor regressions) ----------

@test "cmd_lint whitelist mentions _meta/last-run.json by name" {
  fn_body cmd_lint | grep -q '"_meta/last-run.json"'
}

@test "cmd_lint whitelist comment names P5 + the SOLE permitted exception" {
  fn_body cmd_lint | grep -q 'P5'
  fn_body cmd_lint | grep -q 'SOLE'
}

@test "cmd_lint whitelist enumerates BOTH commit-side AND porcelain-side touched paths" {
  # Both paths must be checked — a write+commit cycle bypasses pure-porcelain
  # whitelisting (P4 §3 head-oid lesson).
  fn_body cmd_lint | grep -q 'log --name-only'
  fn_body cmd_lint | grep -q 'comm -13'   # diff before/after porcelain
}

@test "cmd_lint whitelist returns exit 2 (invariant violation) on disallowed path" {
  fn_body cmd_lint | grep -q 'return 2'
}

@test "cmd_lint emits a stderr message naming the disallowed paths in the diagnostic" {
  fn_body cmd_lint | grep -q 'Disallowed paths touched'
}

# ---------- agent-prompt-side: linter MUST 9 + curator step 6 ----------

@test "agents/linter.md describes the run-record write to _meta/last-run.json" {
  linter_prompt_contains "_meta/last-run.json"
  linter_prompt_contains "MUST 9"
}

@test "agents/linter.md preserves the curator section via jq merge" {
  linter_prompt_contains "Preserve any existing"
  linter_prompt_contains "curator"
}

@test "agents/curator.md final step writes _meta/last-run.json#curator" {
  prompt_contains "curator run record"
  prompt_contains "_meta/last-run.json"
}

@test "agents/curator.md preserves the linter section via jq merge" {
  prompt_contains "preserving any existing \`linter\` block"
}

@test "agents/curator.md final step records inbox_processed / articles_written / drafts_routed" {
  prompt_contains "inbox_processed"
  prompt_contains "articles_written"
  prompt_contains "drafts_routed"
}

# ---------- directive prompt threads identity + head_before + forced ----------

@test "cmd_curate directive prompt threads identity to the curator agent" {
  fn_body cmd_curate | grep -q 'by: \\"\$identity\\"'
}

@test "cmd_curate directive prompt threads head_before from rev-parse HEAD" {
  fn_body cmd_curate | grep -q 'head_before='
  fn_body cmd_curate | grep -q 'rev-parse HEAD'
}

@test "cmd_curate directive prompt threads forced (true|false) for audit trail" {
  fn_body cmd_curate | grep -q 'forced_json'
}

@test "cmd_lint directive prompt threads identity + forced for the run-record" {
  fn_body cmd_lint | grep -q 'by: \\"\$identity\\"'
  fn_body cmd_lint | grep -q 'forced: \$forced_json'
}
