---
type: learning            # learning | idea | improvement
session: <session-name>
created: <iso-date>       # ISO 8601 (YYYY-MM-DD)
suggested_topic: <kebab-slug>   # optional, pre-seeds curator clustering
sources:
  - <thread | pr | branch — see Source priority below>
---

# Short title

<body — see Entry format below>

---
<!-- Below this line is template guidance. Delete it from the actual inbox note. -->

## Source field — priority order

Pick the best reference; thread > PR > branch.

1. **Thread path** (full conversation context):
   `thread: ~/.claude/projects/<path>/<session-id>`
2. **PR link**:
   `pr: https://github.com/<org>/<repo>/pull/<n>`
3. **Remote branch**:
   `branch: origin/<branch-name>`

The `session:` frontmatter pairs with the source for auditability.

## Entry format — learnings

```
### [YYYY-MM-DD] Short title
- **Area**: project / module
- **Source**: session-name | thread/pr/branch reference
- **Detail**: 1–3 specific, actionable sentences
```

## Entry format — improvements

```
### [YYYY-MM-DD] Short title
- **Area**: project / module
- **Source**: session-name | thread/pr/branch reference
- **Impact**: high | medium | low
- **Problem**: 1 sentence
- **Suggestion**: 1–3 sentences
```

## Rules

- One entry per file. Keep it concise.
- Be specific and actionable, not generic.
- Log reusable knowledge, not task-specific context.
- **Never include secrets, API keys, tokens, or PII**.
- Skip the capture entirely if you have nothing new — no filler entries.
