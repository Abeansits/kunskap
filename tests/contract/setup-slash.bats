#!/usr/bin/env bats
# Shape lock for `commands/setup.md` — the slash command surface that hosts
# the guided onboarding conversation. The slash command's job is the
# conversation; the CLI verb's job is the side effects. These tests pin
# that contract: the body must mention `kunskap setup` (so it actually
# delegates), must declare the right tools, and must cover all three
# branches (A: fresh, B: existing identity, C: already-enabled).
#
# Behavioral testing of the conversation flow itself happens empirically
# in the dev dance (Pass-2 captures a real claude session against a test
# vault and confirms <10 turns). These bats tests only lock the static
# shape so /simplify can't quietly hollow it out.

load helpers

SETUP_CMD="$REPO_ROOT/commands/setup.md"

@test "commands/setup.md exists" {
  [[ -f "$SETUP_CMD" ]]
}

# ---------- frontmatter shape ----------

@test "frontmatter declares description" {
  awk '/^---$/{c++} c==1 && /^description:/{found=1} END{exit !found}' "$SETUP_CMD"
}

@test "frontmatter declares argument-hint (optional vault path)" {
  awk '/^---$/{c++} c==1 && /^argument-hint:/{found=1} END{exit !found}' "$SETUP_CMD"
}

@test "frontmatter allowed-tools includes Bash (load-bearing — CLI calls)" {
  awk '/^---$/{c++} c==1 && /^allowed-tools:.*Bash/{found=1} END{exit !found}' "$SETUP_CMD"
}

@test "frontmatter allowed-tools includes Read (marker readback for branch C)" {
  awk '/^---$/{c++} c==1 && /^allowed-tools:.*Read/{found=1} END{exit !found}' "$SETUP_CMD"
}

# ---------- body content: must delegate to the CLI verb ----------

@test "body invokes \`kunskap setup\` (composition contract)" {
  grep -Fq 'kunskap setup' "$SETUP_CMD"
}

@test "body covers all three branches (A: fresh, B: existing identity, C: already-enabled)" {
  grep -Eq '^## Branch A' "$SETUP_CMD"
  grep -Eq '^## Branch B' "$SETUP_CMD"
  grep -Eq '^## Branch C' "$SETUP_CMD"
}

@test "body documents the four pre-flight detections (CLI / identity / marker / vault arg)" {
  # Each detection is keyed by the underlying probe — kunskap CLI on PATH,
  # whoami, the marker file, and the vault arg.
  grep -Fq 'command -v kunskap'             "$SETUP_CMD"
  grep -Fq 'kunskap whoami'                 "$SETUP_CMD"
  grep -Fq '.claude/kunskap.json'           "$SETUP_CMD"
  grep -Fq 'ARGUMENTS'                      "$SETUP_CMD"
}

# ---------- discipline: no direct file mutation ----------

@test "body does not directly write or edit files (CLI owns side effects)" {
  # The slash command's allowed-tools do NOT include Write or Edit by
  # design — the CLI verb is the side-effect surface. Lock that here so a
  # future drive-by edit can't add Write/Edit and start hand-rolling
  # marker / roles.toml changes.
  ! awk '/^---$/{c++} c==1 && /^allowed-tools:.*Write/{print; exit}' "$SETUP_CMD" | grep -q .
  ! awk '/^---$/{c++} c==1 && /^allowed-tools:.*Edit/{print;  exit}' "$SETUP_CMD" | grep -q .
}

# ---------- conversation principles surfaced (anti-rot) ----------

@test "body documents the show-what-will-run principle (Risk #7 + trust)" {
  grep -Fq 'show what will run' "$SETUP_CMD"
}

@test "body documents the verbatim-CLI-output principle" {
  grep -Fq 'verbatim' "$SETUP_CMD"
}

@test "body bounds the conversation budget (≤10 turns)" {
  grep -Eq '10 turns|≤[[:space:]]*10' "$SETUP_CMD"
}

# ---------- registered in the slash-command surface (no orphan) ----------

@test "/kunskap:setup is referenced from the README onboarding section" {
  grep -Fq '/kunskap:setup' "$REPO_ROOT/README.md"
}
