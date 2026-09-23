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
| P0-3 arcana-devs host Jev | **pass** for install; routing **not_measured** | `datarim_enabled: false`; 12 Orca hooks preserved, 0 lost; floor 15/15; `hook_delivery` written; key still empty |
| P0-4 DEV-AI → merged sha | **pass** | 18 foreign hooks preserved, 0 lost; `doctor` clean; API `ok: true`, `jev-1.13.0`, 314 ms |
| P1-5 component routing | **pass** | see below |
| P1-6 session handoff | **pass** | `DEV-AI-SESSION-HANDOFF.md`, commands dry-run before publication |
| P2-7 repository docs | **pass** | new `jev-without-datarim.md`; tutorial now covers both Codex gates and where the key goes under `host_jev`; doc gates green |
| P2-8 site docs | **pass** | published to datarim.club; live pages verified in en and ru |
| P3-9 Codex research | **pass** (trust model corrected twice — see P3-9 below) | `--dangerously-bypass-hook-trust` measured working on 0.155.1; trust is a hash over the command, so the installer registers a stable command |
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

### Mac, proven on the live session that did this work

The strongest evidence available, because it needed no probe: the Mac's own
ledger recorded 171 `hook_delivery` events carrying
`session_id: faa6dc38-de5f-4db2-9b7b-8439929b388a` — this conversation — with
`advice_emitted: false`. The hook at `a95c8d7` is processing real tool calls
every few seconds, and declining to advise only because the key file is empty.

One instrument note: `find -newermt "-20 minutes"` returns nothing on macOS,
which first read as "the Mac hook is dead". It was writing that same minute.
The honest query on this platform is `stat -f "%m %N"` sorted by time.

### arcana-devs, what is proven and what waits on the key

Proven without a key: the hooks are registered (3 Jev entries beside the 12
Orca ones), the floor is correct in both directions (15/15), and the hook path
executes and fails open exactly as designed — a prompt returned in 0.1 s with
no output, rc 0, no broken session, and a `hook_delivery` record written to the
ledger.

Waiting on the operator: `key_ready` is false because the key file is the
protected empty placeholder. Until it is filled, `route` events cannot be
produced there, so the end-to-end routing criterion for P0-3 stands at
**not_measured** — not pass, not fail.

### Safety floor, verified on both newly-installed machines

15 commands through the real hook on arcana-devs and DEV-AI, 15/15 correct:
blocked `dd`/`mkfs` to a block device, `rm -rf /`, `/*`, and the spelling
variants `-fr`, `-r -f`, `~`, `$HOME`, plus `git push --force`; allowed
ordinary `dd`, `mkfs` to an image, `rm -rf ./build`, and — the discriminating
case — `git push --force-with-lease`, which a substring match would wrongly
block.

A fork bomb is **not** blocked, and that is correct: the floor's own docstring
scopes it to "catastrophic-and-irreversible" commands, leaving graded risk to
the advisory layer. My first probe listed it as a required block and reported a
breach; the probe's expectation was wrong, not the floor.

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
measured round trip was 0.5–0.6 s, but a slow network silently degrades to
tier-only advice rather than failing loudly.

And the cost, measured properly on three prompts of different sizes, three runs
each on DEV-AI:

| prompt | median latency | routing cost |
|---|---|---|
| "Refactor the payment module and add unit tests" | 0.51 s | 3417 in / 789 out |
| "Fix a typo in the README" | 0.54 s | 2957 in / 691 out |
| "Design a migration plan … across three regions" | 0.52 s | 3380 in / 812 out |

**Correction.** An earlier entry here put the cost at 281 in / 20 out. That
figure came from `doctor --api`, whose probe is a trivial one-question call —
not a routing request with the project catalogue attached. The real cost is an
order of magnitude higher, and roughly flat across prompt sizes because the
catalogue dominates the input.

So the token saving remains **not_measured**, now with the bar stated: the
components Jev names must save more than ~3400 input tokens per prompt to pay
for themselves. Plausible when it loads four relevant skills instead of the
agent reading a dozen, but plausible is not measured, and proving it needs two
sessions on the same task with and without the advice.

### P3-9, measured correction

An earlier revision of the how-to, the docstring, and my own report to the
operator all asserted that Codex re-arms gate 2 after every upgrade because
trust is keyed to the command string. **Both halves are false.** Two adjacent
slots holding entirely different commands carry the identical `trusted_hash`,
and after `91846a1 → a95c8d7` `codex exec` ran `UserPromptSubmit` with no
prompt. Fixed in PR #421, which also fixes the check that reported `trusted`
for a substituted command.

### P3-9, second correction — the first one was wrong

The correction above is itself wrong, and so were PRs #421 and #423 built on it.
The Codex source settles it (`codex-rs/hooks/src/engine/discovery.rs`): a user
hook runs only while its state block's `trusted_hash` equals `hook_hash` of the
hook as it stands now, and that hash covers the **command string**. A changed
command is `Modified` and skipped.

What misled the earlier measurements:

- **"Same hash in two slots."** Not re-measured, and the hash formula makes it
  impossible for two different commands on the same event; the observation was
  most likely two lines read from different blocks.
- **"`codex exec` ran `UserPromptSubmit` after an upgrade."** It did — but the
  run also carries Orca's and the hookify plugin's `UserPromptSubmit` hooks, and
  the count of `hook:` lines was read as proof about Jev's. Plugin hooks are keyed
  by plugin id, not by the `hooks.json` path, so they also survived the isolated
  `CODEX_HOME` experiment that #423 relied on.
