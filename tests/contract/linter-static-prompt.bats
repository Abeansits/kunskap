#!/usr/bin/env bats
# Static prompt-content tests for agents/linter.md.
#
# Mirror of static-prompt.bats for the curator: each MUST / MUST-NOT clause
# in the linter contract maps to a literal-string presence check in
# agents/linter.md. P1 vault learning §1: catches prompt drift in CI; cheap
# to run, no LLM call. Drift simulation: deleting a clause from
# agents/linter.md fails exactly the corresponding test.

load helpers

setup() {
  [[ -f "$LINTER_AGENT" ]] || skip "agents/linter.md missing"
}

# ---------- frontmatter shape (canonical agents reference) ----------

@test "frontmatter declares name: linter" {
  grep -E "^name: linter$" "$LINTER_AGENT"
}

@test "frontmatter declares model: opus" {
  grep -E "^model: opus$" "$LINTER_AGENT"
}

@test "frontmatter tools list grants Read/Bash/Glob/Grep (read-only)" {
  grep -E "^tools: " "$LINTER_AGENT" | grep -F "Read"
  grep -E "^tools: " "$LINTER_AGENT" | grep -F "Bash"
  grep -E "^tools: " "$LINTER_AGENT" | grep -F "Glob"
  grep -E "^tools: " "$LINTER_AGENT" | grep -F "Grep"
}

@test "frontmatter disallowedTools forbids Write + Edit (read-only invariant)" {
  grep -E "^disallowedTools:.*Write" "$LINTER_AGENT"
  grep -E "^disallowedTools:.*Edit" "$LINTER_AGENT"
}

@test "frontmatter disallowedTools forbids WebFetch + WebSearch (closed-world)" {
  grep -E "^disallowedTools:.*WebFetch" "$LINTER_AGENT"
  grep -E "^disallowedTools:.*WebSearch" "$LINTER_AGENT"
}

@test "frontmatter omits permissionMode/hooks/mcpServers (plugin agents don't support these)" {
  ! grep -E "^permissionMode:" "$LINTER_AGENT"
  ! grep -E "^hooks:" "$LINTER_AGENT"
  ! grep -E "^mcpServers:" "$LINTER_AGENT"
}

# ---------- read-only invariant (the discipline anchor) ----------

@test "read-only invariant declared up front" {
  linter_prompt_contains "You are read-only"
  linter_prompt_contains "Curator writes; linter audits"
}

@test "MUST 8 — read-only invariant named explicitly + git status check" {
  linter_prompt_contains "MUST 8 — read-only invariant"
  linter_prompt_contains "git status --porcelain"
}

@test "MUST NOT — explicit prohibition on auto-fix" {
  linter_prompt_contains "auto-fix any drift"
}

@test "MUST NOT — explicit prohibition on modifying any file" {
  linter_prompt_contains "modify any file"
}

# ---------- output format contract ----------

@test "MUST 7 — finding shape \`[TYPE] path | message\` is mandated" {
  linter_prompt_contains "[TYPE] path | message"
}

@test "MUST 7 — path/severity/suggested-action triple is required" {
  linter_prompt_contains "path/severity/suggested-action triple"
  linter_prompt_contains "Never emit one"
}

@test "MUST 7 — JSON mode shape spelled out (findings array, structured records)" {
  linter_prompt_contains "findings: [...]"
  linter_prompt_contains "{type, severity, path, message, suggested_action}"
}

@test "MUST 7 — text-mode grouping by severity declared" {
  linter_prompt_contains "Group human-readable text output by severity"
}

# ---------- MUST clauses (each finding type has its own fingerprint) ----------

@test "MUST 1 — DRIFT finding type is mandated" {
  linter_prompt_contains "[DRIFT]"
  linter_prompt_contains "find drift across articles"
}

@test "MUST 1 — DRIFT must NOT auto-resolve, only surface" {
  linter_prompt_contains "Do NOT auto-resolve"
}

