---
description: Triage drafts the curator routed to wiki/_drafts/. List / show / approve / reject / defer.
argument-hint: list | show <id> | approve <id> [--into <slug>] | reject <id> --reason "<why>" | defer <id>
allowed-tools: Bash
---

Run `kunskap drafts $ARGUMENTS` from the project working directory and surface its output verbatim.

Pre-flight (do these first, fail fast):
- If `$ARGUMENTS` is empty, default to `list`.
- Pass through to `bin/kunskap drafts` so behaviour stays identical to the CLI invocation. The CLI owns vault resolution (`--vault` flag → project marker fallback), id-or-slug resolution, the `--reason` requirement on reject, and the per-action git commit. Do not duplicate that logic here.

Notes:
- `approve` and `reject` perform `git add -A` + a single commit inside the vault. If the vault has no committer configured (e.g. fresh `kunskap init`), the CLI falls back to a `kunskap@local` identity for that one commit. Do not auto-`git push`; let the SessionEnd hook (or the user) handle pushing.
- `reject` without `--reason` is rejected by the CLI — that's intentional (rejection without a reason loses the context that future humans need).
- `defer` stamps `deferred_at:` and leaves the file in `_drafts/`. The linter's weekly run (P4) flags drafts deferred ≥14 days.
- Drafts naming convention written by the curator: `_drafts/<topic-slug>--<iso-date>.md` (per design §Open decisions #5).
