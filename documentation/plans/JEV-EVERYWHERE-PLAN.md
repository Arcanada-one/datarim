# Plan: Jev everywhere, documented, and provably useful beyond model switching

Operator directive, 2026-09-23. Ten requirements, ordered by the operator's own
priority: **hooks working on every machine comes first**, everything else after.

This file is the working plan, the acceptance criteria, and the dependency
graph. It is updated as work lands; each item carries a measured verdict
(`pass` / `fail` / `not_measured`), never an asserted one.

## Progress (2026-09-23)

| Item | Verdict | Evidence |
|---|---|---|
| P0-1 land PR #420 | **pass** | merged as `a95c8d7`; `main` carries `codex_hook_trust` and 37 Jev files |
| P0-2 Mac → merged sha | **pass** (key + Codex gate: operator) | launchers at `a95c8d7`; `doctor` reports the new field |
| P0-3 arcana-devs host Jev | **pass** (key + Codex gate: operator) | `datarim_enabled: false`; 12 Orca hooks preserved, 0 lost, other settings identical |
| P0-4 DEV-AI → merged sha | **pass** | 18 foreign hooks preserved, 0 lost; `doctor` clean; API `ok: true`, `jev-1.13.0`, 314 ms |
| P1-5 component routing | **pass** | see below |
| P1-6 session handoff | **pass** | `DEV-AI-SESSION-HANDOFF.md`, commands dry-run before publication |
| P2-7 repository docs | **pass** | new `jev-without-datarim.md`; doc gates green |
| P2-8 site docs | not started | operator decision on publishing path |
| P3-9 Codex research | **pass** | `--dangerously-bypass-hook-trust` measured working on 0.155.1 |
| P3-10 installer audit | **pass** | see below |

### P3-10, measured in scratch homes

- Refuses to install from a dirty checkout: *"Commit and verify the source
  revision before host installation"*. This is why the first audit run
  produced no output — the instrument was right and I was not.
- Permissions: key `0600` inside a `0700` directory; `config.json`,
  `installation.json`, `settings.json` all `0600`; the four launchers `0700`.
- Idempotent: a second run changed no existing file; the only new path was
  another timestamped backup.
- **An existing key is never overwritten** — a key written by hand survived a
  reinstall byte-for-byte, with its mode intact.
- **Foreign hooks survive** — a hand-added `/my/own/guard` entry was still
  present after reinstalling.
- Project install: 363 files, `host_jev: true`. Uninstall removed all of them,
  reported `keys_and_state: preserved`, deleted `.datarim-runtime` and the hook
  settings, and renamed the rest to `.datarim-uninstalled` rather than deleting
  it — recoverable by design, not a leftover.

### P3-9, the supported automation path

`codex exec --dangerously-bypass-hook-trust` works on codex-cli 0.155.1.
Measured with a fresh `CODEX_HOME` carrying the hooks but no trust records:
without the flag no hook ran and the run completed silently; with it,
`SessionStart` and `UserPromptSubmit` ran and the events reached the ledger.
Reported broken in TUI mode on 0.131–0.133; scope is one invocation, not the
machine.

### P1-5, measured

One prompt — *"Refactor the payment module, add unit tests, and review the diff
for security issues"* — through the real hook wrapper on DEV-AI, 0.6 s:

```
skills: security (0.95), verification-before-completion (0.92),
        adversarial-review (0.89), security-baseline (0.84)
agent:  reviewer (0.67, low confidence - advisory only)
command: dr-qa (0.44, low confidence - advisory only)
template: none
```

**Negative control**, same prompt, same machine, a directory with no Datarim
catalogue: the `Project catalog:` line is absent entirely and only tier advice
is returned. So the component advice is real and is driven by the catalogue,
not by the prompt text.

Two honest caveats. The wrapper gives the routing child **6 seconds**; the
measured round trip was 0.6 s, but a slow network silently degrades to
tier-only advice rather than failing loudly. And the token saving the operator
expects is **not_measured** — the advice costs 281 input / 20 output tokens per
prompt; whether the components it names save more than that has not been
measured and is not claimed.

### P3-9, measured correction

An earlier revision of the how-to, the docstring, and my own report to the
operator all asserted that Codex re-arms gate 2 after every upgrade because
trust is keyed to the command string. **Both halves are false.** Two adjacent
slots holding entirely different commands carry the identical `trusted_hash`,
and after `91846a1 → a95c8d7` `codex exec` ran `UserPromptSubmit` with no
prompt. Fixed in PR #421, which also fixes the check that reported `trusted`
for a substituted command.

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
