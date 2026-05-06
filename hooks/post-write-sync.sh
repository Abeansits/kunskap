#!/usr/bin/env bash
# Kunskap PostToolUse hook — async per-write inbox sync (v1.1).
#
# Replaces the v1.0 SessionEnd push: per-write commit + push closes the
# loss window left by SIGKILL / SIGHUP / IDE-managed lifecycles where
# SessionEnd never fires. Wires into hooks.json on the `Write|Edit`
# matcher with `async: true`, and additionally backgrounds the git work
# inside the script so the agent is never blocked even if a Claude Code
# version doesn't honour `async`.
#
# HARD CONTRACTS (per design §Q6 + v1.1 brief):
#   - Never block. Every error path exits 0 with a stderr message.
#   - Never act on path traversal. Refuse any "../" segment in
#     tool_input.file_path, even when string-prefix would match.
#   - Never push when a rebase is in progress.
#   - Never act on writes outside <vault>/raw/inbox/.
#
# Test hook: KUNSKAP_HOOK_NO_BG=1 runs the git work synchronously so the
# bats suite can assert post-conditions without sleeping.

set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[[ -n "$PLUGIN_ROOT" && -f "$PLUGIN_ROOT/hooks/_shared.sh" ]] || exit 0
# shellcheck source=hooks/_shared.sh
. "$PLUGIN_ROOT/hooks/_shared.sh"

kunskap_marker_path >/dev/null || exit 0

# Missing identity → quietly skip. Every Write/Edit firing this would be
# noisy and the SessionStart hook already surfaces the actionable message
# once per session.
who="$(kunskap_identity_set)" || exit 0

vault="$(kunskap_resolve_vault)" || exit 0
kunskap_is_shared "$vault" || exit 0

# Read PostToolUse stdin JSON (canonical shape per Claude Code hooks docs):
#   { "tool_input": { "file_path": "/abs/path", ... }, ... }
file_path=""
if [[ ! -t 0 ]]; then
  hook_input="$(cat 2>/dev/null || true)"
  if [[ -n "$hook_input" ]]; then
    file_path="$(printf '%s' "$hook_input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
  fi
fi
[[ -n "$file_path" ]] || exit 0

# Refuse any traversal segment, even if a downstream prefix-match would
# pass. Belt-and-braces with the absolute-prefix check below.
case "$file_path" in
  *"/../"* | "../"* | *"/.." | "..") exit 0 ;;
esac

# Inbox-prefix check. Only act on writes under <vault>/raw/inbox/.
inbox="$vault/raw/inbox"
case "$file_path" in
  "$inbox"/*) ;;
  *) exit 0 ;;
esac

if kunskap_rebase_in_progress "$vault"; then
  echo "Kunskap: post-write-sync skipped — rebase in progress at $vault" >&2
  exit 0
fi

_do_sync() {
  (
    cd "$vault" || exit 0
    git add raw/inbox 2>/dev/null || exit 0
    git diff --cached --quiet 2>/dev/null && exit 0
    git commit --quiet -m "kunskap: inbox capture (auto, ${who})" \
      || { echo "Kunskap: post-write-sync commit failed" >&2; exit 0; }
    git push --quiet 2>/dev/null \
      || echo "Kunskap: post-write-sync push failed; will retry" >&2
  )
}

if [[ "${KUNSKAP_HOOK_NO_BG:-}" == "1" ]]; then
  _do_sync
else
  _do_sync &
  disown 2>/dev/null || true
fi

exit 0
