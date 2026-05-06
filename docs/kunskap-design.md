---
title: Kunskap — Technical Design (v1)
created: 2026-05-04
status: shipped (v1.0; this doc captures the design as locked at P0)
lineage: sibling to Vigil / Sigil / Ting
---

# Kunskap — Technical Design

## TL;DR

Kunskap is a Claude Code plugin that turns any directory into a curator-managed Obsidian-style knowledge vault. Sessions write loose notes into `raw/inbox/`; a librarian agent (Curator nightly + Linter weekly) compiles them into prose articles with `[[wikilinks]]` and `## Sources` provenance, per Karpathy. The plugin ships a `kunskap` CLI inside `bin/` so the same engine drives `/kunskap:curate` slash invocations and shell ops. Per-project opt-in via `/kunskap:learn enable --vault <path>` writes a marker file; hooks no-op without it. Multiplayer = single-primary-curator (no fallback, no advisory lock — see §Q4 for why locks are intentionally avoided); everyone writes only to `raw/inbox/`. Search is `rg` first; Obsidian 1.12 CLI is a best-effort second pass when the desktop app is running.

## Decisions Locked

From `state.json#kunskap_project.design_decisions_locked` + the contract docs. Treated as fixed.

1. **Name + family.** Kunskap (Swedish, "knowledge"). Sibling to Vigil/Sigil/Ting.
2. **Three-repo split.** `<personal-vault>/` (solo, stays) + `kunskap/` (content-free plugin, public-ish) + `<team-vault>/` (private vault, the team).
3. **Architecture per Karpathy.** `raw/inbox/` → LLM-compiled wiki of prose articles with `[[wikilinks]]` + `## Sources` provenance. Not bullet-lists. LLM owns the wiki; humans read.
4. **Distribution per omarsar0.** Claude Code Skill model; auto-load by description.
5. **Search v1 = `rg` + Obsidian CLI + Bases.** No custom RAG, embeddings, or vector DB.
6. **Multiplayer.** Single librarian writes `wiki/`; everyone writes only to `raw/inbox/`. Conflict-free by construction.
7. **Privacy.** Per-project opt-in via `/kunskap:learn enable --vault <path>`. No prompts in unconfigured projects.
8. **Sync.** SessionEnd hook git-pushes shared vaults only. Personal vaults never push.
9. **Two librarian roles.** Curator (inbox→articles) + Linter (Karpathy "health checks").

**Out of scope for this design**: custom RAG / embeddings / vector DB; web/mobile UI; vault federation; public sharing of vault content; synthetic-data finetuning; real-time collab. Per-project opt-in is the privacy primitive; no other privacy mechanism ships in v1.

---

## Q1 — Plugin OR CLI OR both?

**Plugin is the deliverable; CLI ships *inside* it as `bin/kunskap`.** Per the canonical reference, `bin/` is auto-added to the Bash tool's PATH when the plugin is enabled — so one repo, two surfaces. Slash commands shell out to the same binary; humans can call it directly for manual ops.

CLI-alone loses in-session integration (skills, hooks). Plugin-alone re-implements routing in three skills. Two repos = engineering tax. Reject all three.

**Contract for contributors**: contributing requires Claude Code + the Kunskap plugin. Reading the vault requires only Obsidian — the wiki is plain markdown.

**Cron deferred.** GitHub Actions on the shared vault repo is the v2 path if/when "curation should fire while everyone is offline" becomes a real need. `bin/kunskap curate` is already designed to run headlessly, so v2 = a workflow file, not a re-architecture.

---

## Q2 — Plugin file tree

