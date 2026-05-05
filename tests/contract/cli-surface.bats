#!/usr/bin/env bats
# CLI-surface tests for bin/kunskap curate / link-stubs / audit-coverage.
# No LLM, no auth. Exercises arg parsing, vault validation, and the two
# pure-shell primitives against the fixture vault.

load helpers

# CLI tests are read-only against TMPVAULT — build it once per file and share.
setup_file() {
  TMPVAULT="$(make_temp_vault)"
  export TMPVAULT
}

teardown_file() {
  if [[ -n "${TMPVAULT:-}" && -d "$TMPVAULT" ]]; then rm -rf "$TMPVAULT"; fi
}

# ---------- curate (validation only, no agent spawn) ----------

@test "curate --vault required" {
  run "$KUNSKAP_BIN" curate
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"--vault"* ]]
}

@test "curate --vault must be absolute" {
  run "$KUNSKAP_BIN" curate --vault relative/path
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"absolute path"* ]]
}

@test "curate --vault rejects flag-as-value" {
  run "$KUNSKAP_BIN" curate --vault --check
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"got next flag"* ]]
}

@test "curate --vault dies if path missing" {
  run "$KUNSKAP_BIN" curate --vault /nonexistent/path
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"vault path not found"* ]]
}

@test "curate --vault dies if _meta/kunskap.toml missing" {
  empty="$(mktemp -d)"
  mkdir -p "$empty/raw/inbox"
  run "$KUNSKAP_BIN" curate --vault "$empty"
  rm -rf "$empty"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"_meta/kunskap.toml"* ]]
}

@test "curate --vault dies if raw/inbox/ missing" {
  empty="$(mktemp -d)"
  mkdir -p "$empty/_meta"
  echo "[vault]" > "$empty/_meta/kunskap.toml"
  run "$KUNSKAP_BIN" curate --vault "$empty"
  rm -rf "$empty"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"raw/inbox/"* ]]
}

@test "curate --vault dies if wiki/ missing" {
  empty="$(mktemp -d)"
  mkdir -p "$empty/_meta" "$empty/raw/inbox"
  echo "[vault]" > "$empty/_meta/kunskap.toml"
  run "$KUNSKAP_BIN" curate --vault "$empty"
  rm -rf "$empty"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"missing wiki/"* ]]
}

@test "curate --check passes on a healthy vault" {
  run "$KUNSKAP_BIN" curate --vault "$TMPVAULT" --check
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"healthy"* ]]
}

@test "curate rejects unknown extra args" {
  run "$KUNSKAP_BIN" curate --vault "$TMPVAULT" --check --bogus
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"unknown extra args"* ]]
}

@test "curate via symlink shim still resolves the plugin root" {
  # Block-ship Pass-2 fix: plugin_root() must follow symlinks.
  shim_dir="$(mktemp -d)"
  ln -s "$KUNSKAP_BIN" "$shim_dir/kunskap"
  run "$shim_dir/kunskap" curate --vault "$TMPVAULT" --check
  rm -rf "$shim_dir"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"healthy"* ]]
}

@test "curate dies with a clear error when the agent file is missing" {
  fake_root="$(mktemp -d)"
  CLAUDE_PLUGIN_ROOT="$fake_root" run "$KUNSKAP_BIN" curate --vault "$TMPVAULT"
  rm -rf "$fake_root"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"curator agent not found"* ]]
}

# ---------- link-stubs ----------

@test "link-stubs --vault required" {
  run "$KUNSKAP_BIN" link-stubs
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"--vault"* ]]
}

@test "link-stubs --format only accepts text|json" {
  run "$KUNSKAP_BIN" link-stubs --vault "$TMPVAULT" --format yaml
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"--format must be text or json"* ]]
}

@test "link-stubs text output buckets the four categories" {
  run "$KUNSKAP_BIN" link-stubs --vault "$TMPVAULT" --format text
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Multi-ref stubs"* ]]
  [[ "$output" == *"Single-ref orphans"* ]]
  [[ "$output" == *"Name-mismatch"* ]]
  [[ "$output" == *"Resolved links"* ]]
}

@test "link-stubs json output is valid JSON with the four buckets" {
  run "$KUNSKAP_BIN" link-stubs --vault "$TMPVAULT" --format json
  [[ "$status" -eq 0 ]]
  echo "$output" | jq -e '.resolved' >/dev/null
  echo "$output" | jq -e '."needs-alias"' >/dev/null
  echo "$output" | jq -e '."needs-stub"' >/dev/null
  echo "$output" | jq -e '.orphan' >/dev/null
}

@test "link-stubs detects pre-existing resolved links in the fixture" {
  # The fixture _index.md links to the four pre-curated articles by their
  # kebab-case filenames; all should resolve.
  run "$KUNSKAP_BIN" link-stubs --vault "$TMPVAULT" --format json
  [[ "$status" -eq 0 ]]
  count=$(echo "$output" | jq '.resolved | length')
  [[ "$count" -ge 4 ]]
}

