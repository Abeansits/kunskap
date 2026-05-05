#!/usr/bin/env bats
# CLI-surface tests for `bin/kunskap lint`. No LLM, no auth — exercises arg
# parsing, vault validation (flag + marker fallback), and the read-only
# invariant pre-check ordering. Behavioral assertions live in
# linter-behavioral.bats (gated KUNSKAP_LIVE_TESTS=1).

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

# ---------- argument parsing ----------

@test "lint --vault rejects relative path" {
  run "$KUNSKAP_BIN" lint --vault relative/dir
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"absolute path"* ]]
}

@test "lint --vault rejects flag-as-value (require_value pattern)" {
  run "$KUNSKAP_BIN" lint --vault --format
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"got next flag"* ]]
}

@test "lint --vault dies if path missing" {
  run "$KUNSKAP_BIN" lint --vault /nonexistent/path
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"vault path not found"* ]]
}

@test "lint --vault dies if _meta/kunskap.toml missing" {
  empty="$(mktemp -d)"
  mkdir -p "$empty/raw/inbox"
  run "$KUNSKAP_BIN" lint --vault "$empty"
  rm -rf "$empty"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"_meta/kunskap.toml"* ]]
}

@test "lint --format only accepts text|json" {
  TMPVAULT="$(make_temp_vault)"
  run "$KUNSKAP_BIN" lint --vault "$TMPVAULT" --format yaml
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"--format must be text or json"* ]]
}

@test "lint rejects unknown extra args" {
  TMPVAULT="$(make_temp_vault)"
  run "$KUNSKAP_BIN" lint --vault "$TMPVAULT" --bogus
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"unknown extra args"* ]]
}

# ---------- vault resolution (flag + marker fallback) ----------

@test "lint without --vault errors when no project marker" {
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" lint
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"no --vault"* || "$output" == *"no project marker"* ]]
}

@test "lint resolves vault from project marker (.claude/kunskap.json)" {
  TMPVAULT="$(make_temp_vault)"
  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$TMPVAULT" >/dev/null
  # Force the agent-file preflight failure so we don't need claude on PATH.
  fake_root="$(mktemp -d)"
  CLAUDE_PLUGIN_ROOT="$fake_root" run "$KUNSKAP_BIN" lint
  rm -rf "$fake_root"
  # If marker resolution failed, we'd see "no --vault" / "no project marker".
  # If it succeeded, validate_vault would pass and we'd hit the agent-file
  # preflight (the next check after vault validation).
  [[ "$output" != *"no --vault"* ]]
  [[ "$output" != *"no project marker"* ]]
}

@test "lint dies clearly when linter agent file is missing" {
  TMPVAULT="$(make_temp_vault)"
  fake_root="$(mktemp -d)"
  CLAUDE_PLUGIN_ROOT="$fake_root" run "$KUNSKAP_BIN" lint --vault "$TMPVAULT"
  rm -rf "$fake_root"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"linter agent not found"* ]]
}

# Per P1 §5: self-state checks before external (claude on PATH). Verifies the
# user hears about plugin-install corruption before being told to install
# Claude Code — same discipline cmd_curate carries.
@test "lint preflight orders self-checks before external (agent-file before claude-PATH)" {
  TMPVAULT="$(make_temp_vault)"
  fake_root="$(mktemp -d)"
  CLAUDE_PLUGIN_ROOT="$fake_root" PATH="/usr/bin:/bin" run "$KUNSKAP_BIN" lint --vault "$TMPVAULT"
  rm -rf "$fake_root"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"linter agent not found"* ]]
  [[ "$output" != *"claude\` not on PATH"* ]]
}

# ---------- symlink shim (P1 §3 plugin_root resolution) ----------

@test "lint via symlink shim still resolves the plugin root" {
  TMPVAULT="$(make_temp_vault)"
  shim_dir="$(mktemp -d)"
  ln -s "$KUNSKAP_BIN" "$shim_dir/kunskap"
  # Without claude on PATH we land on the agent-file or claude-PATH preflight.
  # Either way, status is non-zero with a kunskap-prefixed message; the test
  # is that the shim found agents/linter.md (otherwise output would mention
  # "linter agent not found" with a wrong fake_root path).
  PATH="/usr/bin:/bin" run "$shim_dir/kunskap" lint --vault "$TMPVAULT"
  rm -rf "$shim_dir"
  # On CI without claude installed, the claude-PATH check fires (agent file
  # was found via the resolved plugin root).
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"claude"*"PATH"* || "$output" == *"linter agent not found"* ]]
}

# ---------- help-text surface ----------

