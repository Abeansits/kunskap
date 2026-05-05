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

( cd "$vault" && git pull --rebase --autostash --quiet ) \
  || echo "Kunskap: vault pull failed; continuing with local copy" >&2

exit 0
