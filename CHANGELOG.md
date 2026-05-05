# Changelog

## v0.3.0 — 2026-05-05 — P3 vault bootstrap + drafts surface

- `bin/kunskap init <path> [--shared <git-remote>] [--name <human-readable>] [--force] [--yes]` (per design §Q3). Self-state checks before external (P1 §5 lesson): validates target before requiring `git` on PATH or the template dir. Existing non-empty target requires `--force` plus interactive confirmation (Risk #7 — labeled `PATH:` / `ENTRIES:` summary so wrong-path mistakes are obvious). `KUNSKAP_AUTO_CONFIRM=1` and `--yes` bypass the prompt for scripts.
- `templates/vault-init/` — full scaffold: `_meta/{kunskap,roles}.toml`, `wiki/{_index.md,_drafts,learnings,ideas,concepts,patterns,bases}/`, `raw/inbox/`, `Archives/{processed-inbox,processed-drafts/{approved,rejected}}/`, `README.md`, `.gitignore`. Substitutes `{{name}}` / `{{created}}` / `{{shared}}` via bash literal-substitution (no sed escaping).
- `templates/article.md` + `templates/inbox-note.md` — version-controllable shape references for the curator and session-end captures.
- Sample notes seeded by `init` are deliberately **neutral** (no specific research domain, per Risk #7 vault-leak prevention) and shaped so a fresh vault passes `kunskap audit-coverage` with `covered_count >= 1`.
- `commands/drafts.md` + `bin/kunskap drafts list | show | approve | reject | defer` — port of the conductor `/drafts` surface (Sebastian's solo-flow pattern, ported into the plugin per design §Drafts review loop). Vault resolution: `--vault` flag wins, else project marker `.claude/kunskap.json`. `approve [--into <slug>]` either creates a new article or appends under a dated heading; archives original to `Archives/processed-drafts/approved/` with `approved_at` + `approved_into` stamps. `reject` requires `--reason` (rejection without reason loses context). `defer` stamps `deferred_at:` and is idempotent. Each action is a single git commit via `git add -A wiki Archives` (so deletions get staged, not just adds).
- Drafts naming convention locked: curator writes `_drafts/<topic-slug>--<iso-date>.md` (per design §Open decisions #5). Three new static-prompt tests assert the convention is encoded in `agents/curator.md` so future prompt edits can't silently drop it.
- CI `.github/workflows/p3.yml`: shellcheck, version-drift check, help-text covers `init` + `drafts`, templates tree completeness + substitution-placeholder lint, `commands/drafts.md` argument-hint check, full bats suite, end-to-end `init → curate --check → drafts list` smoke (the P3 hard contract: a freshly-init'd vault must satisfy curate-check and drafts-list with no manual fixup).
- `bin/kunskap version` bumps to `0.3.0`.

## v0.2.0 — 2026-05-05 — P2 opt-in surface + sync hooks

- `commands/learn.md` + `bin/kunskap learn enable | disable | status` (per design §Q6).
- `bin/kunskap config get <key>` with new global `--vault <abs-path>` flag — vault context reads `_meta/kunskap.toml [vault]`, user context reads `identity.toml [user]`. Missing `_meta/kunskap.toml` is fail-soft (`shared` returns `false`) so hooks survive pre-init vaults until P3.
- `hooks/hooks.json` + `session-start.sh` + `session-end.sh` + `_shared.sh` — SessionStart pull, SessionEnd commit-and-push for shared vaults only. **Hard fail-soft contract**: every error path exits 0 with a stderr message, never blocks session start/end. Both hooks detect mid-rebase wedge state (`.git/rebase-merge` / `.git/rebase-apply`) and refuse with an actionable message rather than auto-aborting (Codex Pass-2 block-ship).
- `.claude/kunskap.json` marker schema with `confirmed_at` ISO-8601 timestamp; `learn status` warns when confirmation is >30 days old (Risk #7 — vault-leak between projects).
- `learn enable` requires interactive confirmation unless `--yes` or `KUNSKAP_AUTO_CONFIRM=1` (Risk #7 privacy primitive). Confirmation prompt prints labeled `PROJECT:` / `VAULT:` lines so wrong-vault mistakes are obvious (Codex Pass-2).
- `learn status` cross-checks identity against `roles.toml` primaries and reports primary / not-primary (Risk #5 — identity fragility), and surfaces remote health for shared vaults (`REMOTE: <url>` or `REMOTE: not configured` — Codex Pass-2).
- Adversarial inbox fixtures (P1-deferred): two notes whose prose-label contradicts body content; behavioral assertions that the curator routes by policy, not by prose label.
- CI `.github/workflows/p2.yml`: `hooks.json` shape validation, `plugin.json` fuller-than-P0 schema validation (P0-deferred), shellcheck on hooks, dynamic test-count printout (no drift-prone hardcoded numbers per P1 §7), drift lint asserting CHANGELOG / README contain no `(N tests)` strings or retired workflow filenames.
- `bin/kunskap version` bumps to `0.2.0`.

## v0.1.0 — 2026-05-05 — P1 curator agent + manual trigger + tests

- `agents/curator.md` — curator agent encoding the design §Curator contract (Karpathy article-writing model, atomic per-article commits, hand-edit preservation per Risk #3, per-source `## Sources` footers, stub discovery recipe verbatim from v0 §6).
- `commands/curate.md` — `/kunskap:curate <vault-path>` slash command surface.
- `bin/kunskap` adds `curate` (headless agent spawn via `claude --plugin-dir`), `link-stubs` (resolved / alias / needs-stub / orphan classification), and `audit-coverage` (silent-drops + broken-provenance) subcommands.
- Fixture-based contract test suite at `tests/contract/`:
  - `static-prompt.bats` — asserts each §Curator contract MUST/MUST-NOT clause is encoded in the agent prompt; catches prompt drift in CI.
  - `cli-surface.bats` — exercises the new CLI subcommands against a hand-crafted fixture vault at `tests/fixtures/curator-vault/`.
  - `behavioral.bats` — gated on `KUNSKAP_LIVE_TESTS=1`; runs the actual curator and asserts end-to-end outcomes.
- CI: `.github/workflows/p1.yml` runs the contract suite alongside P0's `p0.yml`.

Risks #3 (hand-edit overwrite) and #9 (curator contract testability) are now load-bearing-tested.

## v0.0.1 — 2026-05-04 — P0 scaffold

- Plugin manifest at `.claude-plugin/plugin.json`
- `bin/kunskap` with `version`, `config user`, `config show`, `whoami` subcommands (per design §Q5)
- Stub `skills/kunskap-vault/SKILL.md` and `commands/learn.md` (real bodies in P1/P2)
- README + LICENSE (MIT)
- CI: shellcheck on `bin/kunskap`, `plugin.json` parse + required-field check, `bin/kunskap` smoke tests

Tracking: design doc at [`docs/kunskap-design.md`](docs/kunskap-design.md). Phased rollout P0 → P6.
