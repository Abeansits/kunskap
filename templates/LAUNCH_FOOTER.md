## Collective Knowledge

This project uses [Kunskap](https://github.com/Abeansits/kunskap) — a knowledge-base plugin that turns sessions into a searchable wiki. Loose findings (gotchas, design decisions, "this is how X really works") get written as inbox notes; a curator agent compiles them into prose articles with `[[wikilinks]]` and `## Sources` provenance.

The vault path is set in `.claude/kunskap.json` for this project. Use `/kunskap:learn status` to see where it points.

### Pre-flight (required)

At task start (before writing code or making a plan), your first action is to run `/kunskap:recall <keywords>` against the goal — pick 2–3 keywords from the user's request — and briefly note the top 1–3 relevant hits before proceeding. If nothing relevant comes back, say "recall: no prior art" and proceed. If a hit contradicts your plan, surface the conflict before continuing. Skip only when the task is trivial (greetings, time queries, single-line tweaks).

Fallback if the slash command is unavailable: `grep -ri <keyword> <vault>/wiki/`.

### Tool selection

| Operation | Tool | Why |
|-----------|------|-----|
| Search the vault for prior art | `/kunskap:recall` (or `kunskap recall`) | Default — load-bearing rg pass + Obsidian rerank |
| Read a known note by path | Read | Direct |
| Bulk read or grep the vault | Read + Grep | Zero per-call overhead |
| Curator / linter / drafts ops | `/kunskap:curate`, `/kunskap:lint`, `/kunskap:drafts` | Plugin owns role + sandbox |

### Post-task (required unless truly nothing new)

Before declaring the task done, write a learning or idea file to the inbox.

**Write a new file** to `<vault>/raw/inbox/` named `{type}-{short-slug}-{date}.md` where type is `learning`, `idea`, or `improvement`. The PostToolUse hook will commit + push it asynchronously.

### Source field — priority order

Pick the best reference; thread > PR > branch.

1. **Thread path** (full conversation context):
   `thread: ~/.claude/projects/<path>/<session-id>`
2. **PR link**:
   `pr: https://github.com/<org>/<repo>/pull/<n>`
3. **Remote branch**:
   `branch: origin/<branch-name>`

Always include your session name too.

### Entry format — learnings

```
### [YYYY-MM-DD] Short title
- **Area**: project / module
- **Source**: session-name | thread/pr/branch reference
- **Detail**: 1–3 specific, actionable sentences
```

### Entry format — improvements

```
### [YYYY-MM-DD] Short title
- **Area**: project / module
- **Source**: session-name | thread/pr/branch reference
- **Impact**: high | medium | low
- **Problem**: 1 sentence
- **Suggestion**: 1–3 sentences
```

### Rules

- One entry per file. Keep it concise.
- Be specific and actionable, not generic.
- Log reusable knowledge, not task-specific context.
- **Never include secrets, API keys, tokens, or PII** in entries.
- Skip the capture entirely if you have nothing new to contribute — no filler entries.
