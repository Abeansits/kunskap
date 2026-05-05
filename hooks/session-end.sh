#!/usr/bin/env bash
# Kunskap session-end hook — commit + push inbox capture for shared vaults.
#
# HARD CONTRACT: must never block session end. Every error path exits 0
# with a stderr message. See docs/kunskap-design.md §Q6.
#
# session_id comes from the hook's stdin JSON (canonical hook reference).
# CLAUDE_SESSION_ID is NOT set by Claude Code.

set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[[ -n "$PLUGIN_ROOT" && -f "$PLUGIN_ROOT/hooks/_shared.sh" ]] || exit 0
# shellcheck source=hooks/_shared.sh
. "$PLUGIN_ROOT/hooks/_shared.sh"

kunskap_marker_path >/dev/null   || exit 0
kunskap_identity_set             || exit 0
vault="$(kunskap_resolve_vault)" || exit 0
kunskap_is_shared "$vault"       || exit 0

# Pull session_id from stdin JSON, fall back to "unknown".
session_id="unknown"
if [[ ! -t 0 ]]; then
  hook_input="$(cat 2>/dev/null || true)"
  if [[ -n "$hook_input" ]]; then
    parsed="$(printf '%s' "$hook_input" | jq -r '.session_id // empty' 2>/dev/null || true)"
    [[ -n "$parsed" ]] && session_id="$parsed"
  fi
fi

bin="$(kunskap_bin)" || exit 0
who="$("$bin" whoami 2>/dev/null || echo unknown)"

cd "$vault" || {
  echo "Kunskap: cannot cd to vault $vault; skipping push" >&2
  exit 0
}

git add raw/inbox 2>/dev/null || {
  echo "Kunskap: \`git add raw/inbox\` failed (pre-init vault?); skipping commit" >&2
  exit 0
}

# Nothing changed → no commit, no push.
git diff --cached --quiet 2>/dev/null && exit 0

git commit --quiet -m "kunskap: inbox capture from session ${session_id} (${who})" \
  || { echo "Kunskap: vault commit failed; will retry next session" >&2; exit 0; }

git push --quiet 2>/dev/null \
  || echo "Kunskap: vault push failed; will retry next session" >&2

exit 0
