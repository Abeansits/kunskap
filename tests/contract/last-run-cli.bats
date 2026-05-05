#!/usr/bin/env bats
# P5 — _meta/last-run/linter.json whitelist enforcement on the CLI side.
#
# The linter agent is permitted exactly ONE write inside the vault:
# `_meta/last-run/linter.json`. Every other path is a contract violation and the
# CLI's authoritative invariant check (see bin/kunskap cmd_lint) refuses.
# This suite asserts the source-level shape of that whitelist; behavioral
# verification (a real linter run) lives in linter-behavioral.bats.

load helpers

# ---------- source surface (catches refactor regressions) ----------

@test "cmd_lint whitelist mentions _meta/last-run/linter.json by name" {
  fn_body cmd_lint | grep -q '"_meta/last-run/linter.json"'
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

@test "agents/linter.md describes the run-record write to _meta/last-run/linter.json" {
  linter_prompt_contains "_meta/last-run/linter.json"
  linter_prompt_contains "MUST 9"
}

@test "agents/linter.md MUST NOT touch the curator-owned shard" {
  linter_prompt_contains "_meta/last-run/curator.json"
  linter_prompt_contains "curator-owned"
}

@test "agents/curator.md final step writes _meta/last-run/curator.json" {
  prompt_contains "curator run record"
  prompt_contains "_meta/last-run/curator.json"
}

@test "agents/curator.md sharded layout preserves \"no shared file\" §Q4 invariant" {
  prompt_contains "sharded per-role"
  prompt_contains "no shared file"
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
