#!/usr/bin/env bats
# CLI-surface tests for `bin/kunskap init`. No LLM, no auth. Each test runs
# in a temp target dir + temp XDG so the user's real config is untouched.

load helpers

setup() {
  TMPTARGET="$(mktemp -d -t kunskap-init.XXXXXX)"
  rm -rf "$TMPTARGET"   # we want the path to NOT exist for the happy-path tests
  TMPXDG="$(make_temp_xdg)"
  export TMPTARGET TMPXDG
  export XDG_CONFIG_HOME="$TMPXDG"
  # KUNSKAP_AUTO_CONFIRM=1 silences the --force prompt so non-interactive tests
  # don't hang. Tests that exercise the prompt clear this.
  export KUNSKAP_AUTO_CONFIRM=1
}

teardown() {
  cleanup_temp_dirs TMPTARGET TMPXDG
}

# ---------- arg parsing ----------

@test "init requires <path>" {
  run "$KUNSKAP_BIN" init
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"<path> is required"* ]]
}

@test "init rejects unknown flag" {
  run "$KUNSKAP_BIN" init "$TMPTARGET" --bogus
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"unknown flag"* ]]
}

@test "init rejects flag-as-value (P0 lesson)" {
  run "$KUNSKAP_BIN" init "$TMPTARGET" --name --shared
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"got next flag"* ]]
}

@test "init rejects file as target" {
  vfile="$(mktemp)"
  run "$KUNSKAP_BIN" init "$vfile"
  rm -f "$vfile"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"not a directory"* ]]
}

@test "init rejects non-empty target without --force" {
  mkdir -p "$TMPTARGET"
  echo "junk" > "$TMPTARGET/existing.txt"
  run "$KUNSKAP_BIN" init "$TMPTARGET"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"non-empty"* ]]
  [[ "$output" == *"--force"* ]]
}

@test "init --force on non-empty target requires confirmation by default" {
  mkdir -p "$TMPTARGET"
  echo "junk" > "$TMPTARGET/existing.txt"
  unset KUNSKAP_AUTO_CONFIRM
  run bash -c "echo '' | '$KUNSKAP_BIN' init '$TMPTARGET' --force"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"cancelled"* ]]
  # Marker file proves no scaffold happened.
  [[ ! -f "$TMPTARGET/_meta/kunskap.toml" ]]
}

@test "init --force --yes on non-empty target proceeds" {
  mkdir -p "$TMPTARGET"
  echo "junk" > "$TMPTARGET/existing.txt"
  run "$KUNSKAP_BIN" init "$TMPTARGET" --force --yes
  [[ "$status" -eq 0 ]]
  [[ -f "$TMPTARGET/_meta/kunskap.toml" ]]
  # Pre-existing file is preserved (we scaffold over, not nuke).
  [[ -f "$TMPTARGET/existing.txt" ]]
}

@test "init --force with KUNSKAP_AUTO_CONFIRM=1 proceeds (test scriptability)" {
  mkdir -p "$TMPTARGET"
  echo "junk" > "$TMPTARGET/existing.txt"
  run "$KUNSKAP_BIN" init "$TMPTARGET" --force
  [[ "$status" -eq 0 ]]
  [[ -f "$TMPTARGET/_meta/kunskap.toml" ]]
}

# ---------- happy path: full scaffold ----------

@test "init happy path: empty target gets full vault layout" {
  run "$KUNSKAP_BIN" init "$TMPTARGET" --name "Smoke"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Kunskap vault created"* ]]

  # _meta/
  [[ -f "$TMPTARGET/_meta/kunskap.toml" ]]
  [[ -f "$TMPTARGET/_meta/roles.toml" ]]
  # raw/
  [[ -d "$TMPTARGET/raw/inbox" ]]
  # wiki/ — every subdir
  for sub in _drafts learnings ideas concepts patterns bases; do
    [[ -d "$TMPTARGET/wiki/$sub" ]] || { echo "missing wiki/$sub"; return 1; }
  done
  [[ -f "$TMPTARGET/wiki/_index.md" ]]
  # Archives/
  [[ -d "$TMPTARGET/Archives/processed-inbox" ]]
  [[ -d "$TMPTARGET/Archives/processed-drafts/approved" ]]
  [[ -d "$TMPTARGET/Archives/processed-drafts/rejected" ]]
  # README + .gitignore
  [[ -f "$TMPTARGET/README.md" ]]
  [[ -f "$TMPTARGET/.gitignore" ]]
  # git repo
  [[ -d "$TMPTARGET/.git" ]]
}