```
kunskap/                                       # repo root (public-ish, content-free)
├── .claude-plugin/
│   └── plugin.json                            # required: name="kunskap"; version, description, author, repo, license
├── skills/
│   └── kunskap-vault/
│       └── SKILL.md                           # the auto-loaded "you're in a Kunskap vault" skill (description-triggered)
├── commands/                                  # user-typed slash commands (legacy flat-MD form, still supported)
│   ├── learn.md                               # /kunskap:learn enable|disable|status
│   ├── recall.md                              # /kunskap:recall <query> [--author X] [--tag Y]
│   ├── curate.md                              # /kunskap:curate (manual librarian trigger)
│   ├── drafts.md                              # /kunskap:drafts list|show|approve|reject|defer
│   └── lint.md                                # /kunskap:lint (manual linter trigger)
├── agents/
│   ├── curator.md                             # the librarian agent — invoked by /kunskap:curate or hook
│   └── linter.md                              # the health-check agent — invoked by /kunskap:lint or hook
├── hooks/
│   ├── hooks.json                             # SessionStart, SessionEnd, optional UserPromptSubmit (all opt-in gated)
│   ├── session-start.sh                       # git pull --rebase IF shared-vault marker present
│   ├── session-end.sh                         # git add raw/inbox && commit && push, IF shared
│   └── _shared.sh                             # helpers: detect-vault, no-op-if-disabled, identity-load
├── bin/
│   └── kunskap                                # the CLI (bash for v1, escape hatch to Python only if needed)
├── templates/                                 # consumed by `kunskap init`
│   ├── vault-init/                            # scaffolded into a new vault root
│   │   ├── raw/inbox/.gitkeep
│   │   ├── wiki/_index.md
│   │   ├── wiki/learnings/.gitkeep
│   │   ├── wiki/ideas/.gitkeep
│   │   ├── wiki/_drafts/.gitkeep
│   │   ├── wiki/concepts/.gitkeep
│   │   ├── _meta/kunskap.toml
│   │   ├── _meta/roles.toml
│   │   ├── .gitignore
│   │   └── README.md                          # one-page contributor doc, generated with vault name filled in
│   ├── article.md                             # frontmatter + ## Sources stub (Karpathy compile output shape)
│   └── inbox-note.md                          # frontmatter + entry stubs (LAUNCH_FOOTER conventions, lifted)
├── docs/
│   ├── README.md                              # project README, install + concepts
│   ├── ARCHITECTURE.md                        # how the pieces fit (this doc, condensed, post-ship)
│   └── ROLE-ASSIGNMENT.md                     # the algorithm + failure modes (excerpted from §Q4)
└── .gitignore
```

**Mandatory:** `.claude-plugin/plugin.json`, `skills/kunskap-vault/SKILL.md`, `commands/learn.md`, `bin/kunskap`. Everything else is optional in the manifest sense (auto-discovery; absent dirs are simply skipped).

**Pieces I considered and rejected:**
- `.mcp.json`. Tempting to wire an obsidian MCP through here, but those servers are typically per-machine (user scope), not per-plugin. Don't double-wire. Skip.
- `monitors/`. Could watch `raw/inbox/` and notify Claude when new files arrive — clean idea but premature; nothing actionable until the curator runs anyway. Defer.
- `settings.json`. Lets the plugin set a default agent. We don't want to override the user's main thread. Skip.

---

## Q3 — Vault bootstrap (`kunskap init`)

**Yes, exists. Form:**

```bash
kunskap init <path> [--shared <git-remote>] [--name <human-readable>]
```

Behaviour:

1. Reject if `<path>` exists and is non-empty (prompt to confirm if `--force`).
2. `mkdir -p <path>` and copy `templates/vault-init/` into it. Substitute `{{name}}` and `{{created}}` in `_meta/kunskap.toml`, `wiki/_index.md`, `README.md`.
3. `git init` in `<path>`.
4. If `--shared <remote>`: `git remote add origin <remote>`. Set `_meta/kunskap.toml#shared = true`. Without `--shared` the vault is solo.
5. Drop a sample inbox note (`raw/inbox/example-2026-05-04.md`) and a sample wiki article (`wiki/learnings/example-topic.md`) so users see the shape without running the curator.
6. Print a one-screen "next steps" panel: `cd <path> && kunskap status` and "to enable in a project: cd <project>; /kunskap:learn enable --vault <path>".

**`_meta/kunskap.toml` schema:**

```toml
# Vault metadata. Edit by hand; the CLI reads this, never writes back.
[vault]
name = "kunskap-research"          # human-readable, used in commit messages
created = "2026-05-04"             # ISO date, vault birthday
shared = true                      # false = solo, true = git push allowed
schema_version = 1                 # bump when shape changes

[wiki]
default_lane = "learnings"         # learnings | ideas — fallback if curator can't classify
draft_review = "human"             # who reviews wiki/_drafts (right now: human, only)
```

**`_meta/roles.toml` schema** (see §Q4 for semantics — single primary, no fallback in v1):

```toml
[roles.curator]
primary = "alice@laptop"           # identity-string, format: <user>@<host>; only this machine runs curator
# fallback intentionally absent in v1; see §Q4 for why

[roles.linter]
primary = "bob@desktop"
```

No `schedule` field in v1 — v1 fires on demand via `/kunskap:curate` and `/kunskap:lint`. v2 may add a launchd/systemd installer that fires on the primary machine only; the `schedule` field gets reintroduced then.

---

## Q4 — Role assignment

**Single-primary, no fallback, no advisory lock. Manual firing only. GH Actions deferred.**

In-vault advisory locks (acquired by commit-and-push) are intentionally avoided. They have a TOCTOU race: two machines that both pull-clean and both write `_meta/curator.lock` end the loser's `git pull --rebase` in a YAML conflict on the lock file itself, leaving the vault mid-rebase. (The "git lfs lock" analogy doesn't hold — git lfs uses an atomic server endpoint, not file-plus-commit.)