@test "link-stubs classifies natural-language link as needs-alias when kebab matches" {
  # Build a throwaway vault: a single article whose body links to
  # [[two-pass codex review]], with file `two-pass-codex-review.md` present
  # but NOT carrying that alias in frontmatter. Per design §200, this should
  # be classified as needs-alias (curator action item), not resolved.
  alias_vault="$(mktemp -d)"
  mkdir -p "$alias_vault/_meta" "$alias_vault/raw/inbox" "$alias_vault/wiki/learnings"
  echo "[vault]" > "$alias_vault/_meta/kunskap.toml"
  cat > "$alias_vault/wiki/learnings/two-pass-codex-review.md" <<'EOF'
---
type: learning
---
Body.
EOF
  cat > "$alias_vault/wiki/learnings/uses-it.md" <<'EOF'
---
type: learning
---
This refs [[two-pass codex review]] in prose.
EOF
  run "$KUNSKAP_BIN" link-stubs --vault "$alias_vault" --format json
  rm -rf "$alias_vault"
  [[ "$status" -eq 0 ]]
  needs=$(echo "$output" | jq -r '."needs-alias"[0].link')
  [[ "$needs" == "two-pass codex review" ]]
}

@test "link-stubs ignores body --- separators when extracting wikilinks" {
  # Pass-1 finding: a body line of exactly "---" used to flip frontmatter
  # state back on, suppressing wikilink extraction afterward.
  sep_vault="$(mktemp -d)"
  mkdir -p "$sep_vault/_meta" "$sep_vault/raw/inbox" "$sep_vault/wiki/learnings"
  echo "[vault]" > "$sep_vault/_meta/kunskap.toml"
  cat > "$sep_vault/wiki/learnings/with-separator.md" <<'EOF'
---
type: learning
---

# Above the rule

[[link-before]]

---

[[link-after-the-rule]]
EOF
  run "$KUNSKAP_BIN" link-stubs --vault "$sep_vault" --format json
  rm -rf "$sep_vault"
  [[ "$status" -eq 0 ]]
  echo "$output" | jq -e '.orphan | map(.link) | index("link-after-the-rule")' >/dev/null
}

# ---------- audit-coverage ----------

@test "audit-coverage --vault required" {
  run "$KUNSKAP_BIN" audit-coverage
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"--vault"* ]]
}

@test "audit-coverage flags inbox files not yet cited (silent drops)" {
  # Pre-curator state: nothing in raw/inbox/ is cited yet; expected to flag
  # every inbox file. Match dynamically against the actual fixture count so
  # adding a fixture note doesn't drift this assertion.
  expected=$(find "$FIXTURE_VAULT/raw/inbox" -name '*.md' | wc -l | tr -d ' ')
  run "$KUNSKAP_BIN" audit-coverage --vault "$TMPVAULT" --format json
  [[ "$status" -eq 2 ]]   # exits 2 when there are findings
  drops=$(echo "$output" | jq '.silent_drops | length')
  [[ "$drops" -eq "$expected" ]]
}

@test "audit-coverage covered_count reflects archive entries cited in fixture wiki" {
  run "$KUNSKAP_BIN" audit-coverage --vault "$TMPVAULT" --format json
  [[ "$status" -eq 2 ]]
  cov=$(echo "$output" | jq '.covered_count')
  # Fixture wiki articles cite 8 archive entries that exist.
  [[ "$cov" -ge 4 ]]
}

@test "audit-coverage exits 0 when nothing is wrong" {
  empty="$(mktemp -d)"
  mkdir -p "$empty/_meta" "$empty/raw/inbox" "$empty/wiki/learnings"
  echo "[vault]" > "$empty/_meta/kunskap.toml"
  run "$KUNSKAP_BIN" audit-coverage --vault "$empty"
  rm -rf "$empty"
  [[ "$status" -eq 0 ]]
}

# ---------- fixture sanity ----------

@test "fixture vault includes the 9 baseline + adversarial inbox notes" {
  count=$(find "$TMPVAULT/raw/inbox" -name '*.md' | wc -l | tr -d ' ')
  [[ "$count" -ge 9 ]]
  # Adversarial fixtures (P1-deferred, folded into P2) — prose-label vs body
  # disagreement, asserted-by-policy in behavioral.bats.
  adv=$(find "$TMPVAULT/raw/inbox" -name '*adversarial*.md' | wc -l | tr -d ' ')
  [[ "$adv" -eq 2 ]]
}

@test "fixture vault hand-edit trap article carries the HUMAN HAND-EDIT marker" {
  grep -q "HUMAN HAND-EDIT" "$TMPVAULT/wiki/learnings/worktree-discipline.md"
}

@test "fixture vault Lane-2-with-invitation target carries the Revisit footer" {
  grep -q "Revisit on 5th confirmation" "$TMPVAULT/wiki/learnings/two-pass-codex-review.md"
}
