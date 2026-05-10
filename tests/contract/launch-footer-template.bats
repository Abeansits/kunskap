#!/usr/bin/env bats
# Static checks against templates/LAUNCH_FOOTER.md, the canonical capture +
# recall convention sheet shipped inside the plugin (v1.1). The CLAUDE.md
# injection in `kunskap learn enable` reads this file verbatim, so drift
# here is contractually visible to every kunskap-enabled project.

load helpers

TEMPLATE="$REPO_ROOT/templates/LAUNCH_FOOTER.md"

@test "templates/LAUNCH_FOOTER.md exists" {
  [[ -f "$TEMPLATE" ]]
}

@test "LAUNCH_FOOTER declares the Collective Knowledge heading" {
  grep -Fq '## Collective Knowledge' "$TEMPLATE"
}

@test "LAUNCH_FOOTER has the four required convention sections" {
  grep -Fq '### Pre-flight (required)' "$TEMPLATE"
  grep -Fq '### Post-task (required unless truly nothing new)' "$TEMPLATE"
  grep -Fq '### Source field' "$TEMPLATE"
  grep -Fq '### Rules' "$TEMPLATE"
}

@test "LAUNCH_FOOTER documents the inbox-note filename pattern" {
  grep -Fq '{type}-{short-slug}-{date}.md' "$TEMPLATE"
}

@test "LAUNCH_FOOTER mentions /kunskap:recall as the prior-art surface" {
  grep -Fq '/kunskap:recall' "$TEMPLATE"
}

@test "LAUNCH_FOOTER warns against secrets/PII" {
  grep -Fiq 'secrets, API keys, tokens, or PII' "$TEMPLATE"
}

@test "LAUNCH_FOOTER carries no leftover personal/vault paths" {
  # Belt-and-braces: the conductor's LAUNCH_FOOTER pointed at ~/.vigil-vault/
  # by convention; the plugin version must be vault-agnostic.
  ! grep -Fq '~/.vigil-vault' "$TEMPLATE"
  ! grep -Fq 'obsidian-vigil' "$TEMPLATE"
}

@test "LAUNCH_FOOTER ends with a trailing newline (CLAUDE.md injection invariant)" {
  # Body hashing relies on byte-exact concatenation; a missing trailing
  # newline would put the END marker on the same line as the last body line.
  [[ -z "$(tail -c1 "$TEMPLATE")" ]]
}

@test "LAUNCH_FOOTER source-field guidance distinguishes shared vs solo vaults" {
  # thread: paths only resolve on the writer's machine, so shared vaults
  # must lead with team-resolvable refs. Locks the regime split against
  # a future doc sweep that collapses back to a single priority list.
  grep -Fiq 'shared vaults' "$TEMPLATE"
  grep -Fiq 'solo vaults' "$TEMPLATE"
  grep -Fq 'pr: https://github.com/' "$TEMPLATE"
}
