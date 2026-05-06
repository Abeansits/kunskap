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

# ---------- v1.0.1 spawn permissions (subprocess permission fix) ----------
#
# Real-usage finding 2026-05-06 (Vigil's first end-to-end smoke against
# ~/Projects/kunskap-smoke): both curate + lint aborted because spawning with
# --permission-mode acceptEdits covers Edit/Write/fs-ops but NOT Bash git ops.
# The curator's MUST 1 atomic per-article commits and the linter's run-record
# write (single permitted exception per P5) both need git add/commit/mv via
# Bash, which prompted with no human attached → denied. v1.0.1 switches to
# `--permission-mode dontAsk` + an explicit `--allowed-tools` allow-list.
#
# These shape-tests are defense-in-depth: they catch any future /simplify
# pass that swaps the allow-list back to bypassPermissions for convenience,
# and they enforce the linter-tighter-than-curator invariant.

@test "cmd_curate spawn uses --allowed-tools + --permission-mode dontAsk (v1.0.1)" {
  local body
  body="$(fn_body cmd_curate)"
  echo "$body" | grep -q '\-\-allowed-tools "\$curator_tools"'
  echo "$body" | grep -q '\-\-permission-mode dontAsk'
  # Old shape must be gone — acceptEdits doesn't cover Bash git ops, that
  # was the v1.0.1 bug. Catch a regression that re-introduces it.
  ! echo "$body" | grep -q '\-\-permission-mode acceptEdits'
}

@test "cmd_lint spawn uses --allowed-tools + --permission-mode dontAsk (v1.0.1)" {
  local body
  body="$(fn_body cmd_lint)"
  echo "$body" | grep -q '\-\-allowed-tools "\$linter_tools"'
  echo "$body" | grep -q '\-\-permission-mode dontAsk'
  ! echo "$body" | grep -q '\-\-permission-mode acceptEdits'
}

@test "cmd_curate + cmd_lint never spawn with bypassPermissions (defense in depth)" {
  # Bypass mode would grant arbitrary Bash, defeating the allow-list contract.
  # Also covers writes to .git/.claude/.vscode/.idea/.husky per canonical docs
  # — the agent has no business there. If a future /simplify or refactor pass
  # swaps in bypassPermissions for "convenience", this test fails the run.
  ! fn_body cmd_curate | grep -q 'bypassPermissions'
  ! fn_body cmd_lint   | grep -q 'bypassPermissions'
  # Defense in depth × 2: also reject `Bash(*)` which is bypass-equivalent
  # for shell ops.
  ! fn_body cmd_curate | grep -qE 'Bash\(\*\)'
  ! fn_body cmd_lint   | grep -qE 'Bash\(\*\)'
}

@test "cmd_curate allow-list pre-approves the git ops the curator subagent invokes" {
  # MUST 1 atomic per-article commits need add + mv + commit at minimum.
  # Cover both `git foo` and `git -C $vault foo` forms — agent prompts in
  # agents/curator.md use the -C form; cd-into-vault context permits the
  # bare form. Allow-list covers both so neither prompts.
  local body
  body="$(fn_body cmd_curate)"
  echo "$body" | grep -q 'Bash(git add:\*)'
  echo "$body" | grep -q 'Bash(git commit:\*)'
  echo "$body" | grep -q 'Bash(git mv:\*)'
  echo "$body" | grep -q 'Bash(git rm:\*)'
  echo "$body" | grep -q 'Bash(git -C \* add:\*)'
  echo "$body" | grep -q 'Bash(git -C \* commit:\*)'
  echo "$body" | grep -q 'Bash(git -C \* mv:\*)'
  # Run-record recipe (agents/curator.md §6): mkdir + jq.
  echo "$body" | grep -q 'Bash(mkdir:\*)'
  echo "$body" | grep -q 'Bash(jq:\*)'
}

@test "cmd_curate allow-list never includes git push (P2 SessionEnd hook owns push)" {
  # Curator runs locally; pushing is the SessionEnd hook's job (P2). If a
  # future change adds `Bash(git push:*)` to the curator allow-list it's
  # almost certainly a mistake — the agent shouldn't push.
  local body
  body="$(fn_body cmd_curate)"
  ! echo "$body" | grep -qE 'Bash\(git push'
  ! echo "$body" | grep -qE 'Bash\(git -C \* push'
}

