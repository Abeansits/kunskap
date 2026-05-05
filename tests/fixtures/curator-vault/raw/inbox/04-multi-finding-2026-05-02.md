---
type: learning
author: fixture@bats
created: 2026-05-02
---

# Multi-finding inbox file (three sub-findings, three topics)

## Sub-finding 1: bash-discipline addition

Confirms the `var=$(die …)` gotcha applies inside `function () { … }`
bodies too, not just at script top level. Lane 1 additive to
`wiki/learnings/bash-discipline.md`.

## Sub-finding 2: two-pass-codex-review timing

Pass 2 timing observation: when Pass 1's diff is large (≥500 lines),
Pass 2 latency goes up disproportionately. Lane 1 additive to
`wiki/learnings/two-pass-codex-review.md`.

## Sub-finding 3: a brand-new topic — flag-as-value silent corruption

Generalization of the P0 Pass-2 finding into a reusable pattern:
arg-count guards (`[[ $# -ge 2 ]]`) are insufficient — must also reject
`-`-prefixed values. This is a NEW article, no existing topic.
