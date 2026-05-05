#!/usr/bin/env bats
# CLI-surface tests for `bin/kunskap learn enable | disable | status` and the
# `.claude/kunskap.json` marker schema. No LLM, no auth.
#
# Each test runs in a fresh temp project + temp XDG config so the user's real
# identity file and .claude/ markers are never touched.

load helpers

setup() {
  TMPPROJ="$(make_temp_proj)"
  TMPXDG="$(make_temp_xdg)"
  export TMPPROJ TMPXDG
  export XDG_CONFIG_HOME="$TMPXDG"
}

teardown() {
  [[ -n "${TMPPROJ:-}" && -d "$TMPPROJ" ]] && rm -rf "$TMPPROJ"
  [[ -n "${TMPXDG:-}"  && -d "$TMPXDG"  ]] && rm -rf "$TMPXDG"
}

# ---------- learn enable ----------

@test "learn enable requires --vault" {
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" learn enable
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"--vault"* ]]
}

@test "learn enable rejects relative paths" {
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" learn enable --vault relative/dir
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"absolute path"* ]]
}

@test "learn enable rejects flag-as-value (P0 lesson)" {
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" learn enable --vault --yes
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"got next flag"* ]]
}

@test "learn enable rejects non-existent vault path" {
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" learn enable --vault /nonexistent/path-$$ --yes
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"does not exist"* ]]
}

@test "learn enable rejects non-directory" {
  cd "$TMPPROJ"
  vfile="$(mktemp)"
  run "$KUNSKAP_BIN" learn enable --vault "$vfile" --yes
  rm -f "$vfile"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"not a directory"* ]]
}

@test "learn enable requires interactive confirmation (Risk #7)" {
  cd "$TMPPROJ"
  vault="$(mktemp -d)"
  # Default: no --yes, no env var, stdin is empty (read returns "").
  run bash -c "echo '' | '$KUNSKAP_BIN' learn enable --vault '$vault'"
  rm -rf "$vault"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"cancelled"* ]]
  [[ ! -f "$TMPPROJ/.claude/kunskap.json" ]]
}

@test "learn enable confirmation prompt prints labeled PROJECT + VAULT lines (Risk #7 ergonomics)" {
  cd "$TMPPROJ"
  vault="$(mktemp -d)"
  run bash -c "echo 'n' | '$KUNSKAP_BIN' learn enable --vault '$vault'"
  rm -rf "$vault"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"PROJECT:"* ]]
  [[ "$output" == *"VAULT:"* ]]
  [[ "$output" == *"$TMPPROJ"* ]]
}

@test "learn enable accepts KUNSKAP_AUTO_CONFIRM=1 (test scriptability)" {
  cd "$TMPPROJ"
  vault="$(mktemp -d)"
  KUNSKAP_AUTO_CONFIRM=1 run "$KUNSKAP_BIN" learn enable --vault "$vault"
  [[ "$status" -eq 0 ]]
  [[ -f "$TMPPROJ/.claude/kunskap.json" ]]
  rm -rf "$vault"
}

@test "learn enable --yes bypasses confirmation prompt" {
  cd "$TMPPROJ"
  vault="$(mktemp -d)"
  run "$KUNSKAP_BIN" learn enable --vault "$vault" --yes
  [[ "$status" -eq 0 ]]
  [[ -f "$TMPPROJ/.claude/kunskap.json" ]]
  rm -rf "$vault"
}

@test "learn enable writes the documented JSON shape" {
  cd "$TMPPROJ"
  vault="$(mktemp -d)"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  marker="$TMPPROJ/.claude/kunskap.json"
  jq -e '.vault and .enabled and .confirmed_at' "$marker"
  v=$(jq -r .vault "$marker"); [[ "$v" == "$vault" ]]
  e=$(jq -r .enabled "$marker"); [[ "$e" == "true" ]]
  c=$(jq -r .confirmed_at "$marker")
  [[ "$c" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
  rm -rf "$vault"
}

# ---------- learn disable ----------

@test "learn disable on a non-enabled project exits 0 with a friendly message" {
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" learn disable
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"not enabled"* ]]
}

@test "learn disable removes the marker file" {
  cd "$TMPPROJ"
  vault="$(mktemp -d)"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  [[ -f "$TMPPROJ/.claude/kunskap.json" ]]
  run "$KUNSKAP_BIN" learn disable
  [[ "$status" -eq 0 ]]
  [[ ! -f "$TMPPROJ/.claude/kunskap.json" ]]
  rm -rf "$vault"
}

# ---------- learn status ----------

@test "learn status without a marker prints DISABLED" {
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" learn status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"STATUS: disabled"* ]]
}

