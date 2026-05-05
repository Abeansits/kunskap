#!/usr/bin/env bats
# Behavioral tests — actually spawn the linter agent on a seeded scenario
# vault and assert end-to-end finding emission per the linter contract.
# Gated on KUNSKAP_LIVE_TESTS=1; requires Claude Code on PATH + Anthropic auth.
#
# Default CI does NOT run these (cost + no API key in fork PRs). Run locally:
#   KUNSKAP_LIVE_TESTS=1 bats tests/contract/linter-behavioral.bats
#
# Each test seeds ONE specific scenario (drift, stale draft, offline arrival,
# curator-idle, stub cluster, identity mismatch) and asserts the matching
# finding type appears in the linter's stdout. The static-prompt suite asserts
# the rule appears in agents/linter.md; this suite asserts the agent obeys.

load helpers

setup_file() {
  if [[ "${KUNSKAP_LIVE_TESTS:-}" != "1" ]]; then
    export BATS_BEHAVIORAL_SKIP="set KUNSKAP_LIVE_TESTS=1 to run behavioral linter tests"
  elif ! command -v claude >/dev/null; then
    export BATS_BEHAVIORAL_SKIP="claude CLI not on PATH"
  fi
}

setup() {
  [[ -z "${BATS_BEHAVIORAL_SKIP:-}" ]] || skip "$BATS_BEHAVIORAL_SKIP"
  TMPVAULT="$(seed_lint_vault)"
  export TMPVAULT
}

teardown() {
  cleanup_temp_dirs TMPVAULT
}

# Seed an init'd vault with no curator-output yet (empty wiki/learnings/, empty
# Archives/, fresh _drafts/). Each test then layers ONE scenario on top.
seed_lint_vault() {
  local v
  v="$(mktemp -d -t kunskap-lint.XXXXXX)"
  rm -rf "$v"
  KUNSKAP_AUTO_CONFIRM=1 "$KUNSKAP_BIN" init "$v" --name "Lint Test" >/dev/null
  ( cd "$v" && git add . && git -c user.email=test@local -c user.name=test commit -q -m "seed" ) >/dev/null
  printf '%s\n' "$v"
}

run_linter() {
  "$KUNSKAP_BIN" lint --vault "$TMPVAULT" "$@"
}

# ---------- MUST 3 — DRAFT-STALE (≥7d created) ----------

@test "MUST 3 — draft created 8d ago emits [DRAFT-STALE]" {
  local stale_date
  stale_date="$(date -u -v-8d +%Y-%m-%d 2>/dev/null || date -u -d '8 days ago' +%Y-%m-%d)"
  cat > "$TMPVAULT/wiki/_drafts/aging-topic--$stale_date.md" <<EOF
---
type: draft
lane: 2
confidence: medium
reason: meaning-changing extension awaiting triage
source_count: 1
sources:
  - raw/inbox/01-foo.md
created: $stale_date
---

# Aging topic

Body of an aging draft awaiting human triage.
EOF
  ( cd "$TMPVAULT" && git add . && git -c user.email=t@l -c user.name=t commit -q -m "seed stale draft" )
  run run_linter
  [[ "$output" == *"[DRAFT-STALE]"* ]]
  [[ "$output" == *"aging-topic"* ]]
}

@test "MUST 3 — draft deferred 15d ago emits [DRAFT-DEFERRED-STALE]" {
  local deferred_iso
  deferred_iso="$(date -u -v-15d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '15 days ago' +%Y-%m-%dT%H:%M:%SZ)"
  cat > "$TMPVAULT/wiki/_drafts/long-deferred--2026-04-15.md" <<EOF
---
type: draft
lane: 2
confidence: low
reason: deferred awaiting more sources
source_count: 1
sources:
  - raw/inbox/02-bar.md
created: 2026-04-15
deferred_at: $deferred_iso
---

# Long-deferred topic

Body.
EOF
  ( cd "$TMPVAULT" && git add . && git -c user.email=t@l -c user.name=t commit -q -m "seed deferred draft" )
  run run_linter
  [[ "$output" == *"[DRAFT-DEFERRED-STALE]"* ]]
  [[ "$output" == *"long-deferred"* ]]
}

# ---------- MUST 4 — OFFLINE-ARRIVAL (Risk #4) ----------

@test "MUST 4 — inbox author not seen in last-run + 50h-old emits [OFFLINE-ARRIVAL]" {
  local note_iso ran_iso
  note_iso="$(date -u -v-72h +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '72 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
  ran_iso="$(date -u -v-50h +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '50 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$TMPVAULT/_meta"
  cat > "$TMPVAULT/_meta/last-run.json" <<EOF
{ "curator": { "ran_at": "$ran_iso", "by": "sebastian@laptop", "inbox_processed": 0, "articles_written": 0, "drafts_routed": 0 } }
EOF
  cat > "$TMPVAULT/raw/inbox/learning-matt-discovery-${note_iso:0:10}.md" <<EOF
---
type: learning
author: matt@desktop
created: ${note_iso:0:10}
suggested_topic: hyperspectral-tooling
---

# Matt's offline discovery

Note body from a machine that wasn't online during the last curator run.
EOF
  ( cd "$TMPVAULT" && git add . && git -c user.email=t@l -c user.name=t commit -q -m "seed offline arrival" )
  run run_linter
  [[ "$output" == *"[OFFLINE-ARRIVAL]"* ]]
  [[ "$output" == *"matt"* ]]
}

