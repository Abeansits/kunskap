#!/usr/bin/env bats
# Hook contract for hooks/post-write-sync.sh — the v1.1 PostToolUse(Write|Edit)
# async per-write inbox sync. Replaces the v1.0 SessionEnd push.
#
# HARD CONTRACTS asserted here:
#   - Inbox-path write triggers commit + push (against a fake bare remote).
#   - Non-inbox path write is a no-op (no commit).
#   - Path with `..` traversal is rejected even when the prefix would match.
#   - Failed push exits 0 (never blocks the agent).
#   - Empty inbox change exits 0 with no empty commit.
#   - No marker / not shared / rebase in progress → fail-soft no-op.

load helpers

POST_WRITE="$REPO_ROOT/hooks/post-write-sync.sh"

setup() {
  setup_proj_xdg
  export CLAUDE_PLUGIN_ROOT="$REPO_ROOT"
  export CLAUDE_PROJECT_DIR="$TMPPROJ"
  # Run synchronously so we can assert post-conditions without sleeping.
  export KUNSKAP_HOOK_NO_BG=1
}

teardown() {
  cleanup_temp_dirs TMPPROJ TMPXDG
  unset CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR KUNSKAP_HOOK_NO_BG
}

set_identity() { write_identity_toml "$TMPXDG"; }
write_marker() {
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" learn enable --vault "$1" >/dev/null
}

# Init a shared vault git repo at $1 with an inbox/, optional remote at $2.
make_shared_vault() {
  local vault="$1" remote="${2-}"
  mkdir -p "$vault/_meta" "$vault/raw/inbox"
  cat > "$vault/_meta/kunskap.toml" <<EOF
[vault]
name = "post-write-vault"
shared = true
EOF
  (
    cd "$vault"
    git init -q
    git config user.email smoke@bats
    git config user.name  smoke
    [[ -n "$remote" ]] && git remote add origin "$remote" || true
    git add .
    git commit -q -m "smoke: seed"
  )
}

# Init a bare repo at $1 to act as `origin` for pushes that should succeed.
make_bare_remote() { git init -q --bare "$1"; }

run_hook() {
  local payload="$1"
  printf '%s' "$payload" | "$POST_WRITE"
}

# ---------- happy path ----------

@test "post-write-sync: inbox write commits + pushes against a real bare remote" {
  bare="$(mktemp -d -t kunskap-bare.XXXXXX)"
  make_bare_remote "$bare"
  vault="$(mktemp -d -t kunskap-vault.XXXXXX)"
  make_shared_vault "$vault" "$bare"
  ( cd "$vault" && git push -q -u origin HEAD:main )
  write_marker "$vault"
  set_identity

  note="$vault/raw/inbox/learning-foo-2026-05-06.md"
  echo "body" > "$note"

  payload="$(jq -n --arg p "$note" '{tool_input:{file_path:$p, content:"body"}}')"
  run run_hook "$payload"

  [[ "$status" -eq 0 ]]
  ( cd "$vault" && git log --oneline | head -1 ) | grep -q 'kunskap: inbox capture (auto'
  ( cd "$bare" && git log --oneline | head -1 ) | grep -q 'kunskap: inbox capture (auto'

  rm -rf "$vault" "$bare"
}

# ---------- skip / no-op paths ----------

@test "post-write-sync: write outside inbox is a no-op (no commit)" {
  vault="$(mktemp -d -t kunskap-vault.XXXXXX)"
  make_shared_vault "$vault"
  write_marker "$vault"
  set_identity

  before=$( cd "$vault" && git rev-parse HEAD )

  payload="$(jq -n '{tool_input:{file_path:"/tmp/random/file.txt", content:"x"}}')"
  run run_hook "$payload"

  [[ "$status" -eq 0 ]]
  after=$( cd "$vault" && git rev-parse HEAD )
  [[ "$before" == "$after" ]]
  rm -rf "$vault"
}

@test "post-write-sync: traversal segment in file_path is rejected" {
  vault="$(mktemp -d -t kunskap-vault.XXXXXX)"
  make_shared_vault "$vault"
  write_marker "$vault"
  set_identity
  before=$( cd "$vault" && git rev-parse HEAD )

  # Even though the string would prefix-match "$vault/raw/inbox/", the ".."
  # segment must trip the traversal guard.
  evil="$vault/raw/inbox/../../etc/passwd"
  payload="$(jq -n --arg p "$evil" '{tool_input:{file_path:$p, content:"x"}}')"
  run run_hook "$payload"

  [[ "$status" -eq 0 ]]
  after=$( cd "$vault" && git rev-parse HEAD )
  [[ "$before" == "$after" ]]
  rm -rf "$vault"
}

