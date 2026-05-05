# Kunskap Vault — {{name}}

This is a Kunskap-managed knowledge vault. The contract:

- **You write to `raw/inbox/`** as `{type}-{slug}-{date}.md` (see `templates/inbox-note.md` in the plugin repo for the shape).
- **You don't edit `wiki/`** — the librarian (Curator + Linter) owns that. Read it freely; don't hand-edit.
- **Conflict-free by construction**: many writers to `inbox/`, single writer (the role-holding machine) to `wiki/`.

## To use this vault from Claude Code

    cd <any-project>
    /kunskap:learn enable --vault <path-to-this-vault>

Then sessions in that project will:
- pull the vault on session start (shared vaults only)
- get the kunskap-vault skill auto-loaded (vault-search-first discipline)
- commit + push your inbox capture on session end (shared vaults only)

## Roles

Roles are declared in `_meta/roles.toml`. P5 will enforce that only the
designated primary machine runs the curator / linter; until then they're
informational.

To trigger a curator run manually:

    /kunskap:curate <path-to-this-vault>

To triage drafts the curator routed to `wiki/_drafts/`:

    /kunskap:drafts list

## Privacy

If `shared = true` in `_meta/kunskap.toml`, this vault is intended for the team
sharing the configured git remote. **Don't push it to public remotes.** Don't
paste contents into public-AI surfaces. If `shared = false`, pushes are
disabled by the SessionEnd hook — it's a personal vault.
