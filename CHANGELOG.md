# Changelog

## v0.1.0 — 2026-05-05 — P1 curator agent + manual trigger + tests

- `agents/curator.md` — curator agent encoding the design §Curator contract (Karpathy article-writing model, atomic per-article commits, hand-edit preservation per Risk #3, per-source `## Sources` footers, stub discovery recipe verbatim from v0 §6).
- `commands/curate.md` — `/kunskap:curate <vault-path>` slash command surface.
- `bin/kunskap` adds `curate` (headless agent spawn via `claude --plugin-dir`), `link-stubs` (resolved / alias / needs-stub / orphan classification), and `audit-coverage` (silent-drops + broken-provenance) subcommands.
- Fixture-based contract test suite at `tests/contract/`:
  - `static-prompt.bats` (29 tests) — asserts each §Curator contract MUST/MUST-NOT clause is encoded in the agent prompt; catches prompt drift in CI.
  - `cli-surface.bats` (24 tests) — exercises the new CLI subcommands against a hand-crafted fixture vault at `tests/fixtures/curator-vault/`.
  - `behavioral.bats` — gated on `KUNSKAP_LIVE_TESTS=1`; runs the actual curator and asserts end-to-end outcomes.
- CI: `.github/workflows/p1.yml` runs the contract suite alongside P0's `p0.yml`.

Risks #3 (hand-edit overwrite) and #9 (curator contract testability) are now load-bearing-tested. `bin/kunskap version` bumps to `0.1.0`.

## v0.0.1 — 2026-05-04 — P0 scaffold

- Plugin manifest at `.claude-plugin/plugin.json`
- `bin/kunskap` with `version`, `config user`, `config show`, `whoami` subcommands (per design §Q5)
- Stub `skills/kunskap-vault/SKILL.md` and `commands/learn.md` (real bodies in P1/P2)
- README + LICENSE (MIT)
- CI: shellcheck on `bin/kunskap`, `plugin.json` parse + required-field check, `bin/kunskap` smoke tests

Tracking: design doc at [`docs/kunskap-design.md`](docs/kunskap-design.md). Phased rollout P0 → P6.
