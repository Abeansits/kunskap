# shellcheck shell=bash
# Helpers shared between session-start.sh and session-end.sh.
#
# Fail-soft contract: every helper returns non-zero on missing prerequisites
# but never aborts the calling shell. Callers exit 0 with a stderr message
# on any failure — closing your laptop must not be blocked by a flaky vault.

# Tests must export CLAUDE_PLUGIN_ROOT themselves; Claude Code injects it.
kunskap_bin() {
  local root="${CLAUDE_PLUGIN_ROOT:-}"
  [[ -n "$root" && -x "$root/bin/kunskap" ]] || return 1
  printf '%s\n' "$root/bin/kunskap"
}

kunskap_marker_path() {
  local proj="${CLAUDE_PROJECT_DIR:-}"
  [[ -n "$proj" ]] || return 1
  local marker="$proj/.claude/kunskap.json"
  [[ -f "$marker" ]] || return 1
  printf '%s\n' "$marker"
}

kunskap_resolve_vault() {
  local marker vault
  marker="$(kunskap_marker_path)" || return 1
  vault="$(jq -r '.vault // empty' "$marker" 2>/dev/null || true)"
  [[ -n "$vault" && -d "$vault" ]] || return 1
  printf '%s\n' "$vault"
}

# Pre-init vaults (no _meta/kunskap.toml yet) read as not-shared by design —
# `kunskap config get shared` returns "false" for missing files. Hooks rely
# on this to skip pull/push cleanly until P3 ships `kunskap init`.
kunskap_is_shared() {
  local vault="${1:-}"
  [[ -n "$vault" ]] || return 1
  local bin val
  bin="$(kunskap_bin)" || return 1
  val="$("$bin" --vault "$vault" config get shared 2>/dev/null || echo false)"
  [[ "$val" == "true" ]]
}

# Echo the identity-string (`<name>@<host>`) on success, return 1 if unset.
# Callers like session-end use the returned value in commit messages, saving
# a second whoami fork.
kunskap_identity_set() {
  local bin
  bin="$(kunskap_bin)" || return 1
  "$bin" whoami 2>/dev/null
}

# A previous `git pull --rebase --autostash` may have half-succeeded (network
# drop, Ctrl-C, OS shutdown), leaving `.git/rebase-merge/` or
# `.git/rebase-apply/`. Subsequent pulls would fail every session — sync stays
# broken indefinitely. Hooks detect the wedge and refuse to act, leaving the
# user a clear message rather than auto-aborting (which would silently
# discard partially-resolved work).
kunskap_rebase_in_progress() {
  local vault="${1:-}"
  [[ -n "$vault" ]] || return 1
  [[ -d "$vault/.git/rebase-merge" || -d "$vault/.git/rebase-apply" ]]
}
