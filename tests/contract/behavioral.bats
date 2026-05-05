#!/usr/bin/env bats
# Behavioral tests — actually spawn the curator agent on the fixture vault and
# assert end-to-end §Curator contract outcomes. Gated on KUNSKAP_LIVE_TESTS=1
# because they require Claude Code on PATH and Anthropic auth.
#
# Default CI does NOT run these (no API key in fork PRs, cost). Run locally:
#   KUNSKAP_LIVE_TESTS=1 bats tests/contract/behavioral.bats
#
# Each test maps to a §Curator contract rule. The static-prompt suite asserts
# the rule appears in the prompt; this suite asserts the agent actually obeys.

load helpers

setup() {
  if [[ "${KUNSKAP_LIVE_TESTS:-}" != "1" ]]; then
    skip "set KUNSKAP_LIVE_TESTS=1 to run behavioral contract tests"
  fi
  command -v claude >/dev/null || skip "claude CLI not on PATH"
  TMPVAULT="$(make_temp_vault)"
  export TMPVAULT
}

teardown() {
  if [[ -n "${TMPVAULT:-}" && -d "$TMPVAULT" ]]; then rm -rf "$TMPVAULT"; fi
}

run_curator() {
  "$KUNSKAP_BIN" curate --vault "$TMPVAULT"
}

@test "MUST 1 — git log shows >= N atomic per-article commits, not one bulk commit" {
  run_curator
  cd "$TMPVAULT"
  total=$(git log --oneline | wc -l | tr -d ' ')
  # 1 seed commit + at least one per inbox file processed (>=9) → >= 10
  [[ "$total" -ge 10 ]]
  # And: no single commit touches more than one article body
  bulk=$(git log --pretty=format:%H | while read -r h; do
    n=$(git show --name-only --pretty=format: "$h" | grep -E '^wiki/(learnings|ideas|patterns)/[^/]+\.md$' | wc -l | tr -d ' ')
    [[ "$n" -gt 1 ]] && echo "$h:$n"
  done)
  [[ -z "$bulk" ]]
}

@test "MUST 2 — hand-edited worktree-discipline.md is preserved, update routed to _drafts/" {
  run_curator
  grep -q "HUMAN HAND-EDIT" "$TMPVAULT/wiki/learnings/worktree-discipline.md"
  ls "$TMPVAULT/wiki/_drafts/" | grep -E "worktree-discipline.*update" >/dev/null
}

@test "MUST 3 — every inbox file ends up in Archives/processed-inbox or in a draft" {
  run_curator
  remaining=$(find "$TMPVAULT/raw/inbox" -name '*.md' | wc -l | tr -d ' ')
  [[ "$remaining" -eq 0 ]]
  archived=$(find "$TMPVAULT/Archives/processed-inbox" -name '*-2026-05-02.md' | wc -l | tr -d ' ')
  drafts=$(find "$TMPVAULT/wiki/_drafts" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  [[ $((archived + drafts)) -ge 9 ]]
}

@test "MUST 3 — Lane 2 draft carries confidence + reason + source_count frontmatter" {
  run_curator
  draft="$(find "$TMPVAULT/wiki/_drafts" -name '*lane2*' -o -name '*bash-discipline*' | head -1)"
  [[ -n "$draft" ]]
  grep -E "^confidence:" "$draft"
  grep -E "^reason:" "$draft"
  grep -E "^source_count:" "$draft"
}

@test "Operating norm 3 — Lane 2 with invitation promotes into article body" {
  run_curator
  grep -q "N=5\|fifth\|5th confirmation" "$TMPVAULT/wiki/learnings/two-pass-codex-review.md"
  ! ls "$TMPVAULT/wiki/_drafts/" 2>/dev/null | grep -q "two-pass-codex-review"
}

@test "MUST 4 — Sources footer has per-source ### sub-headings, not a merged block" {
  run_curator
  for f in "$TMPVAULT/wiki/learnings/"*.md; do
    awk '/^## Sources/,0' "$f" | grep -E "^### " >/dev/null
  done
}

@test "MUST 4 — multi-finding inbox file appears in multiple articles' sources:" {
  run_curator
  hits=$(grep -lE "04-multi-finding-2026-05-02\.md" "$TMPVAULT/wiki/learnings/"*.md "$TMPVAULT/wiki/ideas/"*.md 2>/dev/null | wc -l | tr -d ' ')
  [[ "$hits" -ge 2 ]]
}

@test "Wikilinks — multi-ref stub creates wiki/concepts/idle-heartbeat.md" {
  run_curator
  [[ -f "$TMPVAULT/wiki/concepts/idle-heartbeat.md" ]]
}

@test "Wikilinks — name-mismatch adds alias to existing pattern file" {
  run_curator
  grep -E "^aliases:.*threat-led readme hook" "$TMPVAULT/wiki/patterns/threat-led-readme-hook.md"
}

@test "MUST 5 — vault scope: no writes outside the temp vault" {
  before="$(stat -f %m "$REPO_ROOT/agents/curator.md")"
  run_curator
  after="$(stat -f %m "$REPO_ROOT/agents/curator.md")"
  [[ "$before" == "$after" ]]
}

@test "Determinism — running curator twice on rolled-back fixture yields no body diff" {
  run_curator
  snap1="$(mktemp -d)"
  cp -R "$TMPVAULT/wiki" "$snap1/wiki1"
  ( cd "$TMPVAULT" && git reset -q --hard HEAD~$(($(git log --oneline | wc -l) - 1)) )
  run_curator
  diff -ruN --strip-trailing-cr \
    -I '^last_curated:' -I '^created:' \
    "$snap1/wiki1" "$TMPVAULT/wiki" >/dev/null
  rm -rf "$snap1"
}