@test "kunskap help advertises lint" {
  run "$KUNSKAP_BIN" help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"kunskap lint"* ]]
  [[ "$output" == *"--format text|json"* ]]
}

@test "kunskap help describes lint exit-code semantics + read-only contract" {
  run "$KUNSKAP_BIN" help
  [[ "$output" == *"Read-only"* ]]
  [[ "$output" == *"git status --porcelain"* ]]
  [[ "$output" == *"0 = no findings"* ]]
}

# ---------- commands/lint.md surface ----------

@test "commands/lint.md exists and declares argument-hint + description" {
  [[ -f "$REPO_ROOT/commands/lint.md" ]]
  grep -q '^argument-hint:' "$REPO_ROOT/commands/lint.md"
  grep -q '^description:'   "$REPO_ROOT/commands/lint.md"
}

@test "commands/lint.md delegates to bin/kunskap lint" {
  grep -q 'kunskap lint' "$REPO_ROOT/commands/lint.md"
}

# ---------- read-only invariant snapshot is taken before agent spawn ----------
#
# We can't run the real agent in a CLI test (no LLM), but we can verify the
# bin/kunskap source explicitly snapshots `git status --porcelain` BEFORE the
# spawn — this is the contract anchor. If a future refactor moves the
# snapshot to AFTER the spawn (or removes it), this test fails specifically.

@test "bin/kunskap captures git status --porcelain before spawning the agent" {
  grep -A 5 '^cmd_lint' "$KUNSKAP_BIN" >/dev/null  # function exists
  grep -q 'status_before' "$KUNSKAP_BIN"
  grep -q 'status_after' "$KUNSKAP_BIN"
  # The before-snapshot line must precede the claude invocation textually.
  before_line=$(grep -n 'status_before=' "$KUNSKAP_BIN" | head -1 | cut -d: -f1)
  spawn_line=$(grep -n 'claude --plugin-dir' "$KUNSKAP_BIN" | tail -1 | cut -d: -f1)
  [[ "$before_line" -lt "$spawn_line" ]]
}

@test "bin/kunskap also snapshots HEAD oid (write+commit case)" {
  # Pass-1 finding: pre/post `git status --porcelain` alone misses a
  # write-and-commit cycle that ends with a clean working tree. Capturing
  # the HEAD oid before+after closes that gap.
  grep -q 'head_before' "$KUNSKAP_BIN"
  grep -q 'head_after'  "$KUNSKAP_BIN"
  grep -q 'rev-parse HEAD' "$KUNSKAP_BIN"
}

@test "bin/kunskap uses rev-parse --is-inside-work-tree, not -d \$vault/.git" {
  # Pass-1 finding: `[[ -d $vault/.git ]]` skips git worktrees (where .git
  # is a file pointing at the worktree's gitdir). Use the canonical check.
  grep -q 'rev-parse --is-inside-work-tree' "$KUNSKAP_BIN"
}

@test "bin/kunskap correctly captures agent exit code without ! inversion" {
  # Pass-1 block-ship: `if ! cmd; then x=$?; fi` returns 0 (status of !),
  # losing the real failure code. The correct form is `if cmd; then 0;
  # else x=$?; fi`. Source-grep for the corrected pattern in cmd_lint.
  awk '/^cmd_lint\(\)/{flag=1} flag{print} /^}$/ && flag{flag=0; exit}' "$KUNSKAP_BIN" \
    | grep -q 'if agent_out='
  awk '/^cmd_lint\(\)/{flag=1} flag{print} /^}$/ && flag{flag=0; exit}' "$KUNSKAP_BIN" \
    | grep -q 'else'
  awk '/^cmd_lint\(\)/{flag=1} flag{print} /^}$/ && flag{flag=0; exit}' "$KUNSKAP_BIN" \
    | grep -q 'agent_status=\$?'
  ! awk '/^cmd_lint\(\)/{flag=1} flag{print} /^}$/ && flag{flag=0; exit}' "$KUNSKAP_BIN" \
    | grep -q 'if ! agent_out='
}

@test "bin/kunskap exit-code semantics are encoded (json→0, text-with-findings→1, invariant-violation→2)" {
  # All three return-paths must be present in cmd_lint. We check by grepping
  # for the distinguishing comments + return statements.
  grep -q 'Exit 0 for JSON' "$KUNSKAP_BIN"
  grep -q 'return 1' "$KUNSKAP_BIN"
  grep -q 'return 2' "$KUNSKAP_BIN"
  grep -q 'MUST 8 violation' "$KUNSKAP_BIN"
}
