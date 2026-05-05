#!/usr/bin/env bats
# Hook smoke tests. Invoke session-start.sh and session-end.sh against
# fixture vaults covering every documented fail-soft path. Each test asserts
# exit 0 (HARD CONTRACT — hooks must NEVER block session start/end) and the
# expected stderr message.

load helpers

SESSION_START="$REPO_ROOT/hooks/session-start.sh"
SESSION_END="$REPO_ROOT/hooks/session-end.sh"

setup() {
  TMPPROJ="$(mktemp -d -t kunskap-proj.XXXXXX)"
  TMPXDG="$(mktemp -d -t kunskap-xdg.XXXXXX)"
  export TMPPROJ TMPXDG
  export XDG_CONFIG_HOME="$TMPXDG"
  export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"
  export CLAUDE_PROJECT_DIR="$TMPPROJ"
}

teardown() {
  [[ -n "${TMPPROJ:-}" && -d "$TMPPROJ" ]] && rm -rf "$TMPPROJ"
  [[ -n "${TMPXDG:-}"  && -d "$TMPXDG"  ]] && rm -rf "$TMPXDG"
  unset CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR
}

# Build a marker for $TMPPROJ pointing at $1.
write_marker() {
  local vault="$1"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault" >/dev/null
}

# Init a shared vault git repo at $1, optional remote at $2.
make_shared_vault() {
  local vault="$1" remote="${2-}"
  mkdir -p "$vault/_meta" "$vault/raw/inbox"
  cat > "$vault/_meta/kunskap.toml" <<EOF
[vault]
name = "smoke-vault"
shared = true
EOF
  ( cd "$vault" \
    && git init -q \
    && git config user.email smoke@bats \
    && git config user.name  smoke \
    && [[ -n "$remote" ]] && git remote add origin "$remote" || true
    git add . && git commit -q -m "smoke: seed" )
}

# ---------- session-start.sh fail-soft paths ----------

@test "session-start: no marker → silent exit 0" {
  run "$SESSION_START"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "session-start: marker but no identity → exit 0 with friendly stderr" {
  vault="$(mktemp -d)"
  write_marker "$vault"
  run "$SESSION_START"
  rm -rf "$vault"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"identity not set"* ]]
}

@test "session-start: identity set but vault missing on disk → exit 0 + stderr" {
  vault="$(mktemp -d)"
  write_marker "$vault"
  rm -rf "$vault"
  "$KUNSKAP_BIN" config user --name ci --host runner >/dev/null 2>&1
  run "$SESSION_START"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"vault path missing"* || "$output" == *"marker malformed"* ]]
}

@test "session-start: vault exists but _meta/kunskap.toml missing → exit 0 quiet (treated as not-shared)" {
  vault="$(mktemp -d)"
  write_marker "$vault"
  "$KUNSKAP_BIN" config user --name ci --host runner >/dev/null 2>&1
  run "$SESSION_START"
  rm -rf "$vault"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "session-start: solo vault (shared=false) → exit 0 quiet, no pull attempted" {
  vault="$(mktemp -d)"
  mkdir -p "$vault/_meta"
  cat > "$vault/_meta/kunskap.toml" <<EOF
[vault]
shared = false
EOF
  write_marker "$vault"
  "$KUNSKAP_BIN" config user --name ci --host runner >/dev/null 2>&1
  run "$SESSION_START"
  rm -rf "$vault"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "session-start: shared vault but git pull fails (no remote) → exit 0 + stderr" {
  vault="$(mktemp -d -t shared-vault.XXXXXX)"
  make_shared_vault "$vault"   # no remote
  write_marker "$vault"
  "$KUNSKAP_BIN" config user --name ci --host runner >/dev/null 2>&1
  run "$SESSION_START"
  rm -rf "$vault"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"vault pull failed"* ]]
}

# ---------- session-end.sh fail-soft paths ----------

