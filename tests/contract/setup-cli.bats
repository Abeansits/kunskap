#!/usr/bin/env bats
# CLI-surface tests for `bin/kunskap setup` — the non-interactive composer
# behind /kunskap:setup. No LLM, no auth. Exercises arg parsing, validation,
# composition with cmd_config_user / cmd_init / cmd_learn_enable, the
# multiplayer roles.toml mutation, and the --yes propagation discipline.
#
# Each test runs in a fresh temp project + temp XDG so the user's real
# identity file and .claude/ markers are never touched.

load helpers

setup() {
  setup_proj_xdg
  TMPVAULT="$(mktemp -d -t kunskap-setup-vault.XXXXXX)"
  rm -rf "$TMPVAULT"  # init wants the path absent or non-vault-empty
  export TMPVAULT
}

teardown() {
  cleanup_temp_dirs TMPPROJ TMPXDG TMPVAULT
}

# ---------- arg parsing + validation ----------

@test "setup requires --vault" {
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" setup --yes
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"--vault"* ]]
}

@test "setup rejects --name without --host (Risk #5 partial-identity)" {
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" setup --name vigil --vault "$TMPVAULT" --init --yes
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"must be set together"* ]]
}

@test "setup rejects --host without --name" {
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" setup --host laptop --vault "$TMPVAULT" --init --yes
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"must be set together"* ]]
}

@test "setup rejects flag-as-value" {
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" setup --vault --yes
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"got next flag"* ]]
}

@test "setup rejects unknown flag" {
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" setup --vault "$TMPVAULT" --bogus --yes
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"unknown extra args"* ]]
}

@test "setup rejects --init when vault is already a kunskap vault" {
  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" init "$TMPVAULT" --name "Existing" >/dev/null
  run "$KUNSKAP_BIN" setup --name vigil --host laptop --vault "$TMPVAULT" --init --yes
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"already a kunskap vault"* ]]
}

@test "setup without --init refuses missing vault" {
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" setup --name vigil --host laptop --vault /nonexistent/setup-vault-$$ --yes
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"vault not found"* ]]
  [[ "$output" == *"--init"* ]]
}

@test "setup without --init refuses non-kunskap directory" {
  cd "$TMPPROJ"
  not_a_vault="$(mktemp -d -t kunskap-not-vault.XXXXXX)"
  run "$KUNSKAP_BIN" setup --name vigil --host laptop --vault "$not_a_vault" --yes
  rm -rf "$not_a_vault"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"not a kunskap vault"* ]]
}

@test "setup resolves a relative --vault to absolute (warns)" {
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" setup --name vigil --host laptop --vault relpath --init --yes
  # We don't assert success — relpath under TMPPROJ may collide with init's
  # "non-empty target" guard if the test harness leaves anything behind.
  # The contract under test is: the warning fires + the resolved path
  # contains TMPPROJ.
  [[ "$output" == *"was relative; resolved to"* ]]
  [[ "$output" == *"$TMPPROJ"* ]]
}

@test "setup without --name refuses fresh shell with no identity" {
  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" init "$TMPVAULT" --name "Existing" >/dev/null
  run "$KUNSKAP_BIN" setup --vault "$TMPVAULT" --yes
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"no identity set"* ]]
}

# ---------- happy path: branch A (fresh user, --init, --multiplayer) ----------

@test "setup --init --multiplayer composes the four steps end-to-end" {
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" setup --name vigil --host laptop --vault "$TMPVAULT" --init --multiplayer --yes
  [[ "$status" -eq 0 ]]

  # Identity written.
  [[ -f "$TMPXDG/kunskap/identity.toml" ]]
  grep -Fxq 'name  = "vigil"' "$TMPXDG/kunskap/identity.toml"
  grep -Fxq 'host  = "laptop"' "$TMPXDG/kunskap/identity.toml"

  # Vault scaffolded.
  [[ -f "$TMPVAULT/_meta/kunskap.toml" ]]
  [[ -f "$TMPVAULT/_meta/roles.toml"   ]]
  [[ -d "$TMPVAULT/raw/inbox"          ]]
  [[ -d "$TMPVAULT/wiki"               ]]

  # Multiplayer mutation applied to BOTH roles.
  grep -Fxq 'primary = "vigil@laptop"' "$TMPVAULT/_meta/roles.toml"
  # Two roles, two primary lines:
  [[ "$(grep -c '^primary = "vigil@laptop"$' "$TMPVAULT/_meta/roles.toml")" -eq 2 ]]
  ! grep -Fxq 'primary = "TBD"' "$TMPVAULT/_meta/roles.toml"

  # --init produced a single baseline commit; inbox is clean (the
  # status panel must report "0 uncommitted notes" or the setup wasn't
  # honest about being done).
  [[ "$(git -C "$TMPVAULT" log --oneline | wc -l | tr -d ' ')" -eq 1 ]]
  [[ -z "$(git -C "$TMPVAULT" status --porcelain --untracked-files=all)" ]]

  # Project marker written, CLAUDE.md injected.
  [[ -f "$TMPPROJ/.claude/kunskap.json" ]]
  [[ -f "$TMPPROJ/CLAUDE.md"            ]]
  grep -Fq '<!-- BEGIN kunskap (managed) -->' "$TMPPROJ/CLAUDE.md"

  # Setup printed each step heading + the final status panel verbatim.
  [[ "$output" == *"setup [1/4]"*   ]]
  [[ "$output" == *"setup [2/4]"*   ]]
  [[ "$output" == *"setup [3/4]"*   ]]
  [[ "$output" == *"setup [4/4]"*   ]]
  [[ "$output" == *"INBOX: 0"*      ]]
}

