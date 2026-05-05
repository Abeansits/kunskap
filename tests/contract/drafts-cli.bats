#!/usr/bin/env bats
# CLI-surface tests for `bin/kunskap drafts list|show|approve|reject|defer`.
# Each test seeds a fresh vault via `kunskap init` + a couple of drafts,
# exercises one drafts subcommand, asserts the post-state.

load helpers

setup() {
  TMPPROJ="$(make_temp_proj)"
  TMPXDG="$(make_temp_xdg)"
  export TMPPROJ TMPXDG
  export XDG_CONFIG_HOME="$TMPXDG"
}

teardown() {
  cleanup_temp_dirs TMPPROJ TMPXDG TMPVAULT
}

# ---------- vault resolution ----------

@test "drafts list errors when no --vault and no project marker" {
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" drafts list
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"no --vault"* || "$output" == *"no project marker"* ]]
}

@test "drafts list resolves vault from project marker (.claude/kunskap.json)" {
  TMPVAULT="$(make_vault_with_drafts)"
  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$TMPVAULT" >/dev/null
  run "$KUNSKAP_BIN" drafts list
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"topic-alpha"* ]]
  [[ "$output" == *"topic-beta"* ]]
}

@test "drafts list with --vault overrides marker" {
  TMPVAULT="$(make_vault_with_drafts)"
  run "$KUNSKAP_BIN" drafts list --vault "$TMPVAULT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"topic-alpha"* ]]
}

@test "drafts list rejects relative --vault" {
  run "$KUNSKAP_BIN" drafts list --vault relative/dir
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"absolute path"* ]]
}

@test "drafts list rejects --format other than text|json" {
  TMPVAULT="$(make_vault_with_drafts)"
  run "$KUNSKAP_BIN" drafts list --vault "$TMPVAULT" --format yaml
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"--format must be text or json"* ]]
}

# ---------- list ----------

@test "drafts list (text) sorts oldest first and shows conf/src/age" {
  TMPVAULT="$(make_vault_with_drafts)"
  run "$KUNSKAP_BIN" drafts list --vault "$TMPVAULT"
  [[ "$status" -eq 0 ]]
  # Oldest = topic-alpha (2026-04-25). Should appear first.
  alpha_line=$(echo "$output" | grep -n 'topic-alpha' | head -1 | cut -d: -f1)
  beta_line=$(echo "$output"  | grep -n 'topic-beta'  | head -1 | cut -d: -f1)
  [[ "$alpha_line" -lt "$beta_line" ]]
  [[ "$output" == *"conf=high"* ]]
  [[ "$output" == *"conf=low"* ]]
  [[ "$output" == *"src=2"* ]]
  [[ "$output" == *"src=1"* ]]
}

@test "drafts list (json) returns valid JSON with id/slug/confidence/source_count" {
  TMPVAULT="$(make_vault_with_drafts)"
  run "$KUNSKAP_BIN" drafts list --vault "$TMPVAULT" --format json
  [[ "$status" -eq 0 ]]
  echo "$output" | jq -e 'length == 2' >/dev/null
  echo "$output" | jq -e '.[0].id == 1' >/dev/null
  echo "$output" | jq -e '.[0].slug == "topic-alpha--2026-04-25"' >/dev/null
  echo "$output" | jq -e '.[0].confidence == "high"' >/dev/null
  echo "$output" | jq -e '.[0].source_count == 2' >/dev/null
}

@test "drafts list on empty _drafts/ prints friendly no-drafts message" {
  TMPVAULT="$(mktemp -d -t kunskap-empty.XXXXXX)"
  rm -rf "$TMPVAULT"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" init "$TMPVAULT" >/dev/null
  run "$KUNSKAP_BIN" drafts list --vault "$TMPVAULT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"no drafts"* ]]
}

# ---------- show ----------

@test "drafts show resolves by 1-based id" {
  TMPVAULT="$(make_vault_with_drafts)"
  run "$KUNSKAP_BIN" drafts show 1 --vault "$TMPVAULT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"topic-alpha"* ]]
  [[ "$output" == *"Draft body proposing"* ]]
}