**Mechanism**:
1. `_meta/roles.toml` — exactly one `primary` per role, no fallback.
2. CLI refuses to run unless `kunskap whoami == roles.<role>.primary`, except with `--force` (interactive confirmation + `forced=true` in the run record).
3. After every run the curator writes `_meta/last-run.json` (informational, not gating):
   ```json
   { "curator": { "ran_at": "...", "by": "alice@laptop", "inbox_processed": 7, "articles_written": 3, "drafts_routed": 1 } }
   ```
4. No scheduler in v1. Fires only via `/kunskap:curate` or `kunskap curate --vault <path>`.

**Why this is enough for a small team**: with one primary firing manually, contention requires the primary to fire two runs at the same second. If that happens, both run on a stale snapshot, the second push fails non-fast-forward, second run aborts cleanly (no half-rebased state, because there's no shared file both are racing on). Primary offline = no curation that night, inbox grows, curator catches up next time. Hand-off = edit `roles.toml`, commit, push. No locks to drain.

**Personal vault** (`shared = false`): roles file ignored, identity check skipped, never pushes. Contention impossible (one machine).

---

## Curator contract

What the curator *does*, in detail. `agents/curator.md` implements this contract. The norms + prompt rules + recipes here are the source-of-truth that the agent prompt mirrors.

**Operating norms (v0 recipe §1)**:
1. Librarian owns all of `wiki/` (no human-vs-agent dir split).
2. Lane 1/2 is a *trust gate*, not directory placement. Lane 1 = additive (new gotcha, source bump, pattern extension); land directly. Lane 2 = changes meaning of existing claims; route to `_drafts/`.
3. Lane 2 *with explicit in-doc invitation* ("Revisit on 3rd use") → may promote into the doc body. Honor invitations.
4. Lane 2 without invitation → draft. `confidence` + `reason` + `source_count` in frontmatter.
5. Ambiguous norm → ask before acting; propose options + tradeoffs.

**The curator MUST**:
- **Process inbox-by-inbox, commit atomically per article.** Loop body: `read inbox file → decide route → write article (or extend) → git mv inbox→Archives/ → git commit "kunskap: {route} <article>"`. Crash mid-loop = previous articles committed, current file still in inbox, next run resumes cleanly. Nothing in the framework enforces this; the prompt MUST state it.
- **Route to one of three buckets**: (a) **extend** an existing `wiki/learnings/<slug>.md`, (b) **new article**, (c) **draft** in `wiki/_drafts/<topic-slug>--<date>.md`.
- **Preserve hand edits.** When extending, diff the existing file against its prior `## Sources`-derived form. Detected hand-edit → route to `_drafts/{slug}-update.md` instead of overwriting. This is v1's answer to Risk #3.
- **Date discipline (v0 §2a)**: use the inbox-cycle date in all frontmatter regardless of midnight drift during a long run.
- **Wikilinks (v0 §2b, §2d)**: kebab-case files + natural-language aliases via `aliases:` frontmatter on the target. Single-ref name-mismatch with existing file → add alias. Single-ref no-file → orange aspirational link. ≥2 refs no file → write `wiki/concepts/<slug>.md` (≤30 lines).
- **`## Sources` footer per-source, not merged (v0 §2e, §2f)**: one `### {filename}` sub-heading per inbox file, entry inline-quoted underneath. Multi-finding files get qualifiers (`### {file} (third sub-finding)`). Cite a multi-finding file in every relevant article's `sources:` frontmatter; quote ONLY the relevant sub-finding in each article's body block.
- **Frontmatter for drift detection**: `last_curated: <iso-date>`, `source_count: N`, `sources: [...]`.
- **Never silently fail.** Unclassifiable inbox note → draft with `confidence: low` and `reason: <classifier-output>`. Never archive without producing a wiki target.

**The curator MUST NOT**: batch writes and commit at end; rewrite an extended article from scratch; archive an inbox file without a corresponding wiki write or draft.

### CLI primitives needed by the curator (v0 recipe §4)

| Tool | Purpose | Phase |
|---|---|---|
| `kunskap link-stubs` | Scan wiki for `[[stubs]]`; classify resolved / single-ref / multi-ref-needs-stub / name-mismatch-needs-alias. **Biggest gap surfaced by v0.** | P1 |
| `kunskap audit-coverage` | Cross-check `raw/inbox/` + `Archives/processed-inbox/` against article `sources:`. Report silent drops + broken provenance. | P1 |
| `kunskap suggest-topics` | Cluster the inbox before write. v0 did this manually in 5 min for 13 notes; bottleneck at 50+. | P4 |
| `kunskap dry-run` | Preview the curator's classifications + draft routing without writing. | P4 |
| `kunskap split-inbox` | Slice multi-finding inbox files into per-cluster blocks. | P5 |
| `inbox-note` template with `suggested_topic:` | Sessions pre-seed the curator's clustering. | P3 |

**Stub discovery recipe** (lift verbatim into `agents/curator.md`, per v0 §2c):

```sh
grep -roh '\[\[[^]]*\]\]' wiki/learnings/*.md wiki/ideas/*.md \
    wiki/_drafts/*.md wiki/patterns/*.md wiki/concepts/*.md \
  | sort | uniq -c | sort -rn
```

### Drafts review loop

`wiki/_drafts/` was a black hole in draft 1. Pass-2 flagged the missing surface. Add to v1:

| Surface | Action |
|---|---|
| `kunskap drafts list` / `/kunskap:drafts` | List pending drafts, sorted by age. Frontmatter shows `confidence`, `reason`, `source_count`, `created`. |
| `kunskap drafts show <id>` | Print full draft content + sources. |
| `kunskap drafts approve <id> [--into <article-slug>]` | Move draft → `wiki/learnings/<slug>.md` (or merge into specified article). Move draft file to `Archives/processed-drafts/approved/`. |
| `kunskap drafts reject <id> --reason "<why>"` | Move to `Archives/processed-drafts/rejected/{id}.md` with a reason header. The rejection itself is the "humans saw this" signal. |
| `kunskap drafts defer <id>` | Stamp `deferred_at: <iso>` in frontmatter; leave in `_drafts/`. The linter surfaces drafts deferred ≥14 days. |

This pulls heavily from a prior `/drafts` surface (proven in solo flow). v1 ports that surface into the plugin.

The linter's weekly run includes a "drafts staleness" check: any draft `created` ≥ 7 days ago shows up in the linter report.

---

## Q5 — Identity bootstrapping

```bash
kunskap config user --name <slug> [--email <addr>]
```

Writes:

```toml
# ~/.config/kunskap/identity.toml
[user]
name  = "alice"                    # the slug. used as `author:` in inbox notes.
email = "alice@example.com"        # optional, only used in vault git commits
host  = "laptop"                   # optional override; default = `hostname -s`
```

**Identity-string** for role + provenance = `{user.name}@{user.host}`. **Set `host` explicitly** via `--host laptop` rather than relying on `hostname -s` (which mutates on machine renames and silently breaks role checks). Stored in `~/.config/kunskap/identity.toml` (XDG path), per-machine.

**Fail-closed when missing.** `kunskap whoami` exits non-zero with a clear stderr message. `/kunskap:learn status` prints `IDENTITY: not set — run kunskap config user --name <slug>`. Session-end hook treats non-zero whoami as "skip commit, log to `~/.cache/kunskap/last-warning`" — never commits under an `unknown` identity. `/kunskap:learn status` cross-checks against `_meta/last-run.json`; if your identity-string doesn't match a role's `primary` that you appear under elsewhere, status prints a "primary-mismatch" warning. The linter surfaces "no curator run ≥2d" as a health-check finding.

**Agents** identify as `agent:claude-{session-name}`. The `agent:` prefix never collides with human identities and never appears as `primary` in `roles.toml`. CLI exposes `kunskap whoami --agent <session-name>` for the curator's `## Sources` footers.

---

## Q6 — Hooks

All hooks no-op when `.claude/kunskap.json` is missing in the project. That file is written by `/kunskap:learn enable` and contains `{"vault": "<absolute-path>", "enabled": true}`.

### `hooks/hooks.json`

Top-level `description` and per-handler `timeout` fields are intentionally absent — neither appears in any canonical example, and both are pending hands-on verification before adoption.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-end.sh"
          }
        ]
      }
    ]
  }
}
```

**SessionEnd matcher values** (per the canonical hooks reference): `clear`, `resume`, `logout`, `prompt_input_exit`, `bypass_permissions_disabled`, `other`. v1 uses `"*"` (fire on all of them); a v2 refinement could use `prompt_input_exit|other` to skip `clear` (which doesn't really mean session over) — defer until we observe noise.

**Hook reliability is best-effort, not guaranteed.** The canonical reference is silent on whether `SessionEnd` fires on SIGKILL, whether Claude Code waits for the hook, and whether per-handler timeouts are enforced. The v0 SessionEnd contract elsewhere in this doc treats inbox sync as best-effort: if the hook doesn't fire (hard kill, OS forced shutdown), the inbox capture is in the local vault but unpushed. The next session-start `git pull --rebase` doesn't lose it; the next session-end pushes it. Document this clearly to users: **closing your laptop with a kunskap session running is fine; SIGKILL'ing the Claude Code process loses that session's inbox commit until next session-end**.

No `UserPromptSubmit` hook in v1. The temptation is to inject "search vault first" reminders, but that's exactly the kind of noise the v0 librarian session is testing whether the curator surfaces naturally. Hold for v2.

### `session-start.sh` (literal)

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Opt-in gate
[[ -f "$CLAUDE_PROJECT_DIR/.claude/kunskap.json" ]] || exit 0

# 2. Identity required (fail-closed)
"$CLAUDE_PLUGIN_ROOT/bin/kunskap" whoami --quiet \
  || { echo "Kunskap: identity not set; run kunskap config user" >&2; exit 0; }

# 3. Resolve vault, sync only if shared
vault="$(jq -r .vault "$CLAUDE_PROJECT_DIR/.claude/kunskap.json")"
[[ -d "$vault" ]] || { echo "Kunskap: vault $vault missing" >&2; exit 0; }

shared="$("$CLAUDE_PLUGIN_ROOT/bin/kunskap" --vault "$vault" config get shared)"
[[ "$shared" == "true" ]] || exit 0

# 4. git pull --rebase, fail-soft (don't block session start on network issues)
( cd "$vault" && git pull --rebase --autostash ) \
  || echo "Kunskap: vault pull failed; continuing with local copy" >&2

exit 0
```