@test "post-write-sync: no marker → silent exit 0" {
  payload="$(jq -n '{tool_input:{file_path:"/tmp/x", content:"x"}}')"
  run run_hook "$payload"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "post-write-sync: solo vault (shared=false) → exit 0 quiet" {
  vault="$(mktemp -d -t kunskap-vault.XXXXXX)"
  mkdir -p "$vault/_meta" "$vault/raw/inbox"
  cat > "$vault/_meta/kunskap.toml" <<EOF
[vault]
shared = false
EOF
  ( cd "$vault" && git init -q && git config user.email s@b && git config user.name s )
  write_marker "$vault"
  set_identity
  echo "body" > "$vault/raw/inbox/note.md"
  payload="$(jq -n --arg p "$vault/raw/inbox/note.md" '{tool_input:{file_path:$p}}')"
  run run_hook "$payload"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
  # No commit on solo vaults.
  ! ( cd "$vault" && git log --oneline 2>/dev/null | grep -q "inbox capture" )
  rm -rf "$vault"
}

@test "post-write-sync: rebase in progress → exit 0 + actionable stderr" {
  vault="$(mktemp -d -t kunskap-vault.XXXXXX)"
  make_shared_vault "$vault"
  mkdir -p "$vault/.git/rebase-merge"
  write_marker "$vault"
  set_identity
  echo "body" > "$vault/raw/inbox/note.md"
  payload="$(jq -n --arg p "$vault/raw/inbox/note.md" '{tool_input:{file_path:$p}}')"
  run run_hook "$payload"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"rebase in progress"* ]]
  rm -rf "$vault"
}

@test "post-write-sync: failed push (no remote) exits 0 with stderr — commit still lands" {
  vault="$(mktemp -d -t kunskap-vault.XXXXXX)"
  make_shared_vault "$vault"   # no remote
  write_marker "$vault"
  set_identity
  echo "body" > "$vault/raw/inbox/note-2026-05-06.md"
  payload="$(jq -n --arg p "$vault/raw/inbox/note-2026-05-06.md" '{tool_input:{file_path:$p}}')"
  run run_hook "$payload"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"push failed"* ]]
  ( cd "$vault" && git log --oneline | head -1 ) | grep -q 'kunskap: inbox capture (auto'
  rm -rf "$vault"
}

@test "post-write-sync: empty inbox change → exit 0 quiet (no empty commit)" {
  vault="$(mktemp -d -t kunskap-vault.XXXXXX)"
  make_shared_vault "$vault"
  write_marker "$vault"
  set_identity
  before=$( cd "$vault" && git rev-parse HEAD )
  # File is in inbox but unchanged from HEAD (we won't even create it).
  payload="$(jq -n --arg p "$vault/raw/inbox/nonexistent.md" '{tool_input:{file_path:$p}}')"
  run run_hook "$payload"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
  after=$( cd "$vault" && git rev-parse HEAD )
  [[ "$before" == "$after" ]]
  rm -rf "$vault"
}

@test "post-write-sync: missing identity → silent exit 0 (no noisy stderr)" {
  vault="$(mktemp -d -t kunskap-vault.XXXXXX)"
  make_shared_vault "$vault"
  write_marker "$vault"
  echo "body" > "$vault/raw/inbox/note.md"
  payload="$(jq -n --arg p "$vault/raw/inbox/note.md" '{tool_input:{file_path:$p}}')"
  run run_hook "$payload"
  [[ "$status" -eq 0 ]]
  # Quiet — every Write/Edit firing this would be noise; SessionStart already
  # surfaces the actionable identity message once per session.
  [[ -z "$output" ]]
  rm -rf "$vault"
}

@test "post-write-sync: malformed stdin → exit 0 no-op (no commit)" {
  vault="$(mktemp -d -t kunskap-vault.XXXXXX)"
  make_shared_vault "$vault"
  write_marker "$vault"
  set_identity
  before=$( cd "$vault" && git rev-parse HEAD )
  run run_hook "not json at all"
  [[ "$status" -eq 0 ]]
  after=$( cd "$vault" && git rev-parse HEAD )
  [[ "$before" == "$after" ]]
  rm -rf "$vault"
}
