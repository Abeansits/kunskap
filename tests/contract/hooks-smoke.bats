#!/usr/bin/env bats
# Hook smoke tests. Invoke session-start.sh against fixture vaults covering
# every documented fail-soft path. Each test asserts exit 0 (HARD CONTRACT
# — hooks must NEVER block session start) and the expected stderr message.
#
# v1.1: SessionEnd was removed; the per-write PostToolUse hook covers the
# inbox push more reliably. See tests/contract/post-write-sync.bats for
# its contract suite.

load helpers

SESSION_START="$REPO_ROOT/hooks/session-start.sh"

setup() {
  TMPPROJ="$(make_temp_proj)"
  TMPXDG="$(make_temp_xdg)"
  export TMPPROJ TMPXDG
  export XDG_CONFIG_HOME="$TMPXDG"
  export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"
  export CLAUDE_PROJECT_DIR="$TMPPROJ"
}

# Bypass the `kunskap config user` fork — write identity.toml directly.
set_identity() { write_identity_toml "$TMPXDG"; }

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
  set_identity
  run "$SESSION_START"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"vault path missing"* || "$output" == *"marker malformed"* ]]
}

@test "session-start: vault exists but _meta/kunskap.toml missing → exit 0 quiet (treated as not-shared)" {
  vault="$(mktemp -d)"
  write_marker "$vault"
  set_identity
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
  set_identity
  run "$SESSION_START"
  rm -rf "$vault"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "session-start: vault has rebase in progress → exit 0 + actionable stderr (no pull attempted)" {
  vault="$(mktemp -d -t shared-vault.XXXXXX)"
  make_shared_vault "$vault"
  mkdir -p "$vault/.git/rebase-merge"   # Pass-2 block-ship: detect mid-rebase wedge
  write_marker "$vault"
  set_identity
  run "$SESSION_START"
  rm -rf "$vault"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"rebase in progress"* ]]
  [[ "$output" == *"rebase --continue"* || "$output" == *"--abort"* ]]
}

@test "session-start: prints uncommitted-inbox warning when notes pending (v1.1 passive nudge)" {
  vault="$(mktemp -d -t shared-vault.XXXXXX)"
  make_shared_vault "$vault"
  # Stage an inbox note WITHOUT committing — simulate prior session that
  # crashed before its PostToolUse hook completed.
  echo "leftover" > "$vault/raw/inbox/leftover-2026-05-06.md"
  write_marker "$vault"
  set_identity
  run "$SESSION_START"
  rm -rf "$vault"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"uncommitted inbox note"* ]]
  [[ "$output" == *"/kunskap:sync"* ]]
}

@test "session-start: no nudge when inbox is clean" {
  vault="$(mktemp -d -t shared-vault.XXXXXX)"
  make_shared_vault "$vault"
  write_marker "$vault"
  set_identity
  run "$SESSION_START"
  rm -rf "$vault"
  [[ "$status" -eq 0 ]]
  ! [[ "$output" == *"uncommitted inbox note"* ]]
}

@test "session-start: shared vault but git pull fails (no remote) → exit 0 + stderr" {
  vault="$(mktemp -d -t shared-vault.XXXXXX)"
  make_shared_vault "$vault"   # no remote
  write_marker "$vault"
  set_identity
  run "$SESSION_START"
  rm -rf "$vault"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"vault pull failed"* ]]
}

# ---------- shape sanity ----------

@test "hooks/hooks.json parses as JSON" {
  jq empty "$REPO_ROOT/hooks/hooks.json"
}

@test "hooks/hooks.json declares SessionStart + PostToolUse handlers pointing at scripts" {
  jq -e '.hooks.SessionStart and .hooks.PostToolUse' "$REPO_ROOT/hooks/hooks.json"
  jq -re '.hooks.SessionStart[0].hooks[0].command' "$REPO_ROOT/hooks/hooks.json" \
    | grep -q 'session-start\.sh$'
  jq -re '.hooks.PostToolUse[0].hooks[0].command' "$REPO_ROOT/hooks/hooks.json" \
    | grep -q 'post-write-sync\.sh$'
}

@test "hooks/hooks.json no longer wires SessionEnd (v1.1: replaced by PostToolUse)" {
  # Per-write hook makes SessionEnd redundant + closes the SIGKILL/SIGHUP
  # loss window. Failing this assertion would mean we re-introduced the
  # known-loss path.
  ! jq -e '.hooks.SessionEnd' "$REPO_ROOT/hooks/hooks.json"
}

@test "PostToolUse hook is configured async (v1.1: never block the agentic loop)" {
  jq -e '.hooks.PostToolUse[0].hooks[0].async == true' "$REPO_ROOT/hooks/hooks.json"
}

@test "PostToolUse hook matcher is Write|Edit (only file-write tools)" {
  matcher=$(jq -r '.hooks.PostToolUse[0].matcher' "$REPO_ROOT/hooks/hooks.json")
  [[ "$matcher" == "Write|Edit" ]]
}

@test "hook commands reference \${CLAUDE_PLUGIN_ROOT} (portability)" {
  cmd_start=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$REPO_ROOT/hooks/hooks.json")
  cmd_post=$(jq -r '.hooks.PostToolUse[0].hooks[0].command'   "$REPO_ROOT/hooks/hooks.json")
  [[ "$cmd_start" == *'${CLAUDE_PLUGIN_ROOT}'* ]]
  [[ "$cmd_post"  == *'${CLAUDE_PLUGIN_ROOT}'* ]]
}
