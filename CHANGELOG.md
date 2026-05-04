# Changelog

## v0.0.1 — 2026-05-04 — P0 scaffold

- Plugin manifest at `.claude-plugin/plugin.json`
- `bin/kunskap` with `version`, `config user`, `config show`, `whoami` subcommands (per design §Q5)
- Stub `skills/kunskap-vault/SKILL.md` and `commands/learn.md` (real bodies in P1/P2)
- README + LICENSE (MIT)
- CI: shellcheck on `bin/kunskap`, `plugin.json` parse + required-field check, `bin/kunskap` smoke tests

Tracking: design doc at [`docs/kunskap-design.md`](docs/kunskap-design.md). Phased rollout P0 → P6.
