# shellcheck shell=bash
# Helpers shared between session-start.sh and session-end.sh.
#
# Fail-soft contract: every helper returns non-zero on missing prerequisites
# but never aborts the calling shell. Callers exit 0 with a stderr message
# on any failure — closing your laptop must not be blocked by a flaky vault.

# Resolve the kunskap binary inside this plugin. CLAUDE_PLUGIN_ROOT is set by
# Claude Code before each hook fires; tests must export it themselves.
kunskap_bin() {
  local root="${CLAUDE_PLUGIN_ROOT:-}"
  [[ -n "$root" && -x "$root/bin/kunskap" ]] || return 1
  printf '%s\n' "$root/bin/kunskap"
}

# Echo the project's opt-in marker path, or return non-zero if not opted in.
kunskap_marker_path() {
  local proj="${CLAUDE_PROJECT_DIR:-}"
  [[ -n "$proj" ]] || return 1
  local marker="$proj/.claude/kunskap.json"
  [[ -f "$marker" ]] || return 1
  printf '%s\n' "$marker"
}

# Echo the vault path declared by the marker. Returns 1 when the marker is
# missing, malformed, or points at a non-existent directory.
kunskap_resolve_vault() {
  local marker vault
  marker="$(kunskap_marker_path)" || return 1
  vault="$(jq -r '.vault // empty' "$marker" 2>/dev/null || true)"
  [[ -n "$vault" && -d "$vault" ]] || return 1
  printf '%s\n' "$vault"
}

# True iff the vault config declares shared = true. Pre-init vaults (no
# _meta/kunskap.toml yet) read as not-shared, by design — `kunskap config get`
# returns "false" for missing files.
kunskap_is_shared() {
  local vault="${1:-}"
  [[ -n "$vault" ]] || return 1
  local bin val
  bin="$(kunskap_bin)" || return 1
  val="$("$bin" --vault "$vault" config get shared 2>/dev/null || echo false)"
  [[ "$val" == "true" ]]
}

# True iff identity is set (`kunskap whoami --quiet` exits 0).
kunskap_identity_set() {
  local bin
  bin="$(kunskap_bin)" || return 1
  "$bin" whoami --quiet 2>/dev/null
}
