# Kunskap

Knowledge-base plugin for Claude Code. Sessions write loose notes into an inbox; a librarian agent compiles them into prose articles with `[[wikilinks]]` and `## Sources` provenance — Karpathy's compile model, distributed as a Claude Code Skill (omarsar0). Sibling to Vigil / Sigil / Ting.

## Status

**v1.0.0 — multiplayer-safe, marketplace-installable, search-enabled.** Sebastian, Paul, and Matt can clone the marketplace, install the plugin, run `kunskap init` on a shared research vault, and start using it. The phased rollout (P0 → P6) shipped on schedule; the design lives at [`docs/kunskap-design.md`](docs/kunskap-design.md).

Post-v1.0 work (cron / GitHub Actions, settings UI, search v2 with embeddings) is driven by real-usage findings, not speculative roadmaps — see the design's §Open decisions for the current deferral list.

## Install

```
/plugin marketplace add Abeansits/kunskap-marketplace
/plugin install kunskap@kunskap-marketplace
```

Then per machine, configure your identity (one-time):

```
kunskap config user --name <yourslug-lowercase> --host <stable-host-name>
```

`--name` is lowercase to pre-empt `Paul`/`paul` collisions in the role check; `--host` should be set explicitly (don't rely on `hostname -s` — machine renames silently break role checks; see Risk #5).

Verify:

```
kunskap whoami
# → yourslug@stable-host-name
```

## The three core flows

### 1. Capture — sessions write inbox notes

The `kunskap-vault` skill auto-loads in projects that opted in (`.claude/kunskap.json` marker). The launch footer reminds Claude to capture learnings + ideas to `<vault>/raw/inbox/` at task end. The `SessionEnd` hook commits and pushes (shared vaults only — solo vaults never push, per Risk #8).

To opt a project in:

```
cd ~/Projects/my-project
/kunskap:learn enable --vault ~/Projects/my-vault
```

To bootstrap a fresh vault:

```
# Solo (never pushes):
kunskap init ~/Projects/my-vault --name "My Vault"

# Shared (sets shared = true, adds origin):
kunskap init ~/Projects/team-vault --name "Team Vault" \
  --shared git@github.com:org/team-vault.git
```

### 2. Curate — compile inbox into wiki

Run on the curator's primary machine (set in `<vault>/_meta/roles.toml`):

```
/kunskap:curate <vault-path>
# or: kunskap curate --vault <vault-path>
```

The curator agent reads `<vault>/raw/inbox/`, routes each note (Lane 1 = additive extension to existing article, Lane 2 = meaning-changing draft, Lane 3 = new article, archive otherwise), atomic-commits each article, and records the run in `<vault>/_meta/last-run/curator.json`. Hand edits to `wiki/*.md` are preserved.

Drafts surface for human triage:

```
/kunskap:drafts list
/kunskap:drafts show <id>
/kunskap:drafts approve <id> [--into <article-slug>]
/kunskap:drafts reject  <id> --reason "<why>"
/kunskap:drafts defer   <id>
```

The linter audits the wiki without writing (read-only contract enforced at the CLI):

```
/kunskap:lint
# or: kunskap lint [--vault <vault-path>] [--format text|json]
```

Findings: drift across articles, stub clusters, draft staleness (≥7d), offline arrivals (≥48h), curator absence (≥2d), identity mismatches.

### 3. Recall — search from inside a session

```
/kunskap:recall <query> [--author X] [--tag Y] [--limit N] [--format text|json]
# or: kunskap recall <query> ...
```

`recall` runs `rg --type md` over `<vault>/wiki/` and `<vault>/raw/inbox/` (Stage 1, load-bearing) and reranks paths by Obsidian's relevance when the desktop app is running with the CLI enabled (Stage 2, best-effort). `--format json` returns `{hits: [{path, line, snippet, score, author?, tags?}]}` for agent consumption.

`recall` is identity-independent — works on any machine regardless of role.

## Roles + hand-off

The curator and linter run only on their designated machine. Check primaries:

```
cat <vault>/_meta/roles.toml
```

Hand off to a teammate:

```
vim <vault>/_meta/roles.toml          # change roles.<role>.primary
git -C <vault> commit -am "<role>: hand off to <name>"
git -C <vault> push
```

Override a single run:

```
kunskap curate --vault <vault> --force --yes
kunskap lint   --vault <vault> --force --yes
```

`--force` runs are recorded with `forced: true` in `_meta/last-run/<role>.json` for audit. A freshly-init'd vault carries `primary = "TBD"` for both roles — that warns and proceeds (solo workflows and pre-handoff teams need to work without role config).

## Risks worth surfacing

The full risk register lives in [`docs/kunskap-design.md`](docs/kunskap-design.md) §Risks. Three are operational and worth surfacing here:

**Risk #5 — Identity fragility.** The identity-string `<user>@<host>` doubles as the role-assignment key. `hostname -s` mutates on machine renames and silently breaks role checks. Pass `--host` explicitly on `kunskap config user` and don't change it. The CLI prints a stderr warning when `--host` is omitted.

**Risk #7 — Vault privacy.** A vault holds research notes. Confirm the path before `kunskap init` and `/kunskap:learn enable` (the CLI prompts; pass `--yes` only in scripts you've already verified). The marker file's `confirmed_at` field surfaces a 30d staleness warning in `/kunskap:learn status`.

**Risk #8 — Wrong-remote pushes.** This plugin repo and the marketplace repo are content-free and public. Vault repos (`<your-team>-research/`) **must be private**. Verify your vault's remote before any push; the SessionEnd hook refuses to push vaults whose `_meta/kunskap.toml` doesn't say `shared = true`.

## Roadmap

Full design: [`docs/kunskap-design.md`](docs/kunskap-design.md). v1.0 is the end of the planned phase chain (P0 → P6); post-v1.0 work is driven by real-usage findings.

| PR | Scope |
|---|---|
| **P0** | Plugin manifest, `bin/kunskap`, `config user` / `whoami`, CI. |
| **P1** | Curator agent + manual trigger + curator-contract tests. |
| **P2** | `/kunskap:learn enable\|disable\|status` + `SessionStart` / `SessionEnd` sync hooks. |
| **P3** | `kunskap init <vault-path>` + drafts surface. |
| **P4** | Linter agent + health checks. Read-only contract. |
| **P5** | Single-primary role assignment + sharded `_meta/last-run/{curator,linter}.json` + headless-agent CWD fix. |
| **P6 (this release)** | Search (`kunskap recall`) + Obsidian Bases starters + marketplace listing + README polish. |

## Lessons from real usage

_Real-usage notes will land here after Sebastian, Paul, and Matt run v1.0 against an actual shared research vault for a few weeks. v1.0 ships with smoke-test coverage against `~/.vigil-vault` (the v0 librarian recipe vault) but not yet with multi-author production findings._

## License

MIT — see [`LICENSE`](LICENSE).