# ---------- MUST 5 — CURATOR-IDLE (≥48h) ----------

@test "MUST 5 — curator ran 60h ago emits [CURATOR-IDLE]" {
  local stale_run
  stale_run="$(date -u -v-60h +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '60 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$TMPVAULT/_meta"
  cat > "$TMPVAULT/_meta/last-run.json" <<EOF
{ "curator": { "ran_at": "$stale_run", "by": "sebastian@laptop" } }
EOF
  ( cd "$TMPVAULT" && git add . && git -c user.email=t@l -c user.name=t commit -q -m "seed stale curator-run" )
  run run_linter
  [[ "$output" == *"[CURATOR-IDLE]"* ]]
}

# ---------- MUST 2 — STUB-CLUSTER (3+ refs, no article) ----------

@test "MUST 2 — orphan-stub referenced 4× emits [STUB-CLUSTER]" {
  for n in 1 2 3 4; do
    cat > "$TMPVAULT/wiki/learnings/article-$n.md" <<EOF
---
type: learning
created: 2026-05-01
---

# Article $n

Body referencing [[orphan stub]] in prose.
EOF
  done
  ( cd "$TMPVAULT" && git add . && git -c user.email=t@l -c user.name=t commit -q -m "seed orphan-stub cluster" )
  run run_linter
  [[ "$output" == *"[STUB-CLUSTER]"* ]]
  [[ "$output" == *"orphan stub"* || "$output" == *"orphan-stub"* ]]
}

# ---------- MUST 1 — DRIFT (contradictory claims across articles) ----------

@test "MUST 1 — two articles claiming contradictory facts emit [DRIFT]" {
  cat > "$TMPVAULT/wiki/learnings/git-merge-policy.md" <<'EOF'
---
type: learning
created: 2026-05-01
---

# Git merge policy

Always squash-merge feature branches into main. Squash-merging keeps the
history linear and is the project's locked policy.
EOF
  cat > "$TMPVAULT/wiki/learnings/branch-discipline.md" <<'EOF'
---
type: learning
created: 2026-05-01
---

# Branch discipline

Never squash-merge feature branches. Use merge commits to preserve the
full development history of each feature branch.
EOF
  ( cd "$TMPVAULT" && git add . && git -c user.email=t@l -c user.name=t commit -q -m "seed drift pair" )
  run run_linter
  [[ "$output" == *"[DRIFT]"* ]]
}

# ---------- MUST 6 — IDENTITY-MISMATCH (commit author not in roles.toml) ----------

@test "MUST 6 — commit by bob@y when curator.primary=alice@x emits [IDENTITY-MISMATCH]" {
  cat > "$TMPVAULT/_meta/roles.toml" <<'EOF'
[roles.curator]
primary = "alice@x"

[roles.linter]
primary = "alice@x"
EOF
  ( cd "$TMPVAULT" && git add _meta/roles.toml \
      && git -c user.email=alice@x -c user.name=alice commit -q -m "seed roles" )
  echo "test note" > "$TMPVAULT/raw/inbox/note-bob.md"
  ( cd "$TMPVAULT" && git add . \
      && git -c user.email=bob@y -c user.name=bob commit -q -m "unauthorized writer" )
  run run_linter
  [[ "$output" == *"[IDENTITY-MISMATCH]"* ]]
}

# ---------- MUST 8 — read-only invariant (vault git-status clean post-run) ----------

@test "MUST 8 — vault git status --porcelain is empty after a lint run" {
  run run_linter
  cd "$TMPVAULT"
  porcelain="$(git status --porcelain)"
  [[ -z "$porcelain" ]]
}

# ---------- format / output contract ----------

@test "lint --format json emits a parseable JSON object with findings array" {
  # Stack a couple of scenarios so we expect at least one finding.
  local stale_run
  stale_run="$(date -u -v-60h +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '60 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$TMPVAULT/_meta"
  cat > "$TMPVAULT/_meta/last-run.json" <<EOF
{ "curator": { "ran_at": "$stale_run", "by": "sebastian@laptop" } }
EOF
  ( cd "$TMPVAULT" && git add . && git -c user.email=t@l -c user.name=t commit -q -m "seed json scenario" )
  run run_linter --format json
  echo "$output" | jq -e '.findings | type == "array"' >/dev/null
  [[ "$status" -eq 0 ]]   # JSON mode always exits 0 (the JSON IS the output)
}