@test "learn status with marker but no identity prints IDENTITY: not set" {
  cd "$TMPPROJ"
  vault="$(mktemp -d)"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  run "$KUNSKAP_BIN" learn status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"STATUS: true"* ]]
  [[ "$output" == *"VAULT:  $vault"* ]]
  [[ "$output" == *"IDENTITY: not set"* ]]
  rm -rf "$vault"
}

@test "learn status surfaces SHARED from vault _meta/kunskap.toml" {
  cd "$TMPPROJ"
  vault="$(mktemp -d)"
  mkdir -p "$vault/_meta"
  cat > "$vault/_meta/kunskap.toml" <<EOF
[vault]
name = "test-vault"
shared = true
EOF
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  run "$KUNSKAP_BIN" learn status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"SHARED: true"* ]]
  rm -rf "$vault"
}

@test "learn status surfaces REMOTE: not configured for shared vault without origin" {
  cd "$TMPPROJ"
  vault="$(mktemp -d)"
  mkdir -p "$vault/_meta"
  cat > "$vault/_meta/kunskap.toml" <<EOF
[vault]
shared = true
EOF
  ( cd "$vault" && git init -q && git config user.email s@b && git config user.name s )
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  run "$KUNSKAP_BIN" learn status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"REMOTE: not configured"* ]]
  [[ "$output" == *"pushes will fail"* ]]
  rm -rf "$vault"
}

@test "learn status surfaces REMOTE: <url> when origin is configured" {
  cd "$TMPPROJ"
  vault="$(mktemp -d)"
  mkdir -p "$vault/_meta"
  cat > "$vault/_meta/kunskap.toml" <<EOF
[vault]
shared = true
EOF
  ( cd "$vault" \
    && git init -q \
    && git config user.email s@b && git config user.name s \
    && git remote add origin git@example.com:org/repo.git )
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  run "$KUNSKAP_BIN" learn status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"REMOTE: git@example.com:org/repo.git"* ]]
  rm -rf "$vault"
}

@test "learn status reports SHARED: unknown when vault not yet initialized" {
  cd "$TMPPROJ"
  vault="$(mktemp -d)"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  run "$KUNSKAP_BIN" learn status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"SHARED: unknown"* ]]
  rm -rf "$vault"
}

@test "learn status warns when confirmed_at is >30 days old (Risk #7)" {
  cd "$TMPPROJ"
  vault="$(mktemp -d)"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  marker="$TMPPROJ/.claude/kunskap.json"
  # Rewrite confirmed_at to 60 days ago. Use python for cross-platform date math.
  old_date=$(python3 -c "from datetime import datetime,timedelta,timezone;print((datetime.now(timezone.utc)-timedelta(days=60)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
  python3 -c "import json,sys;p='$marker';d=json.load(open(p));d['confirmed_at']='$old_date';json.dump(d,open(p,'w'))"
  run "$KUNSKAP_BIN" learn status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"60d ago"* ]]
  [[ "$output" == *"WARNING:"* ]]
  [[ "$output" == *">30 days old"* ]]
  rm -rf "$vault"
}

@test "learn status surfaces ROLE-CHECK when identity matches roles.toml primary" {
  cd "$TMPPROJ"
  "$KUNSKAP_BIN" config user --name ci --host runner >/dev/null 2>&1
  vault="$(mktemp -d)"
  mkdir -p "$vault/_meta"
  cat > "$vault/_meta/kunskap.toml" <<EOF
[vault]
shared = true
EOF
  cat > "$vault/_meta/roles.toml" <<EOF
[roles.curator]
primary = "ci@runner"

[roles.linter]
primary = "someone@elsewhere"
EOF
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  run "$KUNSKAP_BIN" learn status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"IDENTITY: ci@runner"* ]]
  [[ "$output" == *"ROLE-CHECK: primary for curator"* ]]
  rm -rf "$vault"
}

@test "learn status reports not-primary when identity doesn't match any role" {
  cd "$TMPPROJ"
  "$KUNSKAP_BIN" config user --name ci --host runner >/dev/null 2>&1
  vault="$(mktemp -d)"
  mkdir -p "$vault/_meta"
  cat > "$vault/_meta/kunskap.toml" <<EOF
[vault]
shared = true
EOF
  cat > "$vault/_meta/roles.toml" <<EOF
[roles.curator]
primary = "sebastian@laptop"
EOF
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault"
  run "$KUNSKAP_BIN" learn status
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"ROLE-CHECK: not primary"* ]]
  [[ "$output" == *"sebastian@laptop"* ]]
  rm -rf "$vault"
}

@test "learn unknown subcommand dies clearly" {
  run "$KUNSKAP_BIN" learn frobnicate
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"unknown subcommand"* ]]
}