# ---------- skip-identity: branch B (existing identity, plain bind) ----------

@test "setup with existing identity + existing vault skips both bootstrap steps" {
  cd "$TMPPROJ"
  # Pre-seed: identity + a kunskap-init'd vault.
  write_identity_toml "$TMPXDG" "existing" "machine"
  TMPVAULT="$(make_empty_init_vault)"

  run "$KUNSKAP_BIN" setup --vault "$TMPVAULT" --yes
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"using existing identity existing@machine"* ]]
  [[ "$output" == *"reusing existing vault"*                   ]]
  # Roles stay TBD (no --multiplayer).
  grep -Fxq 'primary = "TBD"' "$TMPVAULT/_meta/roles.toml"
  # Project marker written.
  [[ -f "$TMPPROJ/.claude/kunskap.json" ]]
}

# ---------- branch C: re-run on already-enabled project is idempotent ----------

@test "setup re-run on an already-enabled project is idempotent" {
  cd "$TMPPROJ"
  write_identity_toml "$TMPXDG" "existing" "machine"
  TMPVAULT="$(make_empty_init_vault)"

  "$KUNSKAP_BIN" setup --vault "$TMPVAULT" --yes >/dev/null
  marker_first="$(cat "$TMPPROJ/.claude/kunskap.json")"
  claudemd_first="$(grep -F 'kunskap:hash' "$TMPPROJ/CLAUDE.md")"

  # Sleep 1s so confirmed_at definitely changes (it's second-resolution).
  sleep 1
  run "$KUNSKAP_BIN" setup --vault "$TMPVAULT" --yes
  [[ "$status" -eq 0 ]]
  marker_second="$(cat "$TMPPROJ/.claude/kunskap.json")"
  claudemd_second="$(grep -F 'kunskap:hash' "$TMPPROJ/CLAUDE.md")"

  # Marker confirmed_at refreshed (different).
  [[ "$marker_first" != "$marker_second" ]]
  # CLAUDE.md fingerprint unchanged (idempotent body).
  [[ "$claudemd_first" == "$claudemd_second" ]]
  # No spurious managed block duplication.
  [[ "$(grep -c '<!-- BEGIN kunskap (managed) -->' "$TMPPROJ/CLAUDE.md")" -eq 1 ]]
}

# ---------- identity-overwrite confirmation ----------

@test "setup refuses --name/--host overwrite of an existing different identity without --yes" {
  cd "$TMPPROJ"
  write_identity_toml "$TMPXDG" "old" "host1"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" init "$TMPVAULT" --name "Pre" >/dev/null
  run "$KUNSKAP_BIN" setup --name new --host host2 --vault "$TMPVAULT"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"identity already set to old@host1"* ]]
  [[ "$output" == *"--yes"* ]]
}

@test "setup --yes confirms identity overwrite and proceeds" {
  cd "$TMPPROJ"
  write_identity_toml "$TMPXDG" "old" "host1"
  TMPVAULT="$(make_empty_init_vault)"
  run "$KUNSKAP_BIN" setup --name new --host host2 --vault "$TMPVAULT" --yes
  [[ "$status" -eq 0 ]]
  grep -Fxq 'name  = "new"'   "$TMPXDG/kunskap/identity.toml"
  grep -Fxq 'host  = "host2"' "$TMPXDG/kunskap/identity.toml"
}

# ---------- multiplayer roles.toml mutation ----------

