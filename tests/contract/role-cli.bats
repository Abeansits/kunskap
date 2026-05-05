#!/usr/bin/env bats
# P5 — role check semantics for `bin/kunskap curate` and `bin/kunskap lint`.
# No LLM, no auth — exercises the role-check ordering, refusal messages, and
# --force / --yes bypass without spawning an agent. Behavioral assertions
# (curator + linter actually running role-gated) live in their respective
# behavioral.bats / linter-behavioral.bats suites.
#
# Identity-string format: <name>@<host>. The fixture identity is ci@runner.

load helpers

setup() {
  TMPVAULT="$(make_empty_init_vault)"
  TMPXDG="$(make_temp_xdg)"
  export TMPVAULT TMPXDG
  export XDG_CONFIG_HOME="$TMPXDG"
}

teardown() {
  cleanup_temp_dirs TMPVAULT TMPXDG
}

# ---------- --force / --yes / --check argument parsing ----------

@test "curate --force is accepted (P5 surface)" {
  write_identity_toml "$TMPXDG"
  run "$KUNSKAP_BIN" curate --vault "$TMPVAULT" --check --force --yes
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"healthy"* ]]
}

@test "lint --force is accepted (P5 surface)" {
  write_identity_toml "$TMPXDG"
  # Force a failure at the agent-file check so we don't need claude on PATH.
  fake_root="$(mktemp -d)"
  CLAUDE_PLUGIN_ROOT="$fake_root" run "$KUNSKAP_BIN" lint --vault "$TMPVAULT" --force --yes
  rm -rf "$fake_root"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"linter agent not found"* ]]   # got past arg parsing
}

@test "kunskap help advertises --force / --yes for curate + lint" {
  run "$KUNSKAP_BIN" help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"curate --vault <abs-path> [--check] [--force] [--yes]"* ]]
  [[ "$output" == *"lint   [--vault <abs-path>] [--format text|json] [--force] [--yes]"* ]]
}

@test "kunskap help describes the role-check semantics + forced=true audit trail" {
  run "$KUNSKAP_BIN" help
  [[ "$output" == *"single-primary"* ]]
  [[ "$output" == *"forced=true"* ]]
}

# ---------- identity required (self-state, P1 §5 ordering) ----------

@test "curate refuses without identity (whoami required)" {
  # No write_identity_toml → identity unset.
  run "$KUNSKAP_BIN" curate --vault "$TMPVAULT"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"identity not set"* ]]
}

@test "lint refuses without identity (whoami required)" {
  run "$KUNSKAP_BIN" lint --vault "$TMPVAULT"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"identity not set"* ]]
}

@test "curate identity check fires AFTER agent-file but BEFORE claude-PATH" {
  # No identity, plugin shape healthy. Without identity, role check fires
  # before claude-PATH; the user hears "identity not set" rather than
  # "claude not on PATH" on a fresh-checkout machine.
  run env PATH="/usr/bin:/bin" "$KUNSKAP_BIN" curate --vault "$TMPVAULT"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"identity not set"* ]]
  [[ "$output" != *"claude\` not on PATH"* ]]
}

# ---------- missing / TBD primary: warn + proceed ----------

@test "curate proceeds when roles.toml has primary=\"TBD\" (warn, not refuse)" {
  write_identity_toml "$TMPXDG"
  # Empty-init template ships TBD primaries — match the as-shipped state.
  run "$KUNSKAP_BIN" curate --vault "$TMPVAULT" --check
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"healthy"* ]]
}

@test "curate proceeds when _meta/roles.toml is missing entirely (warn)" {
  write_identity_toml "$TMPXDG"
  rm -f "$TMPVAULT/_meta/roles.toml"
  # Force a controlled non-zero AFTER the role-check warning by stripping
  # claude from PATH; the warning lands on stderr regardless. The role
  # name is interpolated (`roles.curator.primary`), not the placeholder.
  run env PATH="/usr/bin:/bin" "$KUNSKAP_BIN" curate --vault "$TMPVAULT"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"no roles.curator.primary configured"* ]]
}

@test "lint proceeds when roles.toml has primary=\"TBD\" (warn, not refuse)" {
  write_identity_toml "$TMPXDG"
  # No claude on PATH so we don't actually spawn; warning lands on stderr
  # before claude-PATH refusal. Role name is interpolated.
  run env PATH="/usr/bin:/bin" "$KUNSKAP_BIN" lint --vault "$TMPVAULT"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"no roles.linter.primary configured"* ]]
}

# ---------- mismatch refuses unless --force ----------

@test "curate refuses on identity mismatch with actionable error" {
  write_identity_toml "$TMPXDG" sebastian laptop
  cat > "$TMPVAULT/_meta/roles.toml" <<'EOF'
[roles.curator]
primary = "alice@desktop"

[roles.linter]
primary = "alice@desktop"
EOF
  run "$KUNSKAP_BIN" curate --vault "$TMPVAULT"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"sebastian@laptop is not the primary"* ]]
  [[ "$output" == *"alice@desktop"* ]]
  [[ "$output" == *"Pass --force to override"* ]]
}

@test "lint refuses on identity mismatch with actionable error" {
  write_identity_toml "$TMPXDG" sebastian laptop
  cat > "$TMPVAULT/_meta/roles.toml" <<'EOF'
[roles.curator]
primary = "alice@desktop"

[roles.linter]
primary = "alice@desktop"
EOF
  run "$KUNSKAP_BIN" lint --vault "$TMPVAULT"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"sebastian@laptop is not the primary"* ]]
  [[ "$output" == *"alice@desktop"* ]]
}

