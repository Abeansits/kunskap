---
description: Run the Kunskap curator on a vault. Compiles raw/inbox/ into wiki articles per the §Curator contract.
argument-hint: <vault-path>
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

Invoke the **curator** agent on the vault at: `$ARGUMENTS`

Pre-flight (do these first, fail fast):
- If `$ARGUMENTS` is empty, stop and tell the user: "Usage: /kunskap:curate <absolute-vault-path>".
- Run `kunskap curate --vault "$ARGUMENTS" --check` (validates `_meta/kunskap.toml` + `raw/inbox/`). If it exits non-zero, stop and surface the error.

Then delegate to the `curator` agent (from this plugin) with the vault path as its `$ARGUMENTS`. The curator's system prompt encodes the full §Curator contract — process inbox file-by-file, atomic per-article commits, hand-edit preservation, per-source `## Sources` footers.

After the curator returns:
- Print a one-line summary: `kunskap: processed N inbox files → A articles, D drafts, S stub additions`.
- If the curator routed anything to `wiki/_drafts/`, remind the user `/kunskap:drafts` (P3) will surface them once that ships.

Note: `--dry-run` is reserved for P4 (`kunskap dry-run` per design §CLI primitives table). Not implemented here.