- **`enabled = true`.** Present on some blocks (DEV-AI 5 of 14), absent on others;
  Codex's TUI trust writes only `trusted_hash`. It never decided trust.

How it was proved this time, with the ledger as the witness rather than the
count of `hook:` lines:

| isolated copy of the Mac's Codex home, keys rewritten to the copy's path | `UserPromptSubmit` hooks run | Jev ledger events |
|---|---|---|
| as installed after the `791dfba` upgrade | 2 | **0** |
| Jev slots' `trusted_hash` recomputed with the reproduced formula | 3 | **2** |
| every state block removed | 0 | 0 |

and the reproduced formula matches, byte for byte, hashes Codex itself wrote
after a TUI "Trust all" on a throwaway home (one hook with a matcher, one
without).

Consequence in the field: the `11841679 → 791dfba` upgrade stopped Jev's Codex
hooks on all three hosts, and `doctor`, reading presence, said `trusted`.

Fix: the host installer now registers a stable command
(`~/.local/share/jev/bin/jev-hook`) that resolves the active release, so the hash
no longer moves on upgrade; `doctor` recomputes Codex's hash and reports
`trusted` / `modified` / `untrusted` / `disabled` per hook. The witness file and
`slot_reused` are removed — with the real comparison there is nothing for them
to stand in for.

## Measured starting state (2026-09-23, before any change)

| Machine | User | Work dir | Host Jev runtime | Jev hooks (Claude) | Codex hooks | Datarim |
|---|---|---|---|---|---|---|
| Mac | `ug` | many projects | `658fa20` (stale) | **yes** | file present | per-project, opt-in |
| DEV-AI (`aether`) | `aether` | `~/code/aether/local-env` | `91846a1` | **yes** | file present, `trusted` | installed, `host_jev: true` |
| arcana-devs | `dev` | `~/arcanada` | **none** | **none** (only Orca) | present, not Jev | not used, by operator decision |

The arcana-devs gap is the largest and is P0. Mac being two releases behind is
why `codex_hook_trust` is absent there — the field ships in `91846a1`.

### P2-8, published — and a bigger problem than the missing Jev section

The site's getting-started page taught `./install.sh --with-claude` and
symlinks into `~/.claude/`. Those flags no longer exist: the installer became
project-local and requires `--project`, so **every new user following the site
hit an argument error on their first command**. The symlink/copy mode cards,
the topology-aware `update.sh` line and the `~/.claude/local/` overlay note
described the same retired model.

Corrected against the installer's own `--help`, and the missing Jev section
added: what the advice is and is not, where the key goes and why not to paste
it through a shell, `doctor` with and without `--api`, `off`/`on`, the floor
surviving `jev off`, and both Codex trust gates.

Verified before publishing: `php -l` clean, site contract PASS (528 routes),
and both language routes rendered locally. Verified after: the deploy workflow
succeeded and <https://datarim.club/en/getting-started> and `/ru/` both serve
the new content with no `--with-claude` or `--copy` remaining.

## After #421 landed: the fix verified on the upgrade it was built for

All three machines moved to `1184167`. On DEV-AI the upgrade exercised exactly
the case `slot_reused` exists for, and it behaved correctly: with the witness
pointing at the previous release's commands, the **first** `doctor` reported
`slot_reused: [PostToolUse, PreToolUse, UserPromptSubmit]`, then recorded the
new commands, so later runs read clean. `codex exec` afterwards ran
`SessionStart` and `UserPromptSubmit` with no prompt.

I briefly misread this as the old bug returning, because I read the witness
file *after* a `doctor` run had already updated it — the second state, not the
first. The isolated test (stale witness → single call) settled it.

**Known limitation, stated rather than hidden.** The flag is one-shot by
construction: it fires on the first run after the commands change and is gone
from every run after. Someone who does not look at that first run will not see
it. Making it sticky would need a separate acknowledged/unacknowledged state,
which is more machinery than the signal currently justifies.

## Known red that is not ours

`shellcheck-extracted` fails on `skills/session-handoff-writer/SKILL.md`: the
documented invocation contains the placeholders `<framework-repo>` and
`<base>..HEAD`, which shellcheck reads as competing redirections (SC2261). It
predates this work (`490b2bc`), no SKILL.md is touched by these branches, and
the check is neither required nor blocking (`continue-on-error`). Recorded
rather than dismissed: a red that is explained is not the same as a red that is
ignored, and the next person to see it should not have to re-derive this.

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

### Cursor, prepared and verified as prepared

Measured on Mac and DEV-AI: 3 Jev hooks each at `a95c8d7`
(`beforeShellExecution`, `beforeSubmitPrompt`, `postToolUse`), with 9 foreign
Cursor hooks preserved on both. So "prepared" is a measured claim, not an
intention — what remains untested is whether routing behaves correctly in a
live Cursor session, which needs the lapsed subscription.

Instrument note: Cursor nests hooks directly under the event name, with no
inner `hooks` key like Claude and Codex. A counter written for the other two
formats reports **0 hooks on a working install**. First run of that counter
said exactly that, and the install was fine.

### Standing: Cursor
Prepared but `not_measured` — the subscription has lapsed. Documentation says
"prepared, untested", never "works". Revisit when the operator tests it.

## Reporting

Progress is reported against this file. An item is only `pass` when its
acceptance criteria have been measured, with the negative control where the
criterion is an absence.
