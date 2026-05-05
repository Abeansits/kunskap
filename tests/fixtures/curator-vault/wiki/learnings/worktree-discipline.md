---
type: learning
area: git / worktree
tags: [worktree, discipline, git]
created: 2026-04-01
last_curated: 2026-04-30
source_count: 1
sources:
  - Archives/processed-inbox/learning-worktree-discipline-2026-04-30.md
---

# Worktree discipline

Use git worktrees to keep parallel branches checkout-clean. One worktree
per long-running feature; never share a worktree across two features.

## Sources

### learning-worktree-discipline-2026-04-30.md

> Worktrees prevent the "stash → switch → restore" dance entirely. Cost
> is a few hundred MB of duplicated `.git/objects`; the tax is worth it
> for any branch that lives more than a day.

Original at Archives/processed-inbox/learning-worktree-discipline-2026-04-30.md

## Caveat for Sebastian's setup (HUMAN HAND-EDIT — DO NOT OVERWRITE)

Sebastian's machine has APFS with case-insensitivity flipped on, which
makes `git worktree add` fail silently when the new path differs only by
case from an existing one. Workaround: prefix worktree paths with the
date (`2026-05-02-feat-foo`) to guarantee uniqueness. This caveat is a
hand edit — it does NOT derive from any cited source, and the curator
must NOT overwrite it on the next pass.