@test "init substitutes {{name}} into _meta/kunskap.toml + _index.md + README.md" {
  "$KUNSKAP_BIN" init "$TMPTARGET" --name "My Custom Vault"
  grep -q 'name = "My Custom Vault"' "$TMPTARGET/_meta/kunskap.toml"
  grep -q "My Custom Vault" "$TMPTARGET/wiki/_index.md"
  grep -q "My Custom Vault" "$TMPTARGET/README.md"
  ! grep -q '{{name}}' "$TMPTARGET/_meta/kunskap.toml"
  ! grep -q '{{name}}' "$TMPTARGET/wiki/_index.md"
  ! grep -q '{{name}}' "$TMPTARGET/README.md"
}

@test "init substitutes {{created}} as ISO date" {
  "$KUNSKAP_BIN" init "$TMPTARGET" --name "Date Test"
  ! grep -q '{{created}}' "$TMPTARGET/_meta/kunskap.toml"
  grep -Eq 'created = "[0-9]{4}-[0-9]{2}-[0-9]{2}"' "$TMPTARGET/_meta/kunskap.toml"
}

@test "init defaults --name to basename when not provided" {
  "$KUNSKAP_BIN" init "$TMPTARGET"
  base="$(basename "$TMPTARGET")"
  grep -Fq "name = \"$base\"" "$TMPTARGET/_meta/kunskap.toml"
}

@test "init --shared sets shared=true and adds origin remote" {
  "$KUNSKAP_BIN" init "$TMPTARGET" --shared "git@example.com:org/x.git"
  grep -q 'shared = true' "$TMPTARGET/_meta/kunskap.toml"
  remote=$(git -C "$TMPTARGET" remote get-url origin)
  [[ "$remote" == "git@example.com:org/x.git" ]]
}

@test "init without --shared sets shared=false (no origin remote)" {
  "$KUNSKAP_BIN" init "$TMPTARGET"
  grep -q 'shared = false' "$TMPTARGET/_meta/kunskap.toml"
  ! git -C "$TMPTARGET" remote get-url origin >/dev/null 2>&1
}

@test "init seeds neutral sample inbox + wiki + archive notes" {
  "$KUNSKAP_BIN" init "$TMPTARGET"
  # Use the literal "example" prefix — neutral, no domain leak (Risk #7).
  inbox_count=$(find "$TMPTARGET/raw/inbox" -name 'example-*.md' | wc -l | tr -d ' ')
  [[ "$inbox_count" -ge 1 ]]
  wiki_count=$(find "$TMPTARGET/wiki/learnings" -name 'example-topic.md' | wc -l | tr -d ' ')
  [[ "$wiki_count" -eq 1 ]]
  archive_count=$(find "$TMPTARGET/Archives/processed-inbox" -name 'example-baseline-*.md' | wc -l | tr -d ' ')
  [[ "$archive_count" -eq 1 ]]
  # Sample article body must NOT mention specific research domains (e.g.
  # hyperspectral). Reject the leak class explicitly.
  ! grep -qi 'hyperspectral\|kunskap-research' "$TMPTARGET/wiki/learnings/example-topic.md"
}

@test "init produces a curator-runnable vault (curate --check passes)" {
  # Hard contract: a freshly-init'd vault must satisfy `kunskap curate --check`
  # with no manual fixup. If this fails, P3 missed its core deliverable.
  "$KUNSKAP_BIN" init "$TMPTARGET" --name "Curator Compatible"
  run "$KUNSKAP_BIN" curate --vault "$TMPTARGET" --check
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"healthy"* ]]
}

@test "init produces a vault that audit-coverage understands (covered_count >= 1)" {
  # Sample article cites the seeded archive entry; covered_count must reflect.
  "$KUNSKAP_BIN" init "$TMPTARGET"
  run "$KUNSKAP_BIN" audit-coverage --vault "$TMPTARGET" --format json
  # Exits 2 because raw/inbox/example-*.md is a "silent drop" until the user
  # runs the curator — that's correct behaviour, not an init bug.
  [[ "$status" -eq 2 ]]
  cov=$(echo "$output" | jq '.covered_count')
  [[ "$cov" -ge 1 ]]
}

@test "init config get shared returns true for --shared vault" {
  "$KUNSKAP_BIN" init "$TMPTARGET" --shared "git@example.com:org/y.git"
  run "$KUNSKAP_BIN" --vault "$TMPTARGET" config get shared
  [[ "$status" -eq 0 ]]
  [[ "$output" == "true" ]]
}

@test "init config get shared returns false for solo vault" {
  "$KUNSKAP_BIN" init "$TMPTARGET"
  run "$KUNSKAP_BIN" --vault "$TMPTARGET" config get shared
  [[ "$status" -eq 0 ]]
  [[ "$output" == "false" ]]
}