### `session-end.sh` (literal)

```bash
#!/usr/bin/env bash
set -euo pipefail

[[ -f "$CLAUDE_PROJECT_DIR/.claude/kunskap.json" ]] || exit 0
"$CLAUDE_PLUGIN_ROOT/bin/kunskap" whoami --quiet || exit 0

vault="$(jq -r .vault "$CLAUDE_PROJECT_DIR/.claude/kunskap.json")"
[[ -d "$vault" ]] || exit 0

shared="$("$CLAUDE_PLUGIN_ROOT/bin/kunskap" --vault "$vault" config get shared)"
[[ "$shared" == "true" ]] || exit 0   # personal vaults never push

cd "$vault"

# Only commit if the inbox actually changed during this session
git add raw/inbox
if git diff --cached --quiet; then
  exit 0
fi

session_id="${CLAUDE_SESSION_ID:-unknown}"
who="$("$CLAUDE_PLUGIN_ROOT/bin/kunskap" whoami)"
git commit -m "kunskap: inbox capture from session ${session_id} (${who})" --quiet

# Push fail-soft: prefer to leave the work locally rather than block session shutdown
git push --quiet 2>/dev/null \
  || echo "Kunskap: vault push failed; will retry next session" >&2

exit 0
```

**Shell choices**: `set -euo pipefail` to fail loudly during dev; opt-in miss exits 0 so unrelated projects aren't disturbed. No commit when inbox unchanged (avoids empty-noise commits). `--rebase --autostash` preserves any in-progress curator state. Fail-soft on push — closing your laptop with a flaky network shouldn't hang shutdown for one missed sync.

