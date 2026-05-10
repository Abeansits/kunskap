#!/usr/bin/env bats
# E2E "panel-content" smoke: scaffolds a vault via `kunskap init`, then
# queries `kunskap learn status` against THAT vault, asserting one stable
# phrase from each user-visible panel. init-cli.bats and learn-cli.bats
# both grep these phrases unit-style — but neither exercises the wiring
# end-to-end against an init-PRODUCED vault. If the init template ever
# stops shipping `primary = "TBD"` defaults, the unit suites stay green
# while the user-visible flow breaks; this file catches that.

load helpers

setup() {
  setup_proj_xdg
  TMPVAULT="$(mktemp -d -t kunskap-panel.XXXXXX)"
  rm -rf "$TMPVAULT"   # init expects a non-existent or empty path
  export TMPVAULT
  export KUNSKAP_AUTO_CONFIRM=1
}

teardown() {
  cleanup_temp_dirs TMPPROJ TMPXDG TMPVAULT
}

@test "panel: kunskap init prints the v1.1.1 next-steps panel with single-primary WHY" {
  run "$KUNSKAP_BIN" init "$TMPVAULT" --name "Panel Smoke"
  [[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
  [[ "$output" == *"Kunskap vault created"* ]] || { echo "$output"; return 1; }
  # The v1.1.1 housekeeping locked in this exact framing — wording drift
  # away from "single-primary contract" would change a user's mental
  # model on the role assignment.
  [[ "$output" == *"single-primary contract"* ]] || { echo "$output"; return 1; }
}

@test "panel: kunskap learn status against an init-produced vault surfaces all-TBD ROLE-CHECK" {
  # Asserts the wiring end-to-end against the init template's TBD
  # defaults — NOT against a hand-rolled fixture roles.toml.
  "$KUNSKAP_BIN" init "$TMPVAULT" --name "Status Smoke" >/dev/null
  cd "$TMPPROJ"
  # ROLE-CHECK branch only fires when identity is set; write_identity_toml
  # (helpers.bash) is the no-fork path used by other hot-setup suites.
  write_identity_toml "$TMPXDG" ci runner
  "$KUNSKAP_BIN" learn enable --vault "$TMPVAULT" >/dev/null
  run "$KUNSKAP_BIN" learn status
  [[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
  # The v1.1.1 distinct copy for the all-TBD case (separate from
  # "not primary" — which would be a misleading regression).
  [[ "$output" == *"ROLE-CHECK: no primary configured"* ]] \
    || { echo "$output"; return 1; }
}
