---
description: Manually flush uncommitted Kunskap inbox notes — commit + push any pending captures.
argument-hint: [--vault <abs-path>]
allowed-tools: Bash
---

Run `kunskap sync $ARGUMENTS` from the project working directory and surface its output verbatim.

Pre-flight (do these first, fail fast):
- The CLI owns vault resolution (`--vault` flag wins, else the project marker `.claude/kunskap.json`), identity, shared-vault gate, rebase guard, and the commit + push step. No spawn — `sync` is pure shell.

Notes:
- `sync` is the **manual lever**. The `PostToolUse(Write|Edit)` hook covers most inbox writes asynchronously (per-write commit + push). Use `/kunskap:sync` to retry (when an earlier push failed) or to deliberately flush before disconnecting.
- Solo vaults (`shared = false` in `_meta/kunskap.toml`) print a "not shared" message and exit 0; they never push.
- Identity must be set (`kunskap config user --name <slug> --host <host>`) — otherwise refuses with an actionable message.
- Rebase-in-progress at `<vault>/.git/rebase-merge` or `rebase-apply` refuses with an actionable hint (`git -C <vault> rebase --continue` or `--abort`).
- Exit codes: 0 = synced or nothing to sync (clean inbox), 1 = push failed (commit landed locally; will retry on next sync) or other refusal. The async hook only surfaces stderr (commit/push failures, rebase-in-progress, solo no-op); this verb returns a non-zero exit code so callers can branch on it.
