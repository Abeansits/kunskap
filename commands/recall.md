---
description: Search the Kunskap vault for matching content. rg-first; Obsidian CLI as best-effort second pass.
argument-hint: <query> [--author X] [--tag Y] [--vault <path>] [--limit N] [--format text|json]
allowed-tools: Bash
---

Run `kunskap recall $ARGUMENTS` from the project working directory and surface its output verbatim.

Pre-flight (do these first, fail fast):
- If `$ARGUMENTS` is empty, stop and tell the user: `Usage: /kunskap:recall <query> [--author X] [--tag Y] [--limit N] [--format text|json]`.
- The CLI owns vault resolution (`--vault` flag wins, else the project marker `.claude/kunskap.json`), arg validation, and the read-only invariant. No spawn — `recall` is pure shell.

Notes:
- Stage 1 is `rg --type md` over `wiki/` + `raw/inbox/`; load-bearing per design §Q8. Stage 2 is the Obsidian CLI (`obsidian search`) when the desktop app is running AND the CLI is enabled in Settings — it reranks rg's hits by Obsidian's relevance score. If Stage 2 isn't available (no app, CLI not enabled), Stage 1 carries silently.
- Identity-independent — works on any machine regardless of role (P5 §8: `--check`-style read-only operations are orthogonal to role gates).
- Output: text mode prints bulleted snippets sorted by score (file hit-count, with Obsidian rerank when available); `--format json` emits `{hits: [{path, line, snippet, score, author?, tags?, obs_rank?}]}` for agent consumption.
- Exit codes: 0 = at least one hit, 1 = no hits. Same convention in both formats.
