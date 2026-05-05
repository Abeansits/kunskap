---
description: Enable / disable / check Kunskap on the current project, pointing it at a vault.
argument-hint: enable [--vault <abs-path>] | disable | status
allowed-tools: Bash
---

Run `kunskap learn $ARGUMENTS` from the project working directory and surface its output verbatim.

Pre-flight (do these first, fail fast):
- If `$ARGUMENTS` is empty, stop and print: "Usage: /kunskap:learn enable [--vault <abs-path>] | disable | status".
- Pass through to `bin/kunskap learn` so behaviour stays identical to the CLI invocation. The CLI owns validation, the confirmation prompt (Risk #7 mitigation), and the marker schema. Do not duplicate that logic here.

After the CLI returns: for `status`, surface the structured output as-is, and if it warns about >30d staleness or identity-not-set, repeat the warning at the end so the user sees it.

Note: `enable` requires interactive confirmation unless `KUNSKAP_AUTO_CONFIRM=1` is set in the environment (the CLI handles this). The confirmation is the privacy primitive (design Risk #7 — vault-leak between projects). Do NOT auto-confirm on the user's behalf.
