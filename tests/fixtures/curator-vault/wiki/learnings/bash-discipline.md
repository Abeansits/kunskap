---
type: learning
area: bash / cli scaffolding
tags: [bash, set-e, gotcha]
created: 2026-04-15
last_curated: 2026-04-30
source_count: 1
sources:
  - Archives/processed-inbox/learning-bash-discipline-2026-04-30.md
---

# Bash discipline: assignment-substitution under `set -e`

A failing command substitution inside a variable assignment does not
trigger `set -e`. Reproduced under bash 5.2.15.

## Sources

### learning-bash-discipline-2026-04-30.md

> The pattern `host="$(take_value --host …)"` swallows the subshell exit
> even with `set -euo pipefail`. Restructure to call the validator outside
> command substitution.

Original at Archives/processed-inbox/learning-bash-discipline-2026-04-30.md
