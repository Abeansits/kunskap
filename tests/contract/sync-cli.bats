#!/usr/bin/env bats
# CLI-surface tests for `bin/kunskap sync` and the `/kunskap:sync` slash
# command (v1.1 manual lever). The CLI owns vault resolution, identity
# check, shared-vault gate, rebase guard, commit + push, and exit codes.

load helpers

setup() {
  setup_proj_xdg
}

teardown() {
  cleanup_temp_dirs TMPPROJ TMPXDG
}

set_identity() { write_identity_toml "$TMPXDG"; }

# ---------- happy + idempotent paths ----------

@test "sync: happy path — commits + pushes new inbox note against bare remote" {
  set_identity
  bare="$(mktemp -d)"
  make_bare_remote "$bare"
  vault="$(mktemp -d)"
  make_shared_vault "$vault" "$bare"
  ( cd "$vault" && git push -q -u origin HEAD:main )

  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault" >/dev/null
  echo "body" > "$vault/raw/inbox/n1.md"

  run "$KUNSKAP_BIN" sync
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"synced 1 note"* ]]
  ( cd "$vault" && git log --oneline | head -1 ) | grep -Fq 'kunskap: inbox sync (manual'
  ( cd "$bare" && git log --oneline | head -1 ) | grep -Fq 'kunskap: inbox sync (manual'

  rm -rf "$vault" "$bare"
}

@test "sync: nothing-to-sync — empty inbox prints clean message" {
  set_identity
  vault="$(mktemp -d)"
  make_shared_vault "$vault"
  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault" >/dev/null

  run "$KUNSKAP_BIN" sync
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"nothing to sync"* ]]

  rm -rf "$vault"
}

@test "sync: solo vault prints not-shared message and exits 0 (never pushes)" {
  set_identity
  vault="$(mktemp -d)"
  make_solo_vault "$vault"
  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault" >/dev/null
  echo "body" > "$vault/raw/inbox/n.md"

  run "$KUNSKAP_BIN" sync
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"not shared"* ]]
  # Confirm no commit happened.
  ! ( cd "$vault" && git log --oneline | grep -q "inbox sync" )

  rm -rf "$vault"
}

# ---------- failure / refusal paths ----------

@test "sync: identity not set — refuses with actionable message" {
  vault="$(mktemp -d)"
  make_shared_vault "$vault"
  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault" >/dev/null
  echo "body" > "$vault/raw/inbox/n.md"

  run "$KUNSKAP_BIN" sync
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"identity not set"* ]]
  rm -rf "$vault"
}

@test "sync: rebase in progress — refuses with actionable hint" {
  set_identity
  vault="$(mktemp -d)"
  make_shared_vault "$vault"
  mkdir -p "$vault/.git/rebase-merge"
  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault" >/dev/null
  echo "body" > "$vault/raw/inbox/n.md"

  run "$KUNSKAP_BIN" sync
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"mid-rebase"* || "$output" == *"rebase in progress"* ]]
  [[ "$output" == *"rebase --continue"* || "$output" == *"--abort"* ]]
  rm -rf "$vault"
}

@test "sync: push failed (no remote) — exit 1, commit landed, clear stderr" {
  set_identity
  vault="$(mktemp -d)"
  make_shared_vault "$vault"   # no remote
  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault" >/dev/null
  echo "body" > "$vault/raw/inbox/n.md"

  run "$KUNSKAP_BIN" sync
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"push failed"* ]]
  # Commit must still be on disk so the next sync can retry.
  ( cd "$vault" && git log --oneline | head -1 ) | grep -Fq 'kunskap: inbox sync (manual'
  rm -rf "$vault"
}

@test "sync: no --vault, no marker — refuses with usage hint" {
  set_identity
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" sync
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"learn enable"* || "$output" == *"--vault"* ]]
}

@test "sync: --vault flag overrides marker" {
  set_identity
  bare="$(mktemp -d)"
  make_bare_remote "$bare"
  vault="$(mktemp -d)"
  make_shared_vault "$vault" "$bare"
  ( cd "$vault" && git push -q -u origin HEAD:main )

  echo "body" > "$vault/raw/inbox/n.md"
  cd "$TMPPROJ"   # no marker here at all
  run "$KUNSKAP_BIN" sync --vault "$vault"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"synced 1 note"* ]]
  rm -rf "$vault" "$bare"
}

@test "sync: unknown flag dies clearly" {
  set_identity
  cd "$TMPPROJ"
  run "$KUNSKAP_BIN" sync --bogus
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"unknown arg"* ]]
}

# ---------- pluralization niceness ----------

@test "sync: pluralizes correctly for >1 note" {
  set_identity
  bare="$(mktemp -d)"
  make_bare_remote "$bare"
  vault="$(mktemp -d)"
  make_shared_vault "$vault" "$bare"
  ( cd "$vault" && git push -q -u origin HEAD:main )

  cd "$TMPPROJ"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$vault" >/dev/null
  echo a > "$vault/raw/inbox/a.md"
  echo b > "$vault/raw/inbox/b.md"
  echo c > "$vault/raw/inbox/c.md"

  run "$KUNSKAP_BIN" sync
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"synced 3 notes"* ]]
  rm -rf "$vault" "$bare"
}