---

## Q7 — Distribution + Install

### v1 path: Anthropic plugin marketplace, private repo

Per the canonical docs, `/plugin marketplace add <github-shorthand>` resolves a marketplace by GitHub shorthand, and marketplaces can be private (`/en/plugin-marketplaces#private-repositories`). For a small team this is the lowest-friction path: one repo (`kunskap-marketplace`, separate from the plugin repo), and contributors run one command.

**Marketplace file path matters.** The marketplace manifest lives at `.claude-plugin/marketplace.json` *inside* the marketplace repo (not bare `marketplace.json` at the repo root). Layout:

```
kunskap-marketplace/                       # the marketplace repo (private GitHub)
└── .claude-plugin/
    └── marketplace.json                   # points to the kunskap plugin repo
```

The `marketplace.json` content lists the kunskap plugin and its source repo. See `/en/plugin-marketplaces` for the schema.

### One-page README excerpt

```markdown
# Kunskap — install

## Prereqs
- Claude Code installed and authed (https://code.claude.com)
- An Obsidian vault on disk (yours or the team's). If you don't have one yet:
    `kunskap init ~/Projects/kunskap-research --shared git@github.com:Abeansits/kunskap-research.git`

## Install
    /plugin marketplace add Abeansits/kunskap-marketplace
    /plugin install kunskap@kunskap-marketplace

## Configure your identity (one-time, per machine)
    kunskap config user --name charlie --email charlie@example.com --host desktop

(The explicit --host avoids breakage if your machine gets renamed; see "Identity fragility" in the design doc.)

## Enable in a project
    cd ~/Projects/research-poc
    /kunskap:learn enable --vault ~/Projects/kunskap-research
    # confirms vault path before writing the marker; cancel if it's wrong

## Verify
    /kunskap:learn status
    # → enabled  vault: ~/Projects/kunskap-research  identity: charlie@desktop  shared: true
    #   role-check: not primary (curator: alice@laptop; linter: bob@desktop)
```

