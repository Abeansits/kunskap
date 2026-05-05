---
description: Audit a Kunskap vault for drift, stale drafts, missing connections, offline arrivals, curator absence, identity mismatches. Read-only.
argument-hint: [--vault <path>] [--format json]
allowed-tools: Bash
---

Run `kunskap lint $ARGUMENTS` from the project working directory and surface its output verbatim.

Pre-flight (do these first, fail fast):
- If `$ARGUMENTS` is empty, the CLI resolves the vault from the project marker (`.claude/kunskap.json`) the same way `/kunskap:drafts` does. If neither flag nor marker resolves, the CLI errors clearly.
- The CLI owns vault validation, agent spawn, exit-code semantics (0 = healthy, 1 = findings present, JSON mode always 0), and the read-only invariant check.

Notes:
- `lint` is **read-only**. The linter agent is forbidden from writing to the vault; the CLI verifies `git status --porcelain` is clean post-run and fails if not (MUST 8 in `agents/linter.md`).
- Findings shape: `[TYPE] path | message`. Severity-grouped in text mode; structured `findings: [...]` array in `--format json`.
- This is a separate manual invocation from `/kunskap:curate`. Do not chain them; the curator writes, the linter audits.
