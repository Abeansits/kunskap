# shellcheck shell=bash
# Test helpers for the Kunskap curator-contract suite.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
KUNSKAP_BIN="$REPO_ROOT/bin/kunskap"
CURATOR_AGENT="$REPO_ROOT/agents/curator.md"
FIXTURE_VAULT="$REPO_ROOT/tests/fixtures/curator-vault"

export REPO_ROOT KUNSKAP_BIN CURATOR_AGENT FIXTURE_VAULT

# Copy the fixture vault to a fresh temp dir, init it as a git repo with a
# single seed commit, and echo the temp path. Tests should rm -rf on teardown.
make_temp_vault() {
  local dst
  dst="$(mktemp -d -t kunskap-vault.XXXXXX)"
  cp -R "$FIXTURE_VAULT/." "$dst/"
  (
    cd "$dst"
    git init -q
    git config user.email "fixture@bats"
    git config user.name "fixture"
    git add .
    git commit -q -m "fixture: seed vault"
  )
  printf '%s\n' "$dst"
}

# grep -F (literal) for an expected clause in the curator agent prompt.
# Used by static prompt-drift tests.
prompt_contains() {
  grep -Fq "$1" "$CURATOR_AGENT"
}

make_temp_proj() { mktemp -d -t kunskap-proj.XXXXXX; }
make_temp_xdg()  { mktemp -d -t kunskap-xdg.XXXXXX; }

# Init a fresh vault and seed two drafts (one high-confidence + older, one
# low-confidence + newer). Echoes the vault path. Used by drafts-cli.bats and
# whatever P4+ needs a drafts-loaded vault.
make_vault_with_drafts() {
  local v
  v="$(mktemp -d -t kunskap-drafts.XXXXXX)"
  rm -rf "$v"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" init "$v" --name "Drafts Test" >/dev/null 2>&1
  cat > "$v/wiki/_drafts/topic-alpha--2026-04-25.md" <<'EOF'
---
type: draft
lane: 2
confidence: high
reason: meaning-changing extension
source_count: 2
sources:
  - raw/inbox/01-foo.md
  - raw/inbox/02-bar.md
created: 2026-04-25
---

# Topic alpha

Draft body proposing a meaningful change.
EOF
  cat > "$v/wiki/_drafts/topic-beta--2026-05-01.md" <<'EOF'
---
type: draft
lane: 2
confidence: low
reason: unclassifiable
source_count: 1
sources:
  - raw/inbox/99-mystery.md
created: 2026-05-01
---

# Topic beta

Body of the unclassifiable note.
EOF
  ( cd "$v" && git add . && git -c user.email=test@local -c user.name=test commit -q -m "seed drafts" ) >/dev/null
  printf '%s\n' "$v"
}

# Bats teardown helper — `[[ -d X ]] && rm -rf X` short-circuits to non-zero
# when the dir doesn't exist, which bats reports as a teardown failure. Use
# this instead. Pass any number of var names whose values are dirs to remove.
cleanup_temp_dirs() {
  local d
  for d in "$@"; do
    if [[ -n "${!d:-}" && -d "${!d}" ]]; then rm -rf "${!d}"; fi
  done
}

# Write identity.toml directly (skips a `kunskap config user` fork — used in
# hot setup paths like hooks-smoke.bats that need identity but not its CLI).
write_identity_toml() {
  local xdg="$1" name="${2:-ci}" host="${3:-runner}"
  mkdir -p "$xdg/kunskap"
  cat > "$xdg/kunskap/identity.toml" <<EOF
[user]
name  = "$name"
host  = "$host"
EOF
}
