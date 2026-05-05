---
type: learning
author: fixture@bats
created: 2026-05-02
suggested_topic: bash-discipline
---

# Bash assignment-substitution: extra confirmation case

The existing `wiki/learnings/bash-discipline.md` topic article documents the
`var=$(die …)` exit-suppression gotcha. This inbox note is a Lane 1 additive
finding: confirms the same failure mode reproduces under `bash 5.2.21` (the
prior article only cited `5.2.15`). Bump `source_count`; add this filename
to `sources:` frontmatter; one new sentence in the body noting the 5.2.21
confirmation. No claim is being changed — this is purely additive.