@test "setup --multiplayer on existing vault commits a roles-only change" {
  cd "$TMPPROJ"
  write_identity_toml "$TMPXDG" "vigil" "laptop"
  TMPVAULT="$(make_empty_init_vault)"

  run "$KUNSKAP_BIN" setup --vault "$TMPVAULT" --multiplayer --yes
  [[ "$status" -eq 0 ]]

  # Both primaries set.
  [[ "$(grep -c '^primary = "vigil@laptop"$' "$TMPVAULT/_meta/roles.toml")" -eq 2 ]]

  # Two commits total: the seed + the roles update.
  [[ "$(git -C "$TMPVAULT" log --oneline | wc -l | tr -d ' ')" -eq 2 ]]

  # The new commit only touches roles.toml.
  changed="$(git -C "$TMPVAULT" diff-tree --no-commit-id --name-only -r HEAD)"
  [[ "$changed" == "_meta/roles.toml" ]]

  # Working tree clean.
  [[ -z "$(git -C "$TMPVAULT" status --porcelain --untracked-files=all)" ]]
}

@test "setup --multiplayer with shared vault + no remote skips push silently" {
  cd "$TMPPROJ"
  write_identity_toml "$TMPXDG" "vigil" "laptop"
  # Hand-craft a shared = true vault with no remote.
  mkdir -p "$TMPVAULT/_meta" "$TMPVAULT/raw/inbox" "$TMPVAULT/wiki"
  cat > "$TMPVAULT/_meta/kunskap.toml" <<EOF
[vault]
name = "shared-no-remote"
shared = true
EOF
  cat > "$TMPVAULT/_meta/roles.toml" <<EOF
[roles.curator]
primary = "TBD"

[roles.linter]
primary = "TBD"
EOF
  ( cd "$TMPVAULT" && git init -q && git add . && \
    git -c user.email=t@x -c user.name=t commit -q -m seed )

  run "$KUNSKAP_BIN" setup --vault "$TMPVAULT" --multiplayer --yes
  [[ "$status" -eq 0 ]]
  # Did not error on missing remote; primaries set; no "push failed" because
  # no remote was even attempted.
  [[ "$(grep -c '^primary = "vigil@laptop"$' "$TMPVAULT/_meta/roles.toml")" -eq 2 ]]
  [[ "$output" != *"push failed"* ]]
  [[ "$output" != *"pushed scaffold to origin"* ]]
}

# ---------- --yes propagation discipline (Risk #7) ----------

@test "setup without --yes propagates the Risk #7 prompt to learn enable" {
  cd "$TMPPROJ"
  write_identity_toml "$TMPXDG" "vigil" "laptop"
  TMPVAULT="$(make_empty_init_vault)"
  # No --yes, no KUNSKAP_AUTO_CONFIRM, /dev/null on stdin → cmd_learn_enable
  # should refuse rather than auto-confirming.
  run bash -c "'$KUNSKAP_BIN' setup --vault '$TMPVAULT' </dev/null"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"cancelled"* ]]
  # Marker NOT written.
  [[ ! -f "$TMPPROJ/.claude/kunskap.json" ]]
}

@test "setup honours KUNSKAP_AUTO_CONFIRM=1 in lieu of --yes" {
  cd "$TMPPROJ"
  write_identity_toml "$TMPXDG" "vigil" "laptop"
  TMPVAULT="$(make_empty_init_vault)"
  run bash -c "KUNSKAP_AUTO_CONFIRM=1 '$KUNSKAP_BIN' setup --vault '$TMPVAULT' </dev/null"
  [[ "$status" -eq 0 ]]
  [[ -f "$TMPPROJ/.claude/kunskap.json" ]]
}

# ---------- composition discipline (helps catch /simplify regressions) ----------

@test "cmd_setup body delegates to existing cmd_* functions (composition lock)" {
  body="$(fn_body cmd_setup)"
  # Composition: each load-bearing step calls the existing verb's function.
  [[ "$body" == *"cmd_config_user "* ]]
  [[ "$body" == *"cmd_init "* ]]
  [[ "$body" == *"cmd_learn_enable "* ]]
  [[ "$body" == *"cmd_learn_status"*  ]]
  # Anti-duplication: setup must NOT reimplement the marker write or the
  # CLAUDE.md inject (those live behind cmd_learn_enable).
  [[ "$body" != *"inject_claudemd"* ]]
  [[ "$body" != *"marker_path"*     ]]
  # Pass-1 (Codex) added the mid-rebase guard — lock it so a future edit
  # can't drop it silently.
  [[ "$body" == *"mid_rebase_guard"* ]]
  # Pass-2 (Codex) flagged that `[[ -d "$vault/.git" ]]` skips git worktrees
  # (where .git is a file). Lock the canonical detection — and the absence
  # of the naive form — so it can't regress.
  [[ "$body" == *"rev-parse --is-inside-work-tree"* ]]
  [[ "$body" != *"-d \"\$vault/.git\""* ]]
}

