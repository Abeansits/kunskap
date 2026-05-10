#!/usr/bin/env bash
# Kunskap PostToolUse hook — async per-write inbox sync.
#
# Fires on every Write|Edit. Hot path: cheapest checks first so that the
# 99% of writes that are NOT under raw/inbox/ exit before we fork any
# helper subprocesses.
#
# HARD CONTRACTS:
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
[[ -n "$PLUGIN_ROOT" ]] || exit 0
# shellcheck source=hooks/_shared.sh
. "$PLUGIN_ROOT/hooks/_shared.sh" 2>/dev/null || exit 0

# Cheapest gate first: marker file must exist.
marker="$(kunskap_marker_path)" || exit 0

# Read PostToolUse stdin JSON before any helper subprocesses fire. Canonical
# shape: { "tool_input": { "file_path": "/abs/path", ... }, ... }.
file_path=""
if [[ ! -t 0 ]]; then
  hook_input="$(cat 2>/dev/null || true)"
  if [[ -n "$hook_input" ]]; then
    file_path="$(printf '%s' "$hook_input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
  fi
fi
[[ -n "$file_path" ]] || exit 0

# Reject any traversal segment, even when string-prefix would match.
case "$file_path" in
  *"/../"* | "../"* | *"/.." | "..") exit 0 ;;
esac

# Cheap inbox-prefix filter against the marker's vault path. Skips the
# expensive identity / shared / rebase checks for the 99% non-inbox case.
# Both sides are canonicalized so multi-slash / `.` segments / symlinks
# don't defeat the prefix match. (Defense in depth — `learn enable` also
# canonicalizes at write-side.)
vault_from_marker="$(jq -r '.vault // empty' "$marker" 2>/dev/null || true)"
[[ -n "$vault_from_marker" && -d "$vault_from_marker" ]] || exit 0
vault_canonical="$(cd "$vault_from_marker" 2>/dev/null && pwd -P)"
[[ -n "$vault_canonical" ]] || exit 0
inbox="$vault_canonical/raw/inbox"
[[ -d "$inbox" ]] || exit 0

# Resolve file_path to its physical absolute. PostToolUse fires after the
# Write/Edit lands, so the file (or at minimum its parent dir) exists.
file_dir_canonical="$(cd "$(dirname "$file_path")" 2>/dev/null && pwd -P)"
[[ -n "$file_dir_canonical" ]] || exit 0
file_canonical="$file_dir_canonical/$(basename "$file_path")"

case "$file_canonical" in
  "$inbox"/*) ;;
  *) exit 0 ;;
esac

# Past the cheap filter — now we can afford the helper subprocesses.
who="$(kunskap_identity_set)" || exit 0
vault="$(kunskap_resolve_vault)" || exit 0

# v1.2.3: emit an explicit stderr line on the solo no-op so users can
# tell "hook fired and decided to no-op (per design)" apart from "hook
# never fired" — Sebastian's 2026-05-10 fresh-install finding. Inbox
# writes are rare enough (≤ 1 per learning) that one line per capture
# is signal, not noise. By design solo vaults never auto-commit or push
# (Risk #8); the user controls their own git workflow until shared=true.
if ! kunskap_is_shared "$vault"; then
  echo "Kunskap: post-write-sync — vault is solo (shared = false in $vault/_meta/kunskap.toml); inbox capture left uncommitted. Flip shared = true and commit _meta/kunskap.toml when you're ready to enable auto-sync." >&2
  exit 0
fi

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
  # Detach FDs: Claude Code may close stdout/stderr after the hook returns;
  # a long-running git push writing to closed FDs would SIGPIPE silently.
  _do_sync </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

exit 0
