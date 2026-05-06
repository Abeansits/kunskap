---
description: Guided onboarding — wires identity, vault, project marker, and (optionally) multiplayer roles in one conversation.
argument-hint: [vault-path-or-keyword] (optional — interactive if omitted)
allowed-tools: Bash, Read
---

You are running guided Kunskap onboarding. The user just typed `/kunskap:setup` (optionally with a vault path or keyword as `$ARGUMENTS`). Your job: turn what was 5–8 commands across CLI + slash + manual TOML editing into one short conversation that ends with a working vault + project marker.

The conversation is yours. The side effects are the CLI's. Compose `bin/kunskap setup` (and only that — don't write files directly, don't reimplement marker writing, don't hand-edit roles.toml). The CLI verb already enforces all the guards: identity validation, Risk #7 confirmation, --init / not-init mode checks, multiplayer roles.toml mutation, the CLAUDE.md managed-block injection.

# Pre-flight (do these FIRST, before asking anything)

Run these checks in parallel (one tool call per item; surface results inline). They tell you which conversation branch to take.

1. **Is the CLI on PATH?** `command -v kunskap || echo MISSING`. If `MISSING`, stop and print: *"Kunskap CLI not found on PATH. Did `/reload-plugins` run after `/plugin install`? Try restarting Claude Code, then re-run /kunskap:setup."*
2. **Is identity already set?** `kunskap whoami --quiet 2>/dev/null && echo YES || echo NO`. Capture the slug+host if YES.
3. **Is this project already enabled?** `test -f .claude/kunskap.json && echo YES || echo NO`. If YES, capture the marker contents with `cat .claude/kunskap.json`.
4. **Was a vault path given as `$ARGUMENTS`?** If non-empty AND it's an existing directory with `_meta/kunskap.toml`, capture as the vault to bind to.

Compose your branch from the four signals.

# Branches

## Branch C — project already enabled

The marker exists. Read it. Print:

```
This project is already kunskap-enabled:
  vault:    <vault from marker>
  enabled:  <confirmed_at from marker>
  identity: <kunskap whoami output>

What do you want?
  1. Re-confirm setup (refresh confirmed_at; no other changes)
  2. Change vault (disable + enable elsewhere)
  3. Disable kunskap on this project (remove marker + CLAUDE.md block)
  4. Cancel
```

On choice:
- **1** → run `kunskap setup --vault <existing-vault> --yes` (re-confirms the binding; idempotent — the managed block is replaced in place per v1.1).
- **2** → run `kunskap learn disable`, then continue into Branch B with the new vault path.
- **3** → run `kunskap learn disable` and stop.
- **4** → say "cancelled" and stop.

## Branch A — fresh user (no identity, no marker)

Print:

```
🧠 Kunskap setup — let's get you wired in. Three questions:

1. Identity (how the vault knows who you are on this machine).
   I'll suggest:
     name = <whoami output>            # lowercase slug; role-check key
     host = <hostname -s output>       # explicit, so machine renames don't break role checks
   Reply "ok" to take both, or "name=<slug> host=<host>" to override.

2. Vault path (the knowledge-base directory).
   - Bind to an existing kunskap vault?       reply: "use <abs-path>"
   - Bootstrap a new vault?                   reply: "init <abs-path>"
   - Use the default location for new vault?  reply: "default" (= ~/Projects/<basename(cwd)>-vault)

3. Solo or multiplayer?
   - Solo (just you):       I'll leave roles at TBD.
   - Multiplayer (team):    I'll set you as curator + linter primary on this machine. You can hand off later via `kunskap config user` and a roles.toml edit.
```

Suggest defaults aggressively. Don't make the user type a slug if `whoami` + `hostname -s` is fine. **Note that `whoami` (the shell command) returns the OS username, not a kunskap slug** — slugify it: lowercase, replace any non-`[a-z0-9._-]` with `-`, collapse runs.

Recognized vocabulary across the three questions: `ok` / `default` / `keep` / blank-line / Enter all mean "take the suggested default"; `use <path>` binds an existing vault; `init <path>` bootstraps a new one; `solo` and `multiplayer` answer question 3. If the user replies with something off-grammar (a typo, a partial answer, a question), reprint the relevant prompt once with the same options; after a second unrecognized reply, default to the safest choice (`keep` for identity, `solo` for question 3) and say so before continuing.

After you have all three answers, before running anything, **show what will run** and ask one final "proceed?":

```
I'll run:
  kunskap setup --name <slug> --host <host> --vault <vault> [--init] [--multiplayer] --yes
Proceed? (y/n)
```

On `y`, run that exact command. **Print the CLI output verbatim** — don't paraphrase. The CLI's "STATUS / VAULT / IDENTITY / SHARED / ROLE-CHECK / CONFIRMED / INBOX" panel is the verification surface; the user expects to see it.

## Branch B — existing identity, no project marker

Skip the identity question. Print:

```
Using existing identity <slug>@<host> from ~/.config/kunskap/identity.toml.
Change? (no/Enter/"keep" = continue with this identity; "change" = re-enter)
```

- **"no" / "keep" / Enter / "ok" / blank** → continue with the existing identity. Compose `kunskap setup --vault <vault> [--init] [--multiplayer] --yes` (no `--name`/`--host`; the CLI reuses what's on disk).
- **"change" / "yes"** → ask Branch A's identity question (with the same `whoami` + `hostname -s` defaults), capture `name=<slug>` and `host=<host>`, and compose `kunskap setup --name <slug> --host <host> --vault <vault> [--init] [--multiplayer] --yes`. The `--yes` is required here because the CLI refuses to overwrite an existing identity without it.
- **Anything else (typo, partial answer)** → reprint the prompt once with the same options. After two unrecognized replies, default to "keep" and explicitly say so before continuing.

Then ask the vault question and the multiplayer question (same as Branch A questions 2 + 3).

# After the CLI returns

End with three concrete next-action suggestions. Tailor to what you just did:

```
✅ Setup complete. Try this:
   - Drop a learning to <vault>/raw/inbox/learning-<slug>-<YYYY-MM-DD>.md
     (the LAUNCH_FOOTER conventions are in your CLAUDE.md — see the managed block)
   - Search prior art: /kunskap:recall <query>
   - Manually flush captures: /kunskap:sync
```

# Conversation principles (apply throughout)

- **Suggest defaults aggressively.** Most users want the obvious answer; don't make them type it.
- **Show what will run before running it.** "I'll execute X" is the contract; surprise side effects break trust.
- **Print CLI output verbatim** when you call `kunskap setup` — the user needs the actual STATUS panel, not a summary.
- **Confirm before destructive operations.** Overwriting an existing identity, re-enabling on a different vault, disabling — all require an explicit y/n.
- **--yes is opt-in only.** Pass it to `kunskap setup` after the user confirms in conversation; never bypass the CLI's own Risk #7 prompt without an explicit user-side y.
- **Stay in budget.** Aim for ≤10 turns end-to-end. Each branch above completes in 3–5 user replies.

# Out of scope for this slash command

- `/plugin marketplace add` and `/plugin install` are upstream Claude Code commands; if pre-flight check 1 fails, refer the user to those — don't try to drive them.
- Repo migration / vault import (existing non-kunskap markdown notes) — separate feature.
- Multi-vault support (one project pointing at >1 vault) — Risk #7 explicitly forbids.