@test "session-end: no marker → silent exit 0" {
  run "$SESSION_END"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "session-end: marker but no identity → exit 0 silent (no commit under unknown identity)" {
  vault="$(mktemp -d)"
  write_marker "$vault"
  run "$SESSION_END"
  rm -rf "$vault"
  [[ "$status" -eq 0 ]]
}

@test "session-end: solo vault (shared=false) → exit 0 quiet, no commit attempted" {
  vault="$(mktemp -d -t solo-vault.XXXXXX)"
  mkdir -p "$vault/_meta" "$vault/raw/inbox"
  cat > "$vault/_meta/kunskap.toml" <<EOF
[vault]
shared = false
EOF
  ( cd "$vault" && git init -q && git config user.email s@b && git config user.name s )
  write_marker "$vault"
  "$KUNSKAP_BIN" config user --name ci --host runner >/dev/null 2>&1
  run "$SESSION_END"
  rm -rf "$vault"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "session-end: shared vault, no inbox changes → exit 0 quiet (no empty commit)" {
  vault="$(mktemp -d -t shared-vault.XXXXXX)"
  make_shared_vault "$vault"
  write_marker "$vault"
  "$KUNSKAP_BIN" config user --name ci --host runner >/dev/null 2>&1
  run "$SESSION_END"
  rm -rf "$vault"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "session-end: shared vault with new inbox file → commit lands; push fails soft" {
  vault="$(mktemp -d -t shared-vault.XXXXXX)"
  make_shared_vault "$vault"
  write_marker "$vault"
  "$KUNSKAP_BIN" config user --name ci --host runner >/dev/null 2>&1
  echo "new note" > "$vault/raw/inbox/new-note-2026-05-05.md"
  # No remote → push fails; commit must still land + script exits 0.
  run bash -c "echo '{\"session_id\": \"smoke-test-id\"}' | '$SESSION_END'"
  [[ "$status" -eq 0 ]]
  ( cd "$vault" && git log --oneline | head -1 ) | grep -q "kunskap: inbox capture from session smoke-test-id"
  [[ "$output" == *"vault push failed"* ]]
  rm -rf "$vault"
}

@test "session-end: malformed stdin → falls back to session_id=unknown, still exits 0" {
  vault="$(mktemp -d -t shared-vault.XXXXXX)"
  make_shared_vault "$vault"
  write_marker "$vault"
  "$KUNSKAP_BIN" config user --name ci --host runner >/dev/null 2>&1
  echo "new note" > "$vault/raw/inbox/another-note-2026-05-05.md"
  run bash -c "echo 'not json at all' | '$SESSION_END'"
  [[ "$status" -eq 0 ]]
  ( cd "$vault" && git log --oneline | head -1 ) | grep -q "kunskap: inbox capture from session unknown"
  rm -rf "$vault"
}

# ---------- shape sanity ----------

@test "hooks/hooks.json parses as JSON" {
  jq empty "$REPO_ROOT/hooks/hooks.json"
}

@test "hooks/hooks.json declares SessionStart and SessionEnd handlers pointing at scripts" {
  jq -e '.hooks.SessionStart and .hooks.SessionEnd' "$REPO_ROOT/hooks/hooks.json"
  jq -re '.hooks.SessionStart[0].hooks[0].command' "$REPO_ROOT/hooks/hooks.json" \
    | grep -q 'session-start\.sh$'
  jq -re '.hooks.SessionEnd[0].hooks[0].command' "$REPO_ROOT/hooks/hooks.json" \
    | grep -q 'session-end\.sh$'
}

@test "hook commands reference \${CLAUDE_PLUGIN_ROOT} (portability)" {
  cmd_start=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$REPO_ROOT/hooks/hooks.json")
  cmd_end=$(jq -r '.hooks.SessionEnd[0].hooks[0].command'   "$REPO_ROOT/hooks/hooks.json")
  [[ "$cmd_start" == *'${CLAUDE_PLUGIN_ROOT}'* ]]
  [[ "$cmd_end"   == *'${CLAUDE_PLUGIN_ROOT}'* ]]
}