@test "drafts show resolves by full slug" {
  TMPVAULT="$(make_vault_with_drafts)"
  run "$KUNSKAP_BIN" drafts show "topic-beta--2026-05-01" --vault "$TMPVAULT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"unclassifiable"* ]]
}

@test "drafts show errors on out-of-range id" {
  TMPVAULT="$(make_vault_with_drafts)"
  run "$KUNSKAP_BIN" drafts show 99 --vault "$TMPVAULT"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"out of range"* ]]
}

@test "drafts show errors on no-match slug" {
  TMPVAULT="$(make_vault_with_drafts)"
  run "$KUNSKAP_BIN" drafts show no-such-slug --vault "$TMPVAULT"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"no draft matching"* ]]
}

# ---------- approve ----------

@test "drafts approve (no --into) creates new article + archives draft + single commit" {
  TMPVAULT="$(make_vault_with_drafts)"
  before=$(git -C "$TMPVAULT" rev-list --count HEAD)
  run "$KUNSKAP_BIN" drafts approve 1 --vault "$TMPVAULT"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"approved"* ]]
  [[ -f "$TMPVAULT/wiki/learnings/topic-alpha--2026-04-25.md" ]]
  [[ -f "$TMPVAULT/Archives/processed-drafts/approved/topic-alpha--2026-04-25.md" ]]
  [[ ! -f "$TMPVAULT/wiki/_drafts/topic-alpha--2026-04-25.md" ]]
  after=$(git -C "$TMPVAULT" rev-list --count HEAD)
  [[ "$after" -eq "$((before + 1))" ]]
  # Article frontmatter has type: learning, last_curated, source fields preserved.
  grep -q '^type: learning' "$TMPVAULT/wiki/learnings/topic-alpha--2026-04-25.md"
  grep -q '^last_curated:'  "$TMPVAULT/wiki/learnings/topic-alpha--2026-04-25.md"
  ! grep -q '^confidence:' "$TMPVAULT/wiki/learnings/topic-alpha--2026-04-25.md"
  ! grep -q '^reason:'     "$TMPVAULT/wiki/learnings/topic-alpha--2026-04-25.md"
}

@test "drafts approve --into appends body under dated heading" {
  TMPVAULT="$(make_vault_with_drafts)"
  # The vault's seed example-topic.md is the --into target.
  run "$KUNSKAP_BIN" drafts approve 1 --vault "$TMPVAULT" --into example-topic
  [[ "$status" -eq 0 ]]
  [[ ! -f "$TMPVAULT/wiki/_drafts/topic-alpha--2026-04-25.md" ]]
  [[ -f "$TMPVAULT/Archives/processed-drafts/approved/topic-alpha--2026-04-25.md" ]]
  grep -q "promoted from drafts/topic-alpha" "$TMPVAULT/wiki/learnings/example-topic.md"
}

@test "drafts approve --into preserves body content past horizontal-rule ---" {
  # Pass-1 block-ship: prior `sed -n '/^---$/,/^---$/!p'` negated EVERY
  # `---...---` range, silently truncating draft bodies that contained
  # markdown horizontal rules. Lock the fix.
  TMPVAULT="$(make_vault_with_drafts)"
  cat > "$TMPVAULT/wiki/_drafts/with-rule--2026-05-02.md" <<'EOF'
---
type: draft
lane: 2
confidence: high
reason: extends with example
source_count: 1
sources:
  - raw/inbox/01-foo.md
created: 2026-05-02
---

Body line before the rule.

---

Body line AFTER the rule (must survive merge).

## Recommendation

Approve into example-topic.
EOF
  ( cd "$TMPVAULT" && git add . && git -c user.email=test@local -c user.name=test commit -q -m "seed rule draft" ) >/dev/null
  run "$KUNSKAP_BIN" drafts approve with-rule --vault "$TMPVAULT" --into example-topic
  [[ "$status" -eq 0 ]]
  grep -q "Body line before the rule" "$TMPVAULT/wiki/learnings/example-topic.md"
  grep -q "Body line AFTER the rule" "$TMPVAULT/wiki/learnings/example-topic.md"
  grep -q "## Recommendation" "$TMPVAULT/wiki/learnings/example-topic.md"
}