@test "MUST 2 — STUB-CLUSTER finding type is mandated" {
  linter_prompt_contains "[STUB-CLUSTER]"
}

@test "MUST 2 — stub-cluster threshold is 3+ references (not 2; that's curator's job)" {
  linter_prompt_contains "3 or more references"
  linter_prompt_contains "2-reference threshold is the curator's job"
}

@test "MUST 2 — stub-discovery recipe lifted verbatim from v0 §6" {
  linter_prompt_contains "grep -roh '\\[\\[[^]]*\\]\\]'"
  linter_prompt_contains "sort | uniq -c | sort -rn"
}

@test "MUST 2 — kunskap link-stubs --format json is the preferred path" {
  linter_prompt_contains "kunskap link-stubs"
  linter_prompt_contains "--format json"
}

@test "MUST 3 — DRAFT-STALE + DRAFT-DEFERRED-STALE finding types are mandated" {
  linter_prompt_contains "[DRAFT-STALE]"
  linter_prompt_contains "[DRAFT-DEFERRED-STALE]"
}

@test "MUST 3 — staleness thresholds spelled out (7d created, 14d deferred)" {
  linter_prompt_contains "≥ 7 days ago"
  linter_prompt_contains "≥ 14 days ago"
}

@test "MUST 4 — OFFLINE-ARRIVAL finding type + Risk #4 named" {
  linter_prompt_contains "[OFFLINE-ARRIVAL]"
  linter_prompt_contains "Risk #4"
}

@test "MUST 4 — last-run.json#curator.by + 48h threshold spelled out" {
  linter_prompt_contains "_meta/last-run.json"
  linter_prompt_contains "curator.by"
  linter_prompt_contains "≥ 48 hours"
}

@test "MUST 5 — CURATOR-IDLE finding type + 48h threshold" {
  linter_prompt_contains "[CURATOR-IDLE]"
  linter_prompt_contains "ran_at"
}

@test "MUST 6 — IDENTITY-MISMATCH finding type + roles.toml + git log" {
  linter_prompt_contains "[IDENTITY-MISMATCH]"
  linter_prompt_contains "_meta/roles.toml"
  linter_prompt_contains "git log --since=30.days.ago"
}

@test "MUST 6 — uses git log directly, doesn't try to parse identities itself" {
  linter_prompt_contains "Use \`git log\` directly"
}

# ---------- vault scope ($ARGUMENTS) ----------

@test "vault scope = \$ARGUMENTS, operate only inside it" {
  linter_prompt_contains "vault path is supplied to you in \`\$ARGUMENTS\`"
  linter_prompt_contains "Operate only inside that vault"
}

@test "errors clearly when \$ARGUMENTS is empty or vault is invalid" {
  linter_prompt_contains "If \`\$ARGUMENTS\` is empty"
  linter_prompt_contains "_meta/kunskap.toml"
}

# ---------- carryover discipline from prior phases ----------

@test "P3 lesson — anchor-to-NR==1 awk recipe is the canonical frontmatter parser" {
  linter_prompt_contains "anchor-to-NR==1"
  linter_prompt_contains "NR == 1 && /^---$/"
}

@test "P3 lesson — never use sed range patterns for frontmatter" {
  linter_prompt_contains "never use sed range patterns"
}

@test "P1 lesson — slash commands don't work in headless \`-p\` mode" {
  linter_prompt_contains "slash commands"
  linter_prompt_contains "interactive-mode only"
}

# ---------- MUST NOT list ----------

@test "MUST NOT — emit findings without a path/severity/suggested-action triple" {
  linter_prompt_contains "emit findings without a path/severity/suggested-action triple"
}

@test "MUST NOT — run during a curator pass" {
  linter_prompt_contains "run during a curator pass"
}

# ---------- design-doc anchors ----------

@test "Karpathy 'safety net' framing is preserved" {
  linter_prompt_contains "safety net"
}

@test "drift-collapse risk: if linter writes, curator and linter become indistinguishable" {
  linter_prompt_contains "If you ever write, the contract collapses"
}
