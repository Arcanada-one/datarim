# Plan: Jev everywhere, documented, and provably useful beyond model switching

Operator directive, 2026-09-23. Ten requirements, ordered by the operator's own
priority: **hooks working on every machine comes first**, everything else after.

This file is the working plan, the acceptance criteria, and the dependency
graph. It is updated as work lands; each item carries a measured verdict
(`pass` / `fail` / `not_measured`), never an asserted one.

## Measured starting state (2026-09-23, before any change)

| Machine | User | Work dir | Host Jev runtime | Jev hooks (Claude) | Codex hooks | Datarim |
|---|---|---|---|---|---|---|
| Mac | `ug` | many projects | `658fa20` (stale) | **yes** | file present | per-project, opt-in |
| DEV-AI (`aether`) | `aether` | `~/code/aether/local-env` | `91846a1` | **yes** | file present, `trusted` | installed, `host_jev: true` |
| arcana-devs | `dev` | `~/arcanada` | **none** | **none** (only Orca) | present, not Jev | not used, by operator decision |

The arcana-devs gap is the largest and is P0. Mac being two releases behind is
why `codex_hook_trust` is absent there — the field ships in `91846a1`.

## Dependency graph

```
P0-1 land PR #420 on main ──┬── P0-2 Mac host runtime → main
                            ├── P0-3 arcana-devs host install (no Datarim)
                            └── P0-4 DEV-AI re-point to main build
                                        │
        ┌───────────────────────────────┴───────────────┐
        │                                               │
P1-5 prove component routing              P2-7 docs in repo ── P2-8 docs on site
   (skills/agents/commands/templates)                    │
        │                                               │
P1-6 session handoff for DEV-1962/1926    P3-9 Codex research + best practice
                                          P3-10 installer/permissions audit
```

Nothing downstream of P0-1 can be done honestly before it: every other machine
must install *the same* revision, and that revision is only canonical once it is
on `main`.

## Items

### P0-1 — Land PR #420 on `main`
`Arcanada-one/datarim` PR #420, `feat/project-scoped-jev-20260922` → `main`.
Measured `MERGEABLE` / `CLEAN`, 19/19 required checks green.

**Acceptance:** `main` contains `91846a1`'s tree; `gh pr view 420` reports
`MERGED`; `Projects/Datarim/code/datarim` on `main` contains `scripts/jev.py`
with `codex_hook_trust`.

**Operator gate:** merging is publishing. Held for explicit operator approval.

### P0-2 — Mac host runtime to the merged revision
Mac runs `658fa20`; `~/.claude/settings.json` points at it. Reinstall from the
merged `main` and re-accept the Codex trust gate (trust is keyed to
`releases/<sha>` in the command string).

**Acceptance:** `jev doctor` on Mac reports `source_sha` = merged sha, and
`codex_hook_trust.state` is `trusted` with `pending: []`. Negative control: the
field must be capable of reporting `untrusted` — verified by clearing `enabled`
for one hook and re-running, then restoring.

### P0-3 — arcana-devs: host Jev, no Datarim
Install the host runtime for user `dev`, clients `claude` and `codex`, merging
into the existing `~/.claude/settings.json` **without disturbing the Orca hooks
already there**. Datarim is explicitly not installed: the operator has retired it
for Arcanada; Muneral and Scrutator are used instead.

**Acceptance:** `jev doctor` as `dev` reports `datarim_enabled: false`,
`key_ready` true once the operator fills the key, hooks present; the pre-existing
Orca hook entries are byte-identical before and after; a real prompt in
`~/arcanada` produces a `route` event in the ledger.

**Constraint:** the operator's fleet sessions, worktrees and CI runners on this
host are untouchable.

### P0-4 — DEV-AI to the merged revision
Already at `91846a1`. Re-point to the merged sha and re-accept Codex gate 2.

**Acceptance:** as P0-2, plus the existing project runtime in
`~/code/aether/local-env` still resolves (`host_jev: true`).

### P1-5 — Prove routing covers component choice, not just model tier
The operator's claim to verify: Jev helps with **tool, skill, agent and template**
selection. Measured today: `hook_user_prompt.py` injects
`skills / agent / command / template` selections, but **only when a project
catalogue exists** (`if any(r.get('candidates', {}).values())`). Without Datarim
there are no candidates and only tier advice is injected — correct by design,
but undocumented and easy to read as "it doesn't work".

**Acceptance:** an end-to-end measurement on DEV-AI showing, from the ledger and
the injected context, a real prompt producing named skills with scores, a chosen
agent, command and template; plus a negative control in a catalogue-free project
showing tier-only advice; plus a token/latency measurement substantiating or
refuting the "saves tokens" claim. If the saving cannot be measured, it is
reported `not_measured` — not asserted.

### P1-6 — Handoff for the DEV-AI test sessions
The operator wants to resume `jev-DEV-1962` (Claude) and `jev-DEV-1926` (Codex)
by hand, through Jev.

**Acceptance:** a written handoff naming each session id, its client, its state,
the exact resume command through the Jev launcher, and what to expect; verified
by reading the session ids from the live processes, not from memory.

### P2-7 — Repository documentation
Install, enable, disable, key placement, running each client, verifying it works
— for four combinations: Datarim+Jev, Datarim alone, Jev alone, neither.

**Acceptance:** a reader who has never seen the project can go from clone to a
verified working install without asking a question; every command in the docs is
executed and its real output pasted; `check-orchestrate-docs.sh` and the doc-ref
checks stay green.

### P2-8 — Site documentation (datarim.club)
Same content, published.

**Acceptance:** the site's install/enable/disable/key/verify pages match the
repository; publishing goes through the sanctioned path, not a direct push.

### P3-9 — Codex: research current best practice
Two trust gates, `Active` counting installed rather than trusted, trust keyed to
the release path so every upgrade re-prompts. Research whether there is now a
supported non-interactive path, and whether the per-release re-prompt can be
avoided legitimately.

**Acceptance:** findings written down with sources and dates; if a better
mechanism exists it is implemented; if not, that is stated explicitly with the
evidence, and the manual steps are documented so no user is surprised.

### P3-10 — Installer, permissions and path audit
`install.sh`, `update.sh`, `project_install.py`, `jev_host_install.py`,
`activate.sh`, uninstall paths. Modes on key files (0600) and their parents,
refusal on protected directories, idempotent re-runs, correct behaviour when a
home already has foreign hooks.

**Acceptance:** each script exercised in a scratch HOME; permissions asserted by
measurement; a second run changes nothing; uninstall restores the prior state;
the existing protected-directory refusals still hold.

### Standing: Cursor
Prepared but `not_measured` — the subscription has lapsed. Documentation says
"prepared, untested", never "works". Revisit when the operator tests it.

## Reporting

Progress is reported against this file. An item is only `pass` when its
acceptance criteria have been measured, with the negative control where the
criterion is an absence.
