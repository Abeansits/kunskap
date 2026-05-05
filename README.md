# Kunskap

Knowledge-base plugin for Claude Code. Sessions write loose notes into an inbox; a librarian agent (later phases) compiles them into prose articles with `[[wikilinks]]` and `## Sources` provenance — Karpathy's compile model, distributed as a Claude Code Skill (omarsar0). Sibling to Vigil / Sigil / Ting.

## Status

**v0.4.0 — P4 linter agent.** Adds `agents/linter.md` (read-only Karpathy "Linting" — drift across articles, stub-cluster suggestions, draft staleness, offline-machine arrivals per Risk #4, curator-idle, identity-mismatch), `commands/lint.md`, and `bin/kunskap lint [--vault <abs-path>] [--format text|json]`. The linter is forbidden from writing to the vault; the CLI verifies `git status --porcelain` snapshots are equal before/after the agent run. Exit codes: `0` = no findings, `1` = findings present, `2` = read-only invariant violation.

The phased rollout (P0 → P6) is in [`docs/kunskap-design.md`](docs/kunskap-design.md). The MVP is P0 → P3.

## Install (development; marketplace at P6)

The Anthropic plugin marketplace path lands at P6. Until then, the canonical
local-dev path:

```bash
git clone https://github.com/Abeansits/kunskap ~/Developer/kunskap
claude --plugin-dir ~/Developer/kunskap
```

`bin/kunskap` is on the Bash tool's PATH whenever the plugin is loaded.

## Configure your identity (the one functional thing P0 ships)

Per machine, run once:

```bash
kunskap config user --name <yourslug-lowercase> --email <you@example.com> --host <stable-host-name>
```

`--name` is lowercase-only to pre-empt `Paul`-vs-`paul` collisions in the P5 role check.

Writes `~/.config/kunskap/identity.toml`. Verify:

```bash
kunskap whoami
# → yourslug@stable-host-name
```

**Pass `--host` explicitly** rather than letting the CLI derive it from `hostname -s`. Hostnames mutate when machines get renamed, and a mismatched identity-string silently breaks the role checks that arrive at P5. The CLI prints a stderr warning when `--host` is omitted.

## Bootstrap a vault (P3)

```bash
# Solo vault (no remote, never pushes):
kunskap init ~/Developer/my-vault --name "My Vault"

# Shared vault (sets shared = true, adds origin):
kunskap init ~/Developer/team-vault --name "Team Vault" \
  --shared git@github.com:org/team-vault.git
```

`init` scaffolds the full vault layout, seeds neutral example notes (so a fresh vault passes `kunskap audit-coverage` and is immediately runnable by the curator), and prints a "next steps" panel. It does NOT auto-commit — review with `git status` before your seed commit. Re-running on an existing non-empty target requires `--force` (with interactive confirmation; pass `--yes` or set `KUNSKAP_AUTO_CONFIRM=1` in scripts).

After the curator routes drafts to `wiki/_drafts/`, triage them with:

```bash
/kunskap:drafts list
/kunskap:drafts show <id>
/kunskap:drafts approve <id> [--into <article-slug>]
/kunskap:drafts reject  <id> --reason "<why>"
/kunskap:drafts defer   <id>
```

Each action commits inside the vault. `reject` requires `--reason` — rejection without a reason loses the context that future humans need.

## Risks at v0.0.1

The full risk register lives in [`docs/kunskap-design.md`](docs/kunskap-design.md) §Risks. Two are operational at P0 and worth surfacing here:

**Risk #5 — Identity fragility.** The identity-string `<user>@<host>` doubles as the role-assignment key from P5 onward. `hostname -s` is volatile (machine renames, OS reinstalls), and a mismatched identity-string silently breaks role checks: a curator run intended for `sebastian@laptop` won't fire if your host is now reported as `Sebastians-MacBook-Pro`. P0 mitigates two ways: (1) the explicit `--host` flag with a stderr warning when it's omitted, and (2) `--name` is enforced lowercase-only so `Paul`/`paul` can't both end up in `roles.toml` after Sebastian, Paul, and Matt all configure independently. Later phases add a status cross-check and a linter health-check. Set `--host` explicitly and don't change it.

**Risk #8 — Vault privacy.** This plugin repo (`kunskap/`) and the eventual marketplace repo are content-free and can be public. The vault repo (`kunskap-research/`, P3) **must be private** — it carries research notes from Sebastian, Paul, Matt. Pushing the wrong remote leaks the wrong way around. Verify your vault remote before any `git push`; the P2 sync hook will refuse to push vaults whose `_meta/kunskap.toml` doesn't say `shared = true`.

## Roadmap

Full design: [`docs/kunskap-design.md`](docs/kunskap-design.md). Phased rollout summary:

| PR | Scope |
|---|---|
| **P0** | Plugin manifest, `bin/kunskap` with `version` / `config user` / `whoami`, stub skill + command, CI. |
| **P1** | Curator agent + manual trigger + curator-contract tests. |
| **P2** | `/kunskap:learn enable\|disable\|status` + `SessionStart` / `SessionEnd` sync hooks. |
| **P3** | `kunskap init <vault-path>` + drafts surface (list/show/approve/reject/defer). MVP complete. |
| **P4 (this release)** | Linter agent + health checks (drift, stub clusters, draft staleness, offline arrivals, curator-idle, identity-mismatch). Read-only contract. |
| **P5** | Single-primary role assignment (`_meta/roles.toml`). |
| **P6** | Search (`kunskap recall`) + marketplace listing + polish. |

## License

MIT — see [`LICENSE`](LICENSE).
