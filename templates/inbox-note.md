---
type: learning            # learning | idea | improvement
session: <session-name>
created: <iso-date>       # ISO 8601 (YYYY-MM-DD)
suggested_topic: <kebab-slug>   # optional, pre-seeds curator clustering
sources:
  - <thread | pr | branch — see "Source field" below>
---

# Short title

<body — see "Entry format" below>

---
<!-- Below this line is template guidance. Delete it from the actual inbox note. -->

## Filename pattern

Save as `<vault>/raw/inbox/{type}-{short-slug}-{YYYY-MM-DD}.md`. Type is one of `learning`, `idea`, or `improvement`. The slug is kebab-case, ≤ 5 words; the date is the day you captured the note.

## Source field — priority order

Pick a reference your readers can resolve. Which regime applies depends on the vault's `shared` flag in `_meta/kunskap.toml`.

**Shared vaults (multiplayer)** — teammates read on different machines, so the reference must resolve anywhere:

1. **PR link**: `pr: https://github.com/<org>/<repo>/pull/<n>`
2. **Remote branch**: `branch: origin/<branch-name>`
3. **Issue / doc URL**: any public link teammates can open
4. _(optional bonus)_ `thread: ~/.claude/projects/<path>/<session-id>` — resolves only on the writer's box; useful for self-reference, not for teammates. Add **after** a team-resolvable ref, never instead.

**Solo vaults** — your machine, your refs. `thread:` is fine to lead with; PR / branch only matter once the work leaves your laptop.

Always include your `session:` slug in frontmatter — it pairs with the source for auditability.

## Entry format — learnings

```
### [YYYY-MM-DD] Short title
- **Area**: project / module
- **Source**: session-name | thread/pr/branch reference
- **Detail**: 1–3 specific, actionable sentences
```

### Example — learning

```markdown
---
type: learning
session: kunskap-v1.0.1-curator-permissions
created: 2026-05-06
sources:
  - pr: https://github.com/Abeansits/kunskap/pull/10
---

### [2026-05-06] `claude --allowed-tools` matchers treat `*` as a literal asterisk

- **Area**: kunskap / claude-headless permissions
- **Source**: kunskap-v1.0.1-curator-permissions | pr: https://github.com/Abeansits/kunskap/pull/10
- **Detail**: `Bash(git -C * foo:*)` does NOT match `git -C /abs/path foo`. Falls through to the bare-form rule. Workaround: `cd $vault` before spawn so the bare form (`Bash(git foo:*)`) covers everything.
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

### Example — idea

```markdown
---
type: idea
session: kunskap-v1.1-recall-design
created: 2026-05-06
sources:
  - branch: origin/feat/v1.1-capture-recall
  - thread: ~/.claude/projects/kunskap-v1.1/2026-05-06-design.jsonl
---

### [2026-05-06] Plan-mode hook for forced recall on plan entry

- **Area**: kunskap / hooks
- **Source**: kunskap-v1.1-recall-design | branch: origin/feat/v1.1-capture-recall
- **Impact**: medium
- **Problem**: CLAUDE.md instruction "run /kunskap:recall at task start" relies on the agent reading and following the contract; effectiveness varies by model + session length.
- **Suggestion**: Add a hook on plan-mode entry that injects the most-recent prior-art hits as a system reminder. Belt-and-braces with the CLAUDE.md instruction; non-negotiable for high-value tasks.
```

## Rules

- One entry per file. Keep it concise.
- Be specific and actionable, not generic.
- Log reusable knowledge, not task-specific context.
- **Never include secrets, API keys, tokens, or PII** in entries.
- Skip the capture entirely if you have nothing new — no filler entries.
