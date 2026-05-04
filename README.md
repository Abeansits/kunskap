# Kunskap

Knowledge-base plugin for Claude Code. Sessions write loose notes into an inbox; a librarian agent (later phases) compiles them into prose articles with `[[wikilinks]]` and `## Sources` provenance — Karpathy's compile model, distributed as a Claude Code Skill (omarsar0). Sibling to Vigil / Sigil / Ting.

## Status

**v0.0.1 — P0 scaffold only.** This release ships the plugin manifest, a stub skill, a stub `/kunskap:learn` command, and `bin/kunskap` with `version` / `config user` / `whoami`. Nothing else works yet.

The phased rollout (P0 → P6) is in [`docs/kunskap-design.md`](docs/kunskap-design.md). The MVP is P0 → P3.

## Install (manual; marketplace at P6)

The Anthropic plugin marketplace path lands at P6. Until then, manual install:

```bash
git clone https://github.com/Abeansits/kunskap ~/.claude/plugins/cache/local/kunskap
# inside Claude Code:
/plugin enable kunskap
```

For local plugin development:

```bash
claude --plugin-dir ~/Developer/kunskap
```

## Configure your identity (the one functional thing P0 ships)

Per machine, run once:

```bash
kunskap config user --name <yourslug> --email <you@example.com> --host <stable-host-name>
```

Writes `~/.config/kunskap/identity.toml`. Verify:

```bash
kunskap whoami
# → yourslug@stable-host-name
```

**Pass `--host` explicitly** rather than letting the CLI derive it from `hostname -s`. Hostnames mutate when machines get renamed, and a mismatched identity-string silently breaks the role checks that arrive at P5. The CLI prints a stderr warning when `--host` is omitted.

## Risks at v0.0.1

The full risk register lives in [`docs/kunskap-design.md`](docs/kunskap-design.md) §Risks. Two are operational at P0 and worth surfacing here:

**Risk #5 — Identity fragility.** The identity-string `<user>@<host>` doubles as the role-assignment key from P5 onward. `hostname -s` is volatile (machine renames, OS reinstalls), and a mismatched identity-string silently breaks role checks: a curator run intended for `sebastian@laptop` won't fire if your host is now reported as `Sebastians-MacBook-Pro`. P0's mitigation is the explicit `--host` flag with a stderr warning when it's omitted; later phases add a status cross-check and a linter health-check. Set `--host` explicitly and don't change it.

**Risk #8 — Vault privacy.** This plugin repo (`kunskap/`) and the eventual marketplace repo are content-free and can be public. The vault repo (`kunskap-research/`, P3) **must be private** — it carries research notes from Sebastian, Paul, Matt. Pushing the wrong remote leaks the wrong way around. Verify your vault remote before any `git push`; the P2 sync hook will refuse to push vaults whose `_meta/kunskap.toml` doesn't say `shared = true`.

## Roadmap

Full design: [`docs/kunskap-design.md`](docs/kunskap-design.md). Phased rollout summary:

| PR | Scope |
|---|---|
| **P0 (this release)** | Plugin manifest, `bin/kunskap` with `version` / `config user` / `whoami`, stub skill + command, CI. |
| **P1** | Curator agent + manual trigger + curator-contract tests. |
| **P2** | `/kunskap:learn enable\|disable\|status` + `SessionStart` / `SessionEnd` sync hooks. |
| **P3** | `kunskap init <vault-path>` + drafts surface (list/show/approve/reject/defer). MVP complete. |
| **P4** | Linter agent + health checks. |
| **P5** | Single-primary role assignment (`_meta/roles.toml`). |
| **P6** | Search (`kunskap recall`) + marketplace listing + polish. |

## License

MIT — see [`LICENSE`](LICENSE).
