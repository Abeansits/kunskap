#!/usr/bin/env bats
# CLI-surface tests for `bin/kunskap recall`. Pure shell — no LLM, no auth.

load helpers

setup() {
  setup_proj_xdg
  # recall is identity-independent (P5 §8) but the marker-fallback path
  # exercises `learn enable` which still needs an identity.
  write_identity_toml "$TMPXDG" fixture bats
}

teardown() {
  cleanup_temp_dirs TMPPROJ TMPXDG TMPVAULT
}

# ---------- argument parsing ----------

@test "recall errors when query is missing" {
  run "$KUNSKAP_BIN" recall
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"missing <query>"* ]]
}

@test "recall --vault rejects relative path" {
  run "$KUNSKAP_BIN" recall foo --vault relative/dir
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"absolute path"* ]]
}

@test "recall --vault dies if path missing" {
  run "$KUNSKAP_BIN" recall foo --vault /nonexistent/path
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"vault path not found"* ]]
}

@test "recall --vault dies if _meta/kunskap.toml missing" {
  empty="$(mktemp -d)"
  mkdir -p "$empty/raw/inbox"
  run "$KUNSKAP_BIN" recall foo --vault "$empty"
  rm -rf "$empty"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"_meta/kunskap.toml"* ]]
}

@test "recall --vault dies if wiki/ missing (Stage 1 needs it)" {
  empty="$(mktemp -d)"
  mkdir -p "$empty/_meta" "$empty/raw/inbox"
  echo "[vault]" > "$empty/_meta/kunskap.toml"
  run "$KUNSKAP_BIN" recall foo --vault "$empty"
  rm -rf "$empty"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"missing wiki/"* ]]
}

@test "recall --format only accepts text|json" {
  TMPVAULT="$(make_temp_vault)"
  run "$KUNSKAP_BIN" recall foo --vault "$TMPVAULT" --format yaml
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"--format must be text or json"* ]]
}

@test "recall --limit must be a positive integer" {
  TMPVAULT="$(make_temp_vault)"
  run "$KUNSKAP_BIN" recall foo --vault "$TMPVAULT" --limit abc
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"--limit must be a positive integer"* ]]
}

@test "recall --limit 0 is rejected (avoids 'matches found but exit 1' confusion)" {
  TMPVAULT="$(make_temp_vault)"
  run "$KUNSKAP_BIN" recall foo --vault "$TMPVAULT" --limit 0
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"--limit must be a positive integer"* ]]
}

@test "recall rejects unknown flags" {
  TMPVAULT="$(make_temp_vault)"
  run "$KUNSKAP_BIN" recall foo --vault "$TMPVAULT" --bogus
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"unknown flag"* ]]
}

# ---------- vault resolution (flag + marker fallback) ----------

@test "recall without --vault errors when no project marker" {
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" recall foo
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"no --vault"* || "$output" == *"no project marker"* ]]
}

@test "recall resolves vault from project marker (.claude/kunskap.json)" {
  TMPVAULT="$(make_temp_vault)"
  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$TMPVAULT" >/dev/null
  run "$KUNSKAP_BIN" recall "set -e"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"bash-discipline.md"* ]]
}

# ---------- Stage 1 (rg) behavioral ----------

@test "recall finds hits in wiki/" {
  TMPVAULT="$(make_temp_vault)"
  run "$KUNSKAP_BIN" recall "set -e" --vault "$TMPVAULT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"wiki/learnings/bash-discipline.md"* ]]
}

@test "recall finds hits in raw/inbox/" {
  TMPVAULT="$(make_temp_vault)"
  run "$KUNSKAP_BIN" recall "Bash assignment-substitution" --vault "$TMPVAULT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"raw/inbox/"* ]]
}

@test "recall returns exit 1 on no hits with helpful stderr" {
  TMPVAULT="$(make_temp_vault)"
  run "$KUNSKAP_BIN" recall "absolutely-nonexistent-zzz" --vault "$TMPVAULT"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"no hits"* ]]
}

@test "recall --author filters to exact frontmatter match" {
  TMPVAULT="$(make_temp_vault)"
  run "$KUNSKAP_BIN" recall "two-pass" --vault "$TMPVAULT" --author "fixture@bats" --format json
  [[ "$status" -eq 0 ]]
  # Every returned hit must have author = fixture@bats (not the agent author).
  all_match="$(echo "$output" | jq '[.hits[] | .author == "fixture@bats"] | all')"
  [[ "$all_match" == "true" ]]
}

