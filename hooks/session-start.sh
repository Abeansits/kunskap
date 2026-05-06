#!/usr/bin/env bash
# Kunskap session-start hook — pull the shared vault when opted in.
#
# HARD CONTRACT: must never block session start. Every error path exits 0
# with a stderr message. Missing identity, missing vault, missing
# _meta/kunskap.toml, network failure, git conflict — all soft.
# See docs/kunskap-design.md §Q6 and Risk #7.

# `set -e` is intentionally OFF: per-step `||` guards catch expected
# failures, but we never want an uncaught non-zero to propagate as a
# blocked session. `-u` and `pipefail` stay on for hygiene.
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[[ -n "$PLUGIN_ROOT" && -f "$PLUGIN_ROOT/hooks/_shared.sh" ]] || exit 0
# shellcheck source=hooks/_shared.sh
. "$PLUGIN_ROOT/hooks/_shared.sh"

kunskap_marker_path >/dev/null || exit 0

# Missing identity would commit under "unknown" — refuse instead.
if ! kunskap_identity_set >/dev/null; then
  echo "Kunskap: identity not set; run \`kunskap config user --name <slug> --host <host>\`" >&2
  exit 0
fi

vault="$(kunskap_resolve_vault)" || {
  echo "Kunskap: vault path missing or marker malformed; skipping pull" >&2
  exit 0
}

kunskap_is_shared "$vault" || exit 0

if kunskap_rebase_in_progress "$vault"; then
  echo "Kunskap: vault $vault has a rebase in progress; skipping pull. Resolve with \`git -C $vault rebase --continue\` or \`--abort\` before the next session." >&2
  exit 0
fi

( cd "$vault" && git pull --rebase --autostash --quiet ) \
  || echo "Kunskap: vault pull failed; continuing with local copy" >&2

# Passive nudge: surface uncommitted inbox notes left by a prior session
# (rare — needs the PostToolUse hook to have died mid-commit / mid-push).
if [[ -d "$vault/raw/inbox" ]]; then
  # `--untracked-files=all` so untracked individual notes are counted (not
  # collapsed into a `?? raw/inbox/` directory line); matches the CLI helper
  # `count_uncommitted_inbox` semantics in bin/kunskap.
  pending=$(git -C "$vault" status --porcelain --untracked-files=all -- raw/inbox 2>/dev/null | grep -c . || true)
  if [[ "$pending" -gt 0 ]]; then
    echo "Kunskap: vault pulled. ⚠ $pending uncommitted inbox note(s) from prior session — run /kunskap:sync to push." >&2
  fi
fi

exit 0
