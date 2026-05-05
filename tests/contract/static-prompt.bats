#!/usr/bin/env bats
# Static prompt-content tests. These map each §Curator contract MUST / MUST-NOT
# clause to a literal-string presence check in agents/curator.md.
#
# If a curator-prompt edit removes a clause, the corresponding test fails.
# This is the design §Risks #9 safety net: contract is enforced, not decorative.
#
# Run a "drift simulation" by deleting any matched string from agents/curator.md
# and re-running this file: the corresponding test fails specifically.

load helpers

setup() {
  [[ -f "$CURATOR_AGENT" ]] || skip "agents/curator.md missing"
}

@test "MUST 1 — atomic per-article commit clause is present" {
  prompt_contains "process inbox file-by-file, commit atomically per article"
}

@test "MUST 1 — explicit prohibition on batch-then-commit" {
  prompt_contains "NEVER"
  prompt_contains "Batch writes across multiple inbox files"
}

@test "MUST 1 — commit message shape spelled out" {
  prompt_contains "kunskap: {extend|new|draft}"
}

@test "MUST 2 — hand-edit preservation rule named explicitly" {
  prompt_contains "preserve hand edits"
  prompt_contains "Risk #3"
}

@test "MUST 2 — hand-edit detection routes to _drafts/{slug}-update.md" {
  prompt_contains "_drafts/{slug}-update.md"
}

@test "MUST 2 — explicit prohibition on silent overwrite" {
  prompt_contains "NEVER silently overwrite a hand edit"
}

@test "MUST 3 — three-bucket routing named (extend / new / draft)" {
  prompt_contains "three buckets"
  prompt_contains "(a) Extend"
  prompt_contains "(b) New article"
  prompt_contains "(c) Draft"
}

@test "MUST 3 — unclassifiable note → draft with confidence: low + reason" {
  prompt_contains "confidence: low"
  prompt_contains "reason: <classifier-output>"
}

@test "MUST 3 — never archive without a wiki target" {
  prompt_contains "Never archive without producing a wiki target"
}

@test "MUST 4 — Sources footer is per-source, not merged" {
  prompt_contains "Sources\` footer is per-source, not merged"
}

@test "MUST 4 — multi-finding files quote only relevant sub-finding per article" {
  prompt_contains "(third sub-finding)"
  prompt_contains "quote ONLY the relevant sub-finding"
}

@test "MUST 5 — vault scope = \$ARGUMENTS, no writes outside vault" {
  prompt_contains "\$ARGUMENTS\` is the vault scope"
  prompt_contains "Operate only inside that vault"
}

@test "Operating norm 1 — librarian owns all of wiki/" {
  prompt_contains "You own all of \`wiki/\`"
}

@test "Operating norm 2 — Lane 1/2 is a trust gate, not directory placement" {
  prompt_contains "Lane 1 / Lane 2 is a trust gate, not directory placement"
}

@test "Operating norm 3 — Lane 2 with in-doc invitation may promote" {
  prompt_contains "Lane 2 with explicit in-doc invitation"
  prompt_contains "Revisit on N+1"
}

@test "Operating norm 4 — Lane 2 without invitation → draft, with confidence/reason/source_count" {
  prompt_contains "Frontmatter MUST include \`confidence\`, \`reason\`, and \`source_count\`"
}

@test "Operating norm 5 — ambiguous norm → ask before acting" {
  prompt_contains "Ambiguous norm"
  prompt_contains "ask before acting"
}

@test "Date discipline — inbox-cycle date in frontmatter regardless of midnight drift" {
  prompt_contains "inbox-cycle date in all frontmatter"
}

@test "Wikilinks — kebab-case files + natural-language aliases" {
  prompt_contains "kebab-case files + natural-language aliases"
}

@test "Wikilinks — single-ref name-mismatch → add alias to existing file" {
  prompt_contains "name-mismatch with existing file"
  prompt_contains "add \`aliases:"
}

@test "Wikilinks — single-ref no-file → orange aspirational link" {
  prompt_contains "orange aspirational link"
}

@test "Wikilinks — 2+ refs no-file → write concept stub (≤30 lines)" {
  prompt_contains "2+ refs, no file exists"
  prompt_contains "≤30 lines"
}

@test "Stub discovery grep recipe lifted verbatim from §6" {
  prompt_contains "grep -roh '\\[\\[[^]]*\\]\\]'"
  prompt_contains "sort | uniq -c | sort -rn"
}

@test "Frontmatter contract — last_curated + source_count + sources" {
  prompt_contains "last_curated:"
  prompt_contains "source_count:"
  prompt_contains "sources:"
}

@test "MUST NOT — rewrite an extended article from scratch" {
  prompt_contains "Rewrite an extended article from scratch"
}

@test "MUST NOT — touch any path outside \$ARGUMENTS" {
  prompt_contains "Touch any path outside \`\$ARGUMENTS\`"
}

@test "Disallowed tools — WebFetch and WebSearch listed in frontmatter" {
  grep -E "^disallowedTools:.*WebFetch.*WebSearch" "$CURATOR_AGENT"
}

@test "Multi-finding inbox file handling explained" {
  prompt_contains "Multi-finding inbox files"
  prompt_contains "cite the file in every relevant article"
}

@test "Frontmatter declares model: opus and tools list (no permissionMode)" {
  grep -E "^model: opus" "$CURATOR_AGENT"
  grep -E "^tools: " "$CURATOR_AGENT"
  ! grep -E "^permissionMode:" "$CURATOR_AGENT"
  ! grep -E "^hooks:" "$CURATOR_AGENT"
  ! grep -E "^mcpServers:" "$CURATOR_AGENT"
}