@test "set_role_primaries places its tempfile next to the target (atomic-mv on same fs)" {
  # Pass-2 (Codex) flagged that mktemp -t lands in TMPDIR which on macOS is
  # a different filesystem from the vault, making the mv copy+unlink rather
  # than atomic rename. The fix is to mktemp inside the vault. Lock by
  # grepping the function body — the mktemp arg must reference \$file, not
  # the bare -t flag form.
  body="$(fn_body set_role_primaries)"
  [[ "$body" == *'mktemp "$file.'* ]]
  [[ "$body" != *'mktemp -t kunskap-roles'* ]]
}

# ---------- mid-rebase guard (Codex Pass 1 finding) ----------

@test "setup refuses to mutate a vault that's mid-rebase" {
  cd "$TMPPROJ"
  write_identity_toml "$TMPXDG" "vigil" "laptop"
  TMPVAULT="$(make_empty_init_vault)"
  # Simulate mid-rebase by creating .git/rebase-merge (matches mid_rebase_guard's check).
  mkdir -p "$TMPVAULT/.git/rebase-merge"
  run "$KUNSKAP_BIN" setup --vault "$TMPVAULT" --multiplayer --yes
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"rebase"* ]]
  # Setup must not have written a marker — guard fires before any mutation.
  [[ ! -f "$TMPPROJ/.claude/kunskap.json" ]]
  # roles.toml unchanged (still TBD primaries).
  grep -Fxq 'primary = "TBD"' "$TMPVAULT/_meta/roles.toml"
}

# ---------- set_role_primaries: named exit codes actually fire (Pass-1 bug fix) ----------

@test "set_role_primaries reports a clear error when [roles.curator] section is missing" {
  cd "$TMPPROJ"
  write_identity_toml "$TMPXDG" "vigil" "laptop"
  TMPVAULT="$(make_empty_init_vault)"
  # Hand-break roles.toml: drop the [roles.curator] section header.
  printf '[roles.linter]\nprimary = "TBD"\n' > "$TMPVAULT/_meta/roles.toml"
  run "$KUNSKAP_BIN" setup --vault "$TMPVAULT" --multiplayer --yes
  [[ "$status" -ne 0 ]]
  # Must surface the section-missing error, NOT a generic "awk rc=0".
  [[ "$output" == *"missing"* ]]
  [[ "$output" == *"[roles.curator]"* || "$output" == *"[roles.linter]"* ]]
  [[ "$output" != *"awk rc=0"* ]]
}

@test "set_role_primaries reports a clear error when a [roles.X] section is missing its primary line" {
  cd "$TMPPROJ"
  write_identity_toml "$TMPXDG" "vigil" "laptop"
  TMPVAULT="$(make_empty_init_vault)"
  # Hand-break roles.toml: drop the primary line under [roles.curator].
  cat > "$TMPVAULT/_meta/roles.toml" <<'EOF'
[roles.curator]

[roles.linter]
primary = "TBD"
EOF
  run "$KUNSKAP_BIN" setup --vault "$TMPVAULT" --multiplayer --yes
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"primary"* ]]
  [[ "$output" != *"awk rc=0"* ]]
}

@test "set_role_primaries is atomic — partial failure leaves roles.toml unchanged" {
  cd "$TMPPROJ"
  write_identity_toml "$TMPXDG" "vigil" "laptop"
  TMPVAULT="$(make_empty_init_vault)"
  # Hand-break: linter section is missing, curator is canonical. Old
  # two-pass code would have written curator=vigil@laptop before erroring
  # on linter; the one-pass refactor must leave both untouched.
  cat > "$TMPVAULT/_meta/roles.toml" <<'EOF'
[roles.curator]
primary = "TBD"
EOF
  before_sha="$(shasum "$TMPVAULT/_meta/roles.toml" | cut -d' ' -f1)"
  run "$KUNSKAP_BIN" setup --vault "$TMPVAULT" --multiplayer --yes
  [[ "$status" -ne 0 ]]
  after_sha="$(shasum "$TMPVAULT/_meta/roles.toml" | cut -d' ' -f1)"
  [[ "$before_sha" == "$after_sha" ]]
}