@test "recall handles single-quoted frontmatter author + tags" {
  TMPVAULT="$(make_temp_vault)"
  cat > "$TMPVAULT/wiki/learnings/_quote-fixture.md" <<'EOF'
---
type: learning
author: 'alice'
tags: ['bash', 'gotcha']
---
single-quoted-fm-needle
EOF
  ( cd "$TMPVAULT" && git add . && git -c user.email=t@l -c user.name=t commit -q -m quotes )
  run "$KUNSKAP_BIN" recall "single-quoted-fm-needle" --vault "$TMPVAULT" --author alice --format json
  [[ "$status" -eq 0 ]]
  count="$(echo "$output" | jq '.hits | length')"
  [[ "$count" -ge 1 ]]
  run "$KUNSKAP_BIN" recall "single-quoted-fm-needle" --vault "$TMPVAULT" --tag bash --format json
  [[ "$status" -eq 0 ]]
  count="$(echo "$output" | jq '.hits | length')"
  [[ "$count" -ge 1 ]]
}

@test "recall preserves apostrophes inside quoted frontmatter values" {
  TMPVAULT="$(make_temp_vault)"
  cat > "$TMPVAULT/wiki/learnings/_apostrophe-fixture.md" <<'EOF'
---
type: learning
tags: ["O'Reilly", "beta"]
---
apostrophe-needle
EOF
  ( cd "$TMPVAULT" && git add . && git -c user.email=t@l -c user.name=t commit -q -m apos )
  # Naive `gsub(/["\047]/, "")` would parse the tag as "OReilly" and miss
  # `--tag O'Reilly` (Codex Pass 2 SHOULD-FIX: matching-pair stripping).
  run "$KUNSKAP_BIN" recall "apostrophe-needle" --vault "$TMPVAULT" --tag "O'Reilly" --format json
  [[ "$status" -eq 0 ]]
  count="$(echo "$output" | jq '.hits | length')"
  [[ "$count" -ge 1 ]]
}

@test "recall accepts unquoted multi-word query (joins positional tokens)" {
  TMPVAULT="$(make_temp_vault)"
  cat > "$TMPVAULT/wiki/learnings/_phrase-fixture.md" <<'EOF'
---
type: learning
---
machine learning notes go here
EOF
  ( cd "$TMPVAULT" && git add . && git -c user.email=t@l -c user.name=t commit -q -m phrase )
  # `kunskap recall machine learning --vault X` (no quotes around the
  # phrase) should join positional tokens into "machine learning"
  # (Codex Pass 2 SHOULD-FIX: ergonomics for unquoted phrases).
  run "$KUNSKAP_BIN" recall machine learning --vault "$TMPVAULT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"_phrase-fixture.md"* ]]
}

@test "recall --tag filters by frontmatter tags membership" {
  TMPVAULT="$(make_temp_vault)"
  run "$KUNSKAP_BIN" recall "set -e" --vault "$TMPVAULT" --tag bash --format json
  [[ "$status" -eq 0 ]]
  all_match="$(echo "$output" | jq '[.hits[] | .tags | index("bash") != null] | all')"
  [[ "$all_match" == "true" ]]
}

@test "recall --limit truncates result count" {
  TMPVAULT="$(make_temp_vault)"
  run "$KUNSKAP_BIN" recall "set -e" --vault "$TMPVAULT" --limit 2 --format json
  [[ "$status" -eq 0 ]]
  count="$(echo "$output" | jq '.hits | length')"
  [[ "$count" -le 2 ]]
}

@test "recall --format json emits valid {hits: [...]} structure" {
  TMPVAULT="$(make_temp_vault)"
  run "$KUNSKAP_BIN" recall "set -e" --vault "$TMPVAULT" --format json
  [[ "$status" -eq 0 ]]
  shape="$(echo "$output" | jq -r 'if has("hits") and (.hits | type == "array") then "ok" else "bad" end')"
  [[ "$shape" == "ok" ]]
  # Each hit has the documented fields.
  every="$(echo "$output" | jq '[.hits[] | has("path") and has("line") and has("snippet") and has("score")] | all')"
  [[ "$every" == "true" ]]
}

