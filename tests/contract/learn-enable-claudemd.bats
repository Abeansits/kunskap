#!/usr/bin/env bats
# CLAUDE.md injection coverage for `kunskap learn enable | disable` (v1.1).
#
# The managed block is bounded by `<!-- BEGIN/END kunskap (managed) -->`
# markers and carries a sha256 fingerprint comment so `learn disable` can
# refuse to silently nuke user edits inside the fence.

load helpers

setup() {
  setup_proj_xdg
  vault="$(mktemp -d)"
  export vault
}

teardown() {
  cleanup_temp_dirs TMPPROJ TMPXDG
  [[ -n "${vault:-}" && -d "$vault" ]] && rm -rf "$vault"
}

claudemd() { printf '%s/CLAUDE.md\n' "$TMPPROJ"; }

# ---------- enable ----------

@test "learn enable creates CLAUDE.md with the managed block when none exists" {
  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  [[ -f "$(claudemd)" ]]
  grep -Fq '<!-- BEGIN kunskap (managed) -->' "$(claudemd)"
  grep -Fq '<!-- END kunskap (managed) -->' "$(claudemd)"
  grep -Fq '<!-- kunskap:hash ' "$(claudemd)"
}

@test "learn enable preserves existing CLAUDE.md user content" {
  cd "$TMPPROJ"
  cat > "$(claudemd)" <<'EOF'
# My project

User-authored guidance line one.
EOF
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  grep -Fq '# My project' "$(claudemd)"
  grep -Fq 'User-authored guidance line one.' "$(claudemd)"
  grep -Fq '<!-- BEGIN kunskap (managed) -->' "$(claudemd)"
}

@test "learn enable injects the LAUNCH_FOOTER body into the managed block" {
  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  # Spot-check: a few stable phrases from templates/LAUNCH_FOOTER.md.
  grep -Fq '## Collective Knowledge' "$(claudemd)"
  grep -Fq '### Post-task (required unless truly nothing new)' "$(claudemd)"
  grep -Fq '/kunskap:recall' "$(claudemd)"
}

@test "learn enable injects the Recall addendum after the LAUNCH_FOOTER body" {
  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  grep -Fq '## Recall' "$(claudemd)"
  grep -Fq 'At the start of every new task, run' "$(claudemd)"
}

@test "learn enable is idempotent — re-enable doesn't duplicate the block" {
  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  count=$(grep -c '<!-- BEGIN kunskap (managed) -->' "$(claudemd)")
  [[ "$count" -eq 1 ]]
  count=$(grep -c '<!-- END kunskap (managed) -->' "$(claudemd)")
  [[ "$count" -eq 1 ]]
}

@test "learn enable replaces stale managed-block content on re-enable" {
  cd "$TMPPROJ"
  # Plant a stale block (stale hash, stale body) by hand.
  cat > "$(claudemd)" <<'EOF'
# My project

<!-- BEGIN kunskap (managed) -->
<!-- kunskap:hash 0000000000000000000000000000000000000000000000000000000000000000 -->
old stale body that should be replaced
<!-- END kunskap (managed) -->
EOF
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  ! grep -Fq 'old stale body that should be replaced' "$(claudemd)"
  grep -Fq '## Collective Knowledge' "$(claudemd)"
  grep -Fq '# My project' "$(claudemd)"
}

# ---------- disable ----------

@test "learn disable cleanly removes the managed block (and the file if empty)" {
  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  "$KUNSKAP_BIN" learn disable
  [[ ! -f "$(claudemd)" ]]
}

@test "learn disable preserves user content surrounding the managed block" {
  cd "$TMPPROJ"
  cat > "$(claudemd)" <<'EOF'
# My project

User-authored guidance line one.
EOF
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  "$KUNSKAP_BIN" learn disable
  [[ -f "$(claudemd)" ]]
  grep -Fq '# My project' "$(claudemd)"
  grep -Fq 'User-authored guidance line one.' "$(claudemd)"
  ! grep -Fq '<!-- BEGIN kunskap (managed) -->' "$(claudemd)"
}

@test "learn disable refuses when user edited inside the managed block" {
  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  # Tamper inside the fence.
  awk '/^### Pre-flight/ { print "INSERTED BY USER" } { print }' "$(claudemd)" \
    > "$(claudemd).tmp"
  mv "$(claudemd).tmp" "$(claudemd)"
  run "$KUNSKAP_BIN" learn disable
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"manual edits detected"* ]]
  # The fence and the marker must still be on disk so the user can review.
  grep -Fq '<!-- BEGIN kunskap (managed) -->' "$(claudemd)"
  [[ -f "$TMPPROJ/.claude/kunskap.json" ]]
}

@test "learn disable refuses when the hash fingerprint is missing (legacy/foreign block)" {
  cd "$TMPPROJ"
  cat > "$(claudemd)" <<'EOF'
<!-- BEGIN kunskap (managed) -->
some body but no hash line
<!-- END kunskap (managed) -->
EOF
  # Drop a marker so disable proceeds past the not-enabled check.
  mkdir -p "$TMPPROJ/.claude"
  echo '{"vault": "/tmp/x", "enabled": true, "confirmed_at": "2026-05-06T00:00:00Z"}' > "$TMPPROJ/.claude/kunskap.json"
  run "$KUNSKAP_BIN" learn disable
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"lacks fingerprint"* ]]
}

@test "learn disable on a project with no CLAUDE.md still removes the marker" {
  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  rm -f "$(claudemd)"   # user nuked CLAUDE.md by hand between enable + disable
  run "$KUNSKAP_BIN" learn disable
  [[ "$status" -eq 0 ]]
  [[ ! -f "$TMPPROJ/.claude/kunskap.json" ]]
}
