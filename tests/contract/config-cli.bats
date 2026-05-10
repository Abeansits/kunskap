#!/usr/bin/env bats
# CLI-surface tests for `kunskap [--vault X] config get <key>` and the global
# --vault flag's pre-dispatch parsing.

load helpers

setup() {
  TMPXDG="$(make_temp_xdg)"
  export TMPXDG
  export XDG_CONFIG_HOME="$TMPXDG"
}

teardown() {
  [[ -n "${TMPXDG:-}" && -d "$TMPXDG" ]] && rm -rf "$TMPXDG"
}

@test "config get without --vault reads from identity.toml" {
  "$KUNSKAP_BIN" config user --name ci --host runner >/dev/null 2>&1
  run "$KUNSKAP_BIN" config get name
  [[ "$status" -eq 0 ]]
  [[ "$output" == "ci" ]]
  run "$KUNSKAP_BIN" config get host
  [[ "$status" -eq 0 ]]
  [[ "$output" == "runner" ]]
}

@test "config get rejects unknown user keys" {
  "$KUNSKAP_BIN" config user --name ci --host runner >/dev/null 2>&1
  run "$KUNSKAP_BIN" config get vault
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"unknown user key"* ]]
  [[ "$output" == *"--vault for vault keys"* ]]
}

@test "config get with --vault reads from _meta/kunskap.toml [vault] section" {
  vault="$(mktemp -d)"
  mkdir -p "$vault/_meta"
  cat > "$vault/_meta/kunskap.toml" <<EOF
[vault]
name = "test-vault"
shared = true
created = "2026-05-04"
schema_version = 1
EOF
  run "$KUNSKAP_BIN" --vault "$vault" config get shared
  [[ "$status" -eq 0 ]]
  [[ "$output" == "true" ]]
  run "$KUNSKAP_BIN" --vault "$vault" config get name
  [[ "$status" -eq 0 ]]
  [[ "$output" == "test-vault" ]]
  rm -rf "$vault"
}

@test "config get shared returns false (fail-soft) when _meta/kunskap.toml missing" {
  # P3 ships kunskap init. Until then, vaults predate the config file. Hooks
  # rely on this returning false-not-die so they can skip pull/push cleanly.
  vault="$(mktemp -d)"
  run "$KUNSKAP_BIN" --vault "$vault" config get shared
  [[ "$status" -eq 0 ]]
  [[ "$output" == "false" ]]
  rm -rf "$vault"
}

@test "config get name (vault context) returns empty when file missing — fail-soft" {
  vault="$(mktemp -d)"
  run "$KUNSKAP_BIN" --vault "$vault" config get name
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
  rm -rf "$vault"
}

@test "config get rejects unknown vault keys" {
  vault="$(mktemp -d)"
  mkdir -p "$vault/_meta"
  echo "[vault]" > "$vault/_meta/kunskap.toml"
  run "$KUNSKAP_BIN" --vault "$vault" config get bogus
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"unknown vault key"* ]]
  rm -rf "$vault"
}

@test "config get accepts schema_version (numeric value)" {
  vault="$(mktemp -d)"
  mkdir -p "$vault/_meta"
  cat > "$vault/_meta/kunskap.toml" <<EOF
[vault]
schema_version = 1
EOF
  run "$KUNSKAP_BIN" --vault "$vault" config get schema_version
  [[ "$status" -eq 0 ]]
  [[ "$output" == "1" ]]
  rm -rf "$vault"
}

@test "global --vault rejects flag-as-value" {
  run "$KUNSKAP_BIN" --vault --help config get shared
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"got next flag"* ]]
}

@test "config get requires exactly one key argument" {
  run "$KUNSKAP_BIN" config get
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"exactly one"* ]]
  run "$KUNSKAP_BIN" config get name extra
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"exactly one"* ]]
}

# ---------- identity-overwrite guard ----------

@test "config user writes silently when no existing identity (first-run path)" {
  run "$KUNSKAP_BIN" config user --name first --host runner
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"identity written"* ]]
  run "$KUNSKAP_BIN" whoami
  [[ "$status" -eq 0 ]]
  [[ "$output" == "first@runner" ]]
}

@test "config user writes silently when existing identity matches the new one" {
  "$KUNSKAP_BIN" config user --name same --host runner >/dev/null
  # Re-running with the same identity must not require --yes; setup
  # re-runs and CI would otherwise need a flag they shouldn't.
  run "$KUNSKAP_BIN" config user --name same --host runner
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"replacing identity"* ]]
}

@test "config user refuses to overwrite an existing different identity without --yes" {
  "$KUNSKAP_BIN" config user --name old --host runner >/dev/null
  run "$KUNSKAP_BIN" config user --name new --host runner
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"identity already set to old@runner"* ]]
  [[ "$output" == *"--yes to confirm"* ]]
  run "$KUNSKAP_BIN" whoami
  [[ "$output" == "old@runner" ]]
}

@test "config user --yes overwrites the existing identity and prints replacement" {
  "$KUNSKAP_BIN" config user --name old --host runner >/dev/null
  run "$KUNSKAP_BIN" config user --name new --host runner --yes
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"replacing identity old@runner → new@runner"* ]]
  run "$KUNSKAP_BIN" whoami
  [[ "$output" == "new@runner" ]]
}

@test "config user honors KUNSKAP_AUTO_CONFIRM=1 (Risk #7 pattern)" {
  "$KUNSKAP_BIN" config user --name old --host runner >/dev/null
  KUNSKAP_AUTO_CONFIRM=1 run "$KUNSKAP_BIN" config user --name new --host runner
  [[ "$status" -eq 0 ]]
  run "$KUNSKAP_BIN" whoami
  [[ "$output" == "new@runner" ]]
}