@test "init is idempotent under --force --yes (no duplicate origin remote, no errors)" {
  "$KUNSKAP_BIN" init "$TMPTARGET" --shared "git@example.com:org/z.git"
  run "$KUNSKAP_BIN" init "$TMPTARGET" --shared "git@example.com:org/z.git" --force --yes
  [[ "$status" -eq 0 ]]
  # Exactly one origin remote, with the correct URL.
  remotes=$(git -C "$TMPTARGET" remote | wc -l | tr -d ' ')
  [[ "$remotes" -eq 1 ]]
  remote=$(git -C "$TMPTARGET" remote get-url origin)
  [[ "$remote" == "git@example.com:org/z.git" ]]
}

@test "init --shared on second run updates remote URL when it differs" {
  "$KUNSKAP_BIN" init "$TMPTARGET" --shared "git@example.com:org/old.git"
  "$KUNSKAP_BIN" init "$TMPTARGET" --shared "git@example.com:org/new.git" --force --yes
  remote=$(git -C "$TMPTARGET" remote get-url origin)
  [[ "$remote" == "git@example.com:org/new.git" ]]
}

@test "init does NOT auto-commit the scaffold (let user review with git status)" {
  "$KUNSKAP_BIN" init "$TMPTARGET" --name "Review First"
  run git -C "$TMPTARGET" log --oneline
  # `git log` exits non-zero on an empty repo — that's exactly the contract
  # we're asserting.
  [[ "$status" -ne 0 ]]
}

@test "init prints next-steps panel pointing at /kunskap:learn enable" {
  run "$KUNSKAP_BIN" init "$TMPTARGET" --name "Panel"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Next steps"* ]]
  [[ "$output" == *"/kunskap:learn enable"* ]]
  [[ "$output" == *"_meta/roles.toml"* ]]
}

@test "init next-steps panel explains role config WHY + HOW (v1.1.1)" {
  run "$KUNSKAP_BIN" init "$TMPTARGET" --name "Panel WhyHow"
  [[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
  # WHY: invariant phrase the v1.1.1 brief locks in.
  [[ "$output" == *"single-primary contract"* ]] \
    || { echo "$output"; return 1; }
  # HOW: the slug-discovery hint must mention `kunskap whoami`.
  [[ "$output" == *"kunskap whoami"* ]] \
    || { echo "$output"; return 1; }
  # HOW: commit-and-push trio that lets teammates pick up the assignment.
  [[ "$output" == *"git add"* ]] \
    || { echo "$output"; return 1; }
  [[ "$output" == *"commit"* ]] \
    || { echo "$output"; return 1; }
  [[ "$output" == *"push"* ]] \
    || { echo "$output"; return 1; }
}

@test "init rejects --name containing a quote (substitution safety)" {
  run "$KUNSKAP_BIN" init "$TMPTARGET" --name 'has"quote'
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"double-quote"* ]]
}

@test "init --force --yes refuses to overwrite a non-Kunskap target's tracked files" {
  # Pass-2 block-ship: --force --yes used to blindly cp -R the template and
  # silently overwrote tracked README.md / .gitignore in non-Kunskap repos.
  mkdir -p "$TMPTARGET"
  echo "user's existing project README" > "$TMPTARGET/README.md"
  echo "user's existing .gitignore" > "$TMPTARGET/.gitignore"
  run "$KUNSKAP_BIN" init "$TMPTARGET" --force --yes
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"not a Kunskap vault"* ]]
  [[ "$output" == *"README.md"* ]]
  # User content untouched.
  grep -q "user's existing project README" "$TMPTARGET/README.md"
}

@test "init --force --yes IS still idempotent on an already-Kunskap vault (re-init)" {
  # The Pass-2 guard distinguishes case-3 (non-Kunskap repo) from case-2
  # (re-init on existing vault). Re-init must keep working.
  "$KUNSKAP_BIN" init "$TMPTARGET" --name "Already a Vault"
  run "$KUNSKAP_BIN" init "$TMPTARGET" --name "Already a Vault" --force --yes
  [[ "$status" -eq 0 ]]
}

@test "init accepts a relative path and canonicalizes to absolute" {
  cd "$(dirname "$TMPTARGET")"
  rel="$(basename "$TMPTARGET")"
  run "$KUNSKAP_BIN" init "$rel" --name "Relative"
  [[ "$status" -eq 0 ]]
  # Output should contain the absolute form of the target.
  [[ "$output" == *"$TMPTARGET"* ]]
  [[ -f "$TMPTARGET/_meta/kunskap.toml" ]]
}