@test "cmd_lint allow-list is tighter than cmd_curate's (read-only invariant)" {
  # Linter MUST 8 read-only invariant: the only path the linter writes is
  # _meta/last-run/linter.json. Reflect that at the permissions layer:
  #   - No Edit / MultiEdit (linter never modifies existing files).
  #   - git add is per-path-scoped to _meta/last-run/linter.json, not `git
  #     add:*` (curator-style).
  local body
  body="$(fn_body cmd_lint)"
  # Per-path scoping for the run-record write — both `git foo` + `git -C *
  # foo` forms covered. The CLI authoritative invariant check below the
  # spawn (P4 §3 status_before/after + HEAD oid) is the trust boundary;
  # the per-path allow rule is defense in depth.
  echo "$body" | grep -q 'Bash(git add _meta/last-run/linter\.json)'
  echo "$body" | grep -q 'Bash(git -C \* add _meta/last-run/linter\.json)'
  # Linter must NOT have the broad `git add:*` curator-style rule.
  ! echo "$body" | grep -qE 'Bash\(git add:\*\)'
  ! echo "$body" | grep -qE 'Bash\(git -C \* add:\*\)'
  # Linter must NOT have Edit / MultiEdit / git mv / git rm.
  ! echo "$body" | grep -qE 'linter_tools.*Edit'
  ! echo "$body" | grep -qE 'linter_tools.*MultiEdit'
  ! echo "$body" | grep -qE 'Bash\(git mv'
  ! echo "$body" | grep -qE 'Bash\(git rm'
}

@test "cmd_lint allow-list covers the read-only git ops the linter subagent invokes" {
  # MUST 6 identity-mismatch needs git log; MUST 8 self-check needs git
  # status; everything uses git rev-parse for HEAD oid. All these ARE
  # auto-approved as built-in read-only forms in dontAsk mode per canonical
  # docs, but explicit allow rules insulate against future Claude Code
  # changes + cover the "unquoted glob promotes to prompt" edge case.
  local body
  body="$(fn_body cmd_lint)"
  echo "$body" | grep -q 'Bash(git status:\*)'
  echo "$body" | grep -q 'Bash(git log:\*)'
  echo "$body" | grep -q 'Bash(git rev-parse:\*)'
  echo "$body" | grep -q 'Bash(git -C \* status:\*)'
  echo "$body" | grep -q 'Bash(git -C \* log:\*)'
  echo "$body" | grep -q 'Bash(git -C \* rev-parse:\*)'
}

@test "cmd_curate + cmd_lint allow-list both include Agent (subagent invocation)" {
  # The directive prompt invokes the curator/linter subagent via the Agent
  # tool (canonical docs §Agent SDK overview — "Include `Agent` in
  # allowedTools since subagents are invoked via the Agent tool"). Without
  # this entry, the parent claude can't spawn the subagent, defeating the
  # entire spawn shape.
  fn_body cmd_curate | grep -qE 'curator_tools="[^"]*Agent'
  fn_body cmd_lint   | grep -qE 'linter_tools="[^"]*Agent'
}

@test "cmd_lint allow-list covers awk + find + xargs (MUST 3 frontmatter parsing)" {
  # agents/linter.md §Frontmatter parsing mandates the canonical anchor-to-
  # NR==1 awk recipe for every draft's `created:` / `deferred_at:` parse
  # (MUST 3 staleness), and `find … | xargs awk` for single-pass bulk
  # parsing (agents/linter.md:152). The first smoke missed this because
  # the smoke vault had no stale drafts; any production vault with
  # wiki/_drafts/*.md triggers silent denials without these. Pass-1 review
  # gap, locked here to prevent regression.
  local body
  body="$(fn_body cmd_lint)"
  echo "$body" | grep -q 'Bash(awk:\*)'
  echo "$body" | grep -q 'Bash(find:\*)'
  echo "$body" | grep -q 'Bash(xargs:\*)'
}