### Fallbacks

- **Local clone for plugin development.** `git clone … kunskap && claude --plugin-dir ./kunskap` (per `/en/plugins#test-your-plugins-locally`). This is the path used during plugin development (PR0–P2).
- **Manual install (no marketplace).** `git clone …/kunskap ~/.claude/plugins/cache/local/kunskap && /plugin enable kunskap`. Documented as escape-hatch only.

---

## Q8 — Search interface

### User-facing surfaces

| Surface | Form | What it runs |
|---|---|---|
| `/kunskap:recall <query>` | slash command | `kunskap recall <query>` — see CLI below |
| `kunskap recall <query>` | CLI | `rg` first; if Obsidian app is running, also runs `obsidian search query="<query>" format=json` and merges results |
| Curator/linter agent | tool calls | `rg` only (Obsidian CLI requires the desktop app open, which is unsafe to assume in agent context) |

### `kunskap recall` semantics

```bash
kunskap recall <query> [--author X] [--tag Y] [--vault <path>] [--limit N]
```

1. **Stage 1 — `rg`.** `rg --json --type md "<query>" "$vault/wiki" "$vault/raw/inbox"` over the resolved vault. Format hits as `{path, line, snippet, author?, tags?}` by reading frontmatter. Filter by `--author` / `--tag` post-hoc.
2. **Stage 2 — Obsidian (best-effort).** Detect with `command -v obsidian && pgrep -x Obsidian >/dev/null`. If both: invoke `obsidian search` and merge by path (prefer the obsidian record's relevance score where it disagrees). Skip if either check fails. Never block on this stage.
3. **Output** sorted by score, truncated to `--limit` (default 20). For agent-callability, `--format json` returns the structured array; default is human-readable bulleted snippets.

**Stage-2 graceful degradation is load-bearing.** If Obsidian's CLI shape changes or the integration becomes "open the Obsidian search view with the query pre-populated" rather than a programmatic merge, the Stage-2 surface degrades but Stage-1 still carries — `rg` is the design's load-bearing search primitive.

### Why not Bases here

Bases is an Obsidian-internal view system (YAML-defined filters and formulas, evaluated by Obsidian itself; per [obsidian.md/help/bases/syntax](https://obsidian.md/help/bases/syntax)). It's amazing for *humans browsing in Obsidian* — set up a "all <topic> notes by <author>, last 30 days" view once, click it forever. But it doesn't expose a CLI/programmatic surface. So Bases is a **vault-side artifact**, not a Kunskap CLI primitive: ship a few canonical Bases (`bases/by-topic.base`, `bases/by-author.base`) inside `templates/vault-init/` and let humans use them via the Obsidian UI. Don't try to replicate Bases in `kunskap recall`.

---

## Vault layout (concrete)

```
<vault-root>/
├── .git/
├── .gitignore                    # /Archives kept, /.obsidian/workspace.json ignored
├── README.md                     # generated by kunskap init
├── _meta/
│   ├── kunskap.toml              # see §Q3
│   ├── roles.toml                # see §Q4 (single primary, no fallback)
│   └── last-run.json             # informational record of curator/linter runs
├── raw/inbox/                    # the only place humans + agents write
│   └── {type}-{slug}-{date}.md
├── wiki/
│   ├── _index.md                 # regenerated by curator each run
│   ├── _drafts/                  # Lane 2 — drafts pending human review
│   ├── learnings/                # Lane 1 articles
│   ├── ideas/                    # idea- prefix entries
│   ├── concepts/                 # ≤30-line stubs for [[wikilinks]] used in 2+ articles
│   ├── patterns/                 # canonical patterns (librarian-writable, see norm 1)
│   └── bases/                    # Obsidian Bases views (hand-edited)
└── Archives/
    ├── processed-inbox/          # inbox files moved here after compile (never deleted)
    └── processed-drafts/{approved,rejected}/
```

`Archives/` is in the repo (provenance is a feature). No lock files — see §Q4 for why.

### Two specifics from §Q2 worth surfacing here

**`skills/kunskap-vault/SKILL.md`** — the auto-loaded skill. Description must reference the marker file (`.claude/kunskap.json`) as the trigger condition; that scopes the skill to opted-in projects without an explicit user invocation. Body covers pre-flight search, post-task inbox capture, identity rules, and link to `/kunskap:recall`.

**`agents/curator.md` and `agents/linter.md`** — plugin agents use `tools` / `disallowedTools` (not the skill-style `allowed-tools`); they do **not** support `permissionMode`, `hooks`, or `mcpServers`. v1 curator: `model: opus`, `tools: Read Write Edit Bash`, `disallowedTools: WebFetch WebSearch`. System prompt = §Curator contract above + v0 recipe-note edge cases + the v0 launch prompt distilled to take vault path as `$ARGUMENTS`. The linter is similar with a "health checks" system prompt (drift, missing connections, drafts staleness, offline-arrivals, identity mismatch).

---

## Phased rollout

PR-by-PR breakdown, mirroring the bridge-routing-design discipline. Each PR is independently reviewable; no PR ships behind a feature flag — they ship as visible features the team can use immediately.

| PR | Scope | Gates on |
|---|---|---|
| **P0 — scaffold** | `kunskap/` repo created. Plugin manifest, empty skill/`commands` placeholders, `bin/kunskap` stub that prints version. `kunskap config user`. CI that lints `plugin.json` against schema, validates `hooks/hooks.json` against the canonical reference, and runs shellcheck on `bin/kunskap`. | — |
| **P1 — curator agent + manual trigger + curator-contract tests** | `agents/curator.md` filled in from v0 librarian recipe note (or, fallback, written cold from §Curator contract — judgment call at P1 kick-off). `commands/curate.md` invokes it. `bin/kunskap curate --vault <path>` runs the same agent headlessly via `claude --plugin-dir`. **Critically**: ship a fixture-based test suite that asserts the §Curator contract rules hold — preserve hand-edits, atomic per-article commit, route-decision determinism on a frozen inbox set. No hooks, no roles, no lock — fires on demand only. Tested against a real personal vault (whose 13-note inbox is the smoke set). | P0; v0 librarian recipe note **OR** explicit decision to proceed without it |
| **P2 — opt-in + sync hooks** | `commands/learn.md` (`enable/disable/status`, with vault confirmation prompt). `.claude/kunskap.json` marker (with `confirmed_at` timestamp). `hooks/hooks.json` + `session-start.sh` + `session-end.sh`. Personal-vault path verified (no push). Identity-mismatch banner in `status`. | P1 |
| **P3 — vault bootstrap + drafts surface** | `bin/kunskap init`, `templates/vault-init/`. `commands/drafts.md` (list/show/approve/reject/defer) — port from conductor `CLAUDE.md`. New shared vault stood up by the curator-primary + cloned by team members as the smoke-test. Sample article + sample inbox note land. | P2; team members have Claude Code installed |
| **P4 — linter agent** | `agents/linter.md`, `commands/lint.md`, `bin/kunskap lint`. Health checks: drift, missing connections, drafts staleness (≥7d), offline-machine arrivals (≥48h), curator-not-run (≥2d), identity-mismatch surfaces. Fires manually first. | P3; vault has ≥10 wiki articles to lint over |
| **P5 — role assignment (single primary)** | `_meta/roles.toml` (single `primary` per role, no fallback). `bin/kunskap curate` honours the role check. `_meta/last-run.json` recording. **No advisory lock** — see §Q4 for why the lock variant was dropped. Two-machine smoke-test = primary machine fires, secondary machine declines with "not primary, use --force to override." | P4 |
| **P6 — search + polish** | `commands/recall.md`, `bin/kunskap recall`, `--format json` for agent calls. **Smoke-test the Obsidian CLI integration** with a real Obsidian 1.12 install (per §Q8 unverified flag). README finalized. Marketplace listing (`.claude-plugin/marketplace.json` in the marketplace repo). | P5 |

**P0 → P3 is the MVP.** P4 and P5 are quality-of-life. P6 is reach. If something has to be cut to ship, cut from the P6 end. **P1 contains the load-bearing testing work** — if the curator-contract tests aren't rigorous, every later phase is built on guesswork.

---

## Risks & open flags

1. **v0 recipe note: folded.** A v0 librarian recipe (354 lines) was folded into §Curator contract (5 norms + 13 prompt rules + stub recipe) and §CLI primitives at design time.

2. **Obsidian CLI partially unverified.** `obsidian.md/help/cli` 404'd at fetch time. The "must be running" constraint is consistent with how the CLI works (IPC to desktop) and with kepano/obsidian-skills, but the §Q8 search-flag syntax (`query="..."`, `format=json`) is not confirmed and must be smoke-tested at P6. Search v1 carries on `rg`; Obsidian is best-effort.

3. **Hand-edit overwrite.** §Curator contract's "preserve hand edits" rule is a *prompt* rule, not framework-enforced. P1 must include a regression test: hand-edit a wiki article, run curator with related new inbox notes, assert the edit survives. Fallback if the prompt can't reliably honor this: pre-commit hook that refuses hand-edits to `wiki/` outside `_drafts/`.

4. **Offline-contributor-for-a-week.** A contributor's session-end commits accumulate locally; on reconnect, their notes pile in but the curator already ran all week without them. Their contributions get curated in isolation = thin/duplicate articles. Mitigation: the linter flags inbox notes from authors not seen in `_meta/last-run.json` for ≥48h and biases next curator run toward re-reading related existing articles. Document for users: closing your laptop is fine; >48h offline = catch-up mode.

5. **Identity fragility.** `hostname -s` is volatile; mismatched identity-strings silently break role checks. v1 mitigation in §Q5 (explicit `--host`, status cross-check, linter health-check). Document in README.

6. **GitHub Actions cron deferred.** When "fire curator while everyone offline" becomes a real need, the path is GH Actions running `kunskap curate` on the shared vault repo. `bin/kunskap` already runs headlessly. When added: single-primary-OR-GH-Actions, never both fired in the same window.

7. **Vault-leak between projects.** Project `enable`-d against the wrong vault leaks across boundaries (personal notes → research vault, or vice versa). v1 mitigations: `kunskap init` + `/kunskap:learn enable` confirm the path before writing the marker; `.claude/kunskap.json` includes `confirmed_at` and `/kunskap:learn status` warns on >30d staleness; the skill description tells Claude to filter inbox notes for non-research content. Discipline-first; revisit if month-3 shows leakage in practice.

8. **Marketplace privacy.** Plugin repo (`kunskap/`) and marketplace repo can be public. Vault repo (`kunskap-research/`) **must** be private. Document the wrong-remote risk in README at P0.

9. **Curator contract testability.** Each rule in §Curator contract should map to a P1 test case. If P1 ships without those tests, the contract is decoration and the design is back where draft 1 was.

---

## Open decisions (snapshot at design time)

From v0 recipe §7 — items that don't fold cleanly into a design choice. Each has a recommendation; gate at `[KUNSKAP-DESIGN-READY]` if any of them needs a different call.

1. **Multi-human-into-wiki protocol**: locked decision says "humans write inbox, librarian writes wiki." When a human wants to land directly (e.g. a correction)? **Recommend** v1 = everything through inbox, plus the §Curator contract diff-detection routes hand-edits into drafts. v2 may add `kunskap edit <article>` if friction-heavy at month 3.
2. **Curation cadence**: v0 ran weekly-equivalent (1-week backlog). **Recommend** v1 = manual-only; v2 default = weekly cron with `/kunskap:curate` ad-hoc always available.
3. **Wikilink form**: kebab-case files + natural-language aliases (current) vs kebab-case everywhere (uniform but ugly). **Recommend** the current design; accept alias clutter as cost of readable prose.
4. **Inbox-writer as separate plugin?** Recipe §7.4 raises factoring out the inbox-write discipline so Vigil/agent-deck can reuse. **Recommend** v1 = one plugin; factor out in v2 if reuse demand materializes.
5. **Drafts naming**: v0 used proposal-title (`two-pass-codex-promotion-r3.md`) which goes stale. **Recommend** `_drafts/<topic-slug>--<date>.md` (consistent with inbox).
6. **Search v2**: omarsar0's "search is the open problem." **Recommend** revisit only when the wiki has ≥50 articles AND a real find-failure is reported. Don't pre-build.

---

## Appendix — one-page contributor README (target shape)

What lands at `kunskap-research/README.md` after `kunskap init --shared`:

```markdown
# Kunskap Research Vault — {{name}}

This is a Kunskap-managed research vault for {{team}}. The contract:

- **You write to `raw/inbox/`** as `{type}-{slug}-{date}.md` (see `_meta/templates/inbox-note.md`).
- **You don't edit `wiki/`** — the librarian (Curator + Linter) owns that. Read it freely; don't hand-edit.
- **Conflict-free by construction**: many writers to `inbox/`, single writer (the role-holding machine) to `wiki/`.

## To use this vault from Claude Code

    cd <any-project>
    /kunskap:learn enable --vault <path-to-this-vault>

Then sessions in that project will:
- pull the vault on session start
- get the kunskap-vault skill auto-loaded (vault-search-first discipline)
- commit + push your inbox capture on session end

## Roles

- Curator (nightly inbox→wiki compile): `{{roles.curator.primary}}`
- Linter (weekly health check):           `{{roles.linter.primary}}`

To trigger a curator run manually:
    /kunskap:curate

## Privacy

This vault is private. Don't push to public remotes. Don't paste contents into public-AI surfaces.
```