@test "curate --force --yes bypasses role check on mismatch" {
  write_identity_toml "$TMPXDG" sebastian laptop
  cat > "$TMPVAULT/_meta/roles.toml" <<'EOF'
[roles.curator]
primary = "alice@desktop"

[roles.linter]
primary = "alice@desktop"
EOF
  # --force --yes proceeds; --check short-circuits before agent spawn.
  run "$KUNSKAP_BIN" curate --vault "$TMPVAULT" --check --force --yes
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"healthy"* ]]
}

@test "lint --force without --yes (and KUNSKAP_AUTO_CONFIRM=0) prompts for confirmation" {
  write_identity_toml "$TMPXDG" sebastian laptop
  cat > "$TMPVAULT/_meta/roles.toml" <<'EOF'
[roles.curator]
primary = "alice@desktop"

[roles.linter]
primary = "alice@desktop"
EOF
  # `n` answer cancels the run; KUNSKAP_AUTO_CONFIRM=0 forces prompting
  # even when the env wants auto-confirm.
  run env KUNSKAP_AUTO_CONFIRM=0 bash -c "echo n | '$KUNSKAP_BIN' lint --vault '$TMPVAULT' --force"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"cancelled"* ]]
}

@test "lint --force with KUNSKAP_AUTO_CONFIRM=1 skips the prompt (cron-friendly)" {
  write_identity_toml "$TMPXDG" sebastian laptop
  cat > "$TMPVAULT/_meta/roles.toml" <<'EOF'
[roles.curator]
primary = "alice@desktop"

[roles.linter]
primary = "alice@desktop"
EOF
  # Stop at the claude-on-PATH preflight (which fires AFTER role check),
  # so the force-override stderr lands without spawning an agent. Real
  # plugin root → agent-file passes; PATH strip → claude check fails.
  run env KUNSKAP_AUTO_CONFIRM=1 PATH="/usr/bin:/bin" \
    "$KUNSKAP_BIN" lint --vault "$TMPVAULT" --force
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"claude"*"PATH"* ]]
  [[ "$output" == *"--force overrides role check"* ]]
}

# ---------- match permits without --force ----------

@test "curate proceeds when identity matches roles.curator.primary" {
  write_identity_toml "$TMPXDG" sebastian laptop
  cat > "$TMPVAULT/_meta/roles.toml" <<'EOF'
[roles.curator]
primary = "sebastian@laptop"

[roles.linter]
primary = "alice@desktop"
EOF
  run "$KUNSKAP_BIN" curate --vault "$TMPVAULT" --check
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"healthy"* ]]
  [[ "$output" != *"--force overrides"* ]]
}

@test "lint proceeds when identity matches roles.linter.primary" {
  write_identity_toml "$TMPXDG" sebastian laptop
  cat > "$TMPVAULT/_meta/roles.toml" <<'EOF'
[roles.curator]
primary = "alice@desktop"

[roles.linter]
primary = "sebastian@laptop"
EOF
  fake_root="$(mktemp -d)"
  CLAUDE_PLUGIN_ROOT="$fake_root" run "$KUNSKAP_BIN" lint --vault "$TMPVAULT"
  rm -rf "$fake_root"
  [[ "$status" -ne 0 ]]   # agent-file preflight fires
  [[ "$output" == *"linter agent not found"* ]]
  [[ "$output" != *"--force"* ]]
}

# ---------- bin/kunskap source surface (catches refactor regressions) ----------

@test "bin/kunskap defines check_role + read_role_primary helpers" {
  grep -q '^check_role()' "$KUNSKAP_BIN"
  grep -q '^read_role_primary()' "$KUNSKAP_BIN"
}

@test "bin/kunskap treats roles.<role>.primary=\"TBD\" as not-yet-configured" {
  # The TBD sentinel maps to "primary unset" (warn, not refuse). Check the
  # source-level branch directly so a refactor that drops the special-case
  # fails this test specifically.
  grep -q '"\$val" == "TBD"' "$KUNSKAP_BIN"
}

@test "cmd_curate calls check_role for the curator role" {
  fn_body cmd_curate | grep -q 'check_role "$vault" curator'
}

@test "cmd_lint calls check_role for the linter role" {
  fn_body cmd_lint | grep -q 'check_role "$vault" linter'
}

# ---------- CWD-fix (P4 §2 sandbox-CWD bug → P5 priority fix) ----------

@test "cmd_curate cd's into the vault before spawning claude (P4 §2 fix)" {
  # The CWD-fix is the load-bearing P5 implementation change alongside the
  # role check — ensure cmd_curate sets vault as CWD before exec'ing claude.
  fn_body cmd_curate | grep -q 'cd "$vault"'
}

@test "cmd_lint runs claude with vault as CWD (sandbox covers vault)" {
  fn_body cmd_lint | grep -q 'cd "$vault" && claude'
}

@test "cmd_curate + cmd_lint pass --add-dir \"\$vault\" to claude (defense in depth)" {
  fn_body cmd_curate | grep -q '\-\-add-dir "$vault"'
  fn_body cmd_lint | grep -q '\-\-add-dir "$vault"'
}
