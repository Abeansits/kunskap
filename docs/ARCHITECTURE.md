# Kunskap — Architecture notes

Operational notes that complement [`kunskap-design.md`](kunskap-design.md). Smaller, faster-changing, implementation-shaped. The design doc is the contract; this file is the working set.

## TOML reader: documented constrained subset

`bin/kunskap` reads three TOML files: `~/.config/kunskap/identity.toml`, `<vault>/_meta/kunskap.toml`, and `<vault>/_meta/roles.toml`. All three are hand-edited, small, and read with the same minimal awk parser (`read_toml_field`, `read_toml_field "$file" <section> <field>`). The parser is a documented **constrained subset** of TOML; out-of-subset input must either be rejected by review (vault config files are PR-reviewed) or surfaced via a CI fuzz test.

**Supported (the subset)**:

- One-level table headers: `[user]`, `[vault]`, `[wiki]`, `[roles.curator]`, `[roles.linter]`. The header line is the literal table name in `[ ]`; whitespace around the brackets is not allowed. Header dots (`roles.curator`) are part of the literal section name; the parser does not split them into nested objects.
- Single-line key-value assignments: `<bare-key> = <value>`.
- Bare keys: `[A-Za-z_][A-Za-z0-9_-]*`. Quoted keys are not supported.
- String values: `"value"` (double-quoted, no escape sequences). Unquoted scalars (`true`, `false`, integers) are read literally.
- End-of-line `# ...` comments are stripped from values.

**Out-of-subset (parser will silently mis-read or return empty)**:

- Multi-line strings (`"""..."""`).
- String escapes (`"a\nb"` returns the literal `a\nb`).
- Inline tables (`{a = 1, b = 2}`).
- Arrays (`[1, 2, 3]`).
- Nested tables expressed via dotted-key assignment (`a.b.c = 1`).
- Whitespace inside table headers.
- Multiple values per line.

**Why a constrained subset (not a real TOML library)**:

- All three files are hand-edited and small (<20 lines). Review catches subset violations.
- `~/.config/kunskap/identity.toml` is written by `kunskap config user`, in the subset by construction.
- `_meta/kunskap.toml` and `_meta/roles.toml` are scaffolded by `kunskap init` from `templates/vault-init/`, in the subset by construction. Hand edits are the only way to escape the subset.
- Adding a real TOML parser pulls in either `tomlq` (extra dep, not on stock macOS / Ubuntu) or `python -c "import tomllib"` (Python 3.11+; awkward shell-out boundary). Neither pays for itself at this size.
- A future P6+ may swap to a real parser if the subset becomes a friction point. The CI fuzz test guards the swap by failing loudly the moment a vault file leaves the subset.

The subset is enforced by `tests/contract/toml-fuzz.bats`: a battery of out-of-subset inputs are passed through the parser, and each must either return cleanly (the field is unset/empty — fail-soft) or return the expected string. The test never asserts a specific mis-read; it asserts the parser doesn't crash and that subset-conforming inputs round-trip correctly.

## CWD-scoped sandbox for headless agents

Per the P4 vault learning §2: `claude --plugin-dir <repo> -p "<directive>"` sandboxes the agent's filesystem reads to the spawning process's CWD, NOT to `--plugin-dir` and NOT to the agent's `$ARGUMENTS`. `bin/kunskap curate` and `bin/kunskap lint` therefore `cd "$vault"` before spawning AND pass `--add-dir "$vault"` (belt-and-suspenders — `--add-dir` extends sandbox access in Claude Code 1.x). Without this, running `kunskap curate --vault X` from any directory other than `X` produces `Read`-blocked agent runs and `[DRIFT]` self-check failures — fixed in P5.

## Run-record file: `_meta/last-run.json`

Two writers, two sections, never clobber:

```json
{
  "curator": {
    "ran_at": "<iso-8601 UTC>",
    "by": "<name>@<host>",
    "inbox_processed": <N>,
    "articles_written": <M>,
    "drafts_routed": <K>,
    "head_before": "<git oid>",
    "head_after": "<git oid>",
    "forced": <bool>
  },
  "linter": {
    "ran_at": "<iso-8601 UTC>",
    "by": "<name>@<host>",
    "findings_count": <N>,
    "forced": <bool>
  }
}
```

Both agents merge their section via jq, preserving the other side. The curator agent owns its block (it has Write + Bash and writes per-article anyway); the linter agent owns its block (the SOLE whitelisted write — see `agents/linter.md` MUST 8 + MUST 9, and `bin/kunskap lint`'s post-run path-by-path whitelist enforcement). The `forced` field is the audit trail for `--force` overrides of the role check.