@test "drafts approve --into errors when target doesn't exist" {
  TMPVAULT="$(make_vault_with_drafts)"
  run "$KUNSKAP_BIN" drafts approve 1 --vault "$TMPVAULT" --into no-such-article
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
  # Original draft still in place.
  [[ -f "$TMPVAULT/wiki/_drafts/topic-alpha--2026-04-25.md" ]]
}

@test "drafts approve archive copy carries approved_at + approved_into stamps" {
  TMPVAULT="$(make_vault_with_drafts)"
  "$KUNSKAP_BIN" drafts approve 1 --vault "$TMPVAULT"
  archive="$TMPVAULT/Archives/processed-drafts/approved/topic-alpha--2026-04-25.md"
  grep -q '^approved_at:'   "$archive"
  grep -q '^approved_into:' "$archive"
}

# ---------- reject ----------

@test "drafts reject without --reason errors (rejection without reason loses context)" {
  TMPVAULT="$(make_vault_with_drafts)"
  run "$KUNSKAP_BIN" drafts reject 1 --vault "$TMPVAULT"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"--reason"* ]]
  # Draft still in place — rejection didn't happen.
  [[ -f "$TMPVAULT/wiki/_drafts/topic-alpha--2026-04-25.md" ]]
}

@test "drafts reject with --reason archives draft + single commit + reason in frontmatter" {
  TMPVAULT="$(make_vault_with_drafts)"
  before=$(git -C "$TMPVAULT" rev-list --count HEAD)
  run "$KUNSKAP_BIN" drafts reject topic-beta --vault "$TMPVAULT" --reason "duplicate of existing"
  [[ "$status" -eq 0 ]]
  archive="$TMPVAULT/Archives/processed-drafts/rejected/topic-beta--2026-05-01.md"
  [[ -f "$archive" ]]
  [[ ! -f "$TMPVAULT/wiki/_drafts/topic-beta--2026-05-01.md" ]]
  grep -q 'rejection_reason:.*duplicate of existing' "$archive"
  grep -q '^rejected_at:' "$archive"
  after=$(git -C "$TMPVAULT" rev-list --count HEAD)
  [[ "$after" -eq "$((before + 1))" ]]
}

# ---------- defer ----------

@test "drafts defer stamps deferred_at + leaves draft in _drafts/" {
  TMPVAULT="$(make_vault_with_drafts)"
  before=$(git -C "$TMPVAULT" rev-list --count HEAD)
  run "$KUNSKAP_BIN" drafts defer 2 --vault "$TMPVAULT"
  [[ "$status" -eq 0 ]]
  draft="$TMPVAULT/wiki/_drafts/topic-beta--2026-05-01.md"
  [[ -f "$draft" ]]
  grep -q '^deferred_at:' "$draft"
  after=$(git -C "$TMPVAULT" rev-list --count HEAD)
  [[ "$after" -eq "$((before + 1))" ]]
}

@test "drafts defer is idempotent (re-deferring replaces the stamp, doesn't duplicate)" {
  TMPVAULT="$(make_vault_with_drafts)"
  "$KUNSKAP_BIN" drafts defer 2 --vault "$TMPVAULT" >/dev/null
  "$KUNSKAP_BIN" drafts defer 2 --vault "$TMPVAULT" >/dev/null
  draft="$TMPVAULT/wiki/_drafts/topic-beta--2026-05-01.md"
  count=$(grep -c '^deferred_at:' "$draft")
  [[ "$count" -eq 1 ]]
}

# ---------- unknown ----------

@test "drafts unknown subcommand dies clearly" {
  run "$KUNSKAP_BIN" drafts frobnicate
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"unknown subcommand"* ]]
}