@test "recall --format json on no hits emits {hits: []}" {
  TMPVAULT="$(make_temp_vault)"
  run "$KUNSKAP_BIN" recall "absolutely-nonexistent-zzz" --vault "$TMPVAULT" --format json
  [[ "$status" -eq 1 ]]
  count="$(echo "$output" | jq '.hits | length')"
  [[ "$count" -eq 0 ]]
}

# ---------- read-only invariant ----------

@test "recall does not modify the vault (porcelain + HEAD oid pair)" {
  TMPVAULT="$(make_temp_vault)"
  before_status="$(git -C "$TMPVAULT" status --porcelain --untracked-files=all)"
  before_head="$(git -C "$TMPVAULT" rev-parse HEAD)"
  "$KUNSKAP_BIN" recall "set -e" --vault "$TMPVAULT" --format json >/dev/null
  after_status="$(git -C "$TMPVAULT" status --porcelain --untracked-files=all)"
  after_head="$(git -C "$TMPVAULT" rev-parse HEAD)"
  [[ "$before_status" == "$after_status" ]]
  [[ "$before_head" == "$after_head" ]]
}

# ---------- Stage 2 (Obsidian CLI) graceful skip ----------

@test "recall works when Obsidian binary is not on PATH (Stage 2 graceful skip)" {
  # CI runners don't have Obsidian. Stage-2 detection must return cleanly
  # and Stage-1 (rg) must carry the load. Test by stripping PATH to bare
  # minimum (rg + jq still need to be reachable, so probe for them).
  TMPVAULT="$(make_temp_vault)"
  rg_path="$(command -v rg)"
  jq_path="$(command -v jq)"
  rg_dir="$(dirname "$rg_path")"
  jq_dir="$(dirname "$jq_path")"
  run env PATH="/usr/bin:/bin:$rg_dir:$jq_dir" "$KUNSKAP_BIN" recall "set -e" --vault "$TMPVAULT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"bash-discipline.md"* ]]
}

@test "recall errors clearly when rg is missing" {
  TMPVAULT="$(make_temp_vault)"
  run env PATH="/usr/bin:/bin" "$KUNSKAP_BIN" recall foo --vault "$TMPVAULT"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"\`rg\` not on PATH"* ]]
}

# ---------- CLI shape (source-level invariants) ----------

@test "cmd_recall enforces self-state (vault) before external (rg) check" {
  # P1 §5 self-state-before-external — a missing vault is actionable
  # without any tooling. Keep this source-shape test (load-bearing
  # cross-cutting invariant); drop the `--fixed-strings` and `|| true`
  # source-grep tests they used to pair with — those are covered
  # behaviorally by the no-hits-on-no-match and dash-in-query tests.
  body="$(fn_body cmd_recall)"
  vault_line="$(echo "$body" | grep -n 'validate_vault' | head -1 | cut -d: -f1)"
  rg_line="$(echo "$body" | grep -n 'command -v rg' | head -1 | cut -d: -f1)"
  [[ -n "$vault_line" && -n "$rg_line" ]]
  [[ "$vault_line" -lt "$rg_line" ]]
}

@test "recall handles regex metachars literally (--fixed-strings)" {
  TMPVAULT="$(make_temp_vault)"
  # Seed a file containing a regex-invalid string. Without --fixed-strings,
  # `a[b` is an unclosed character class that rg rejects with status 2 →
  # the rg-status-1-tolerance guard would die. With --fixed-strings, the
  # literal is found. This test fails for the right reason if the flag
  # regresses (Codex Pass 1 SHOULD-FIX: weak prior assertion).
  cat > "$TMPVAULT/wiki/learnings/_metachar-fixture.md" <<'EOF'
---
type: learning
---
contains a[b literal
EOF
  ( cd "$TMPVAULT" && git add . && git -c user.email=t@l -c user.name=t commit -q -m metachar )
  run "$KUNSKAP_BIN" recall "a[b" --vault "$TMPVAULT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"_metachar-fixture.md"* ]]
}

@test "recall surfaces rg failures (>1) instead of swallowing them as no-hits" {
  TMPVAULT="$(make_temp_vault)"
  chmod 000 "$TMPVAULT/wiki"
  run "$KUNSKAP_BIN" recall "anything" --vault "$TMPVAULT"
  chmod 755 "$TMPVAULT/wiki"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"rg failed"* ]]
}
