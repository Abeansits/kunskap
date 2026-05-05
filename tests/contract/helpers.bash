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
