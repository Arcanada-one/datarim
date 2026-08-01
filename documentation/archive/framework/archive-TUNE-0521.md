---
id: TUNE-0521
title: Verify immutability skill file existence claim — closed as STALE
status: archived
completed_date: 2026-07-29
complexity: L1
type: framework
project: Datarim
related: ["TUNE-0517", "TUNE-0518"]
archive_doc: documentation/archive/framework/archive-TUNE-0521.md
verification_outcome:
  caught_by_verify: 0
  missed_by_verify: 0
  false_positive: 0
  n_a: true
  dogfood_window: "enforcement-program-2026-07"
---

# Archive: TUNE-0521 — Immutability skill file existence claim (STALE)

**Audited at commit:** `b8e26ac197a393d3a7e4a70e9d50cdd7b6211d55`

## Claim

The TUNE-0517 audit of MUST/MANDATORY/REQUIRED declarations in `commands/`
and `agents/` claimed:

> `$HOME/.claude/skills/immutability/SKILL.md` does not exist while 7 files
> cite it by absolute path.

## Finding

**STALE — closed as no-op.** The file exists, is wired, and is enforced.

The audit finding was correct when made (2026-07-26) but the gap was closed
by TUNE-0518 before TUNE-0521 was reached in the enforcement queue.

## Evidence

### File existence

The file exists at commit `b8e26ac` (`main`):

```
skills/immutability/SKILL.md — 14327 bytes, valid YAML frontmatter,
5 common rules, 7 per-stage fragments, routing table, integration section.
```

### Git provenance

The file was created by TUNE-0518:

```
9c4a231 2026-07-28 feat(immutability): add shared immutability skill with per-stage fragments
cfaf324 2026-07-29 feat(immutability): extend immutability + return-to-plan contract to all pipeline stages (TUNE-0518)
```

### Wiring tests — 25/25 pass

```
$ bats tests/immutability-wiring.bats
1..25
ok 1 immutability/SKILL.md exists
ok 2 immutability/SKILL.md contains Artefact Immutability Rule heading
ok 3 immutability/SKILL.md contains Return-to-Source Transition heading
ok 4 immutability/SKILL.md contains V-AC Parity Rule heading
ok 5 immutability/SKILL.md contains Non-Code Parity Rule heading
ok 6 immutability/SKILL.md contains Anti-Tautological Rule heading
ok 7 immutability/SKILL.md contains Return-to-Source routing table
ok 8 dr-prd command references immutability skill
ok 9 dr-plan command references immutability skill
ok 10 dr-design command references immutability skill
ok 11 dr-do command references immutability skill
ok 12 dr-qa command references immutability skill
ok 13 dr-compliance command references immutability skill
ok 14 architect agent references immutability skill
ok 15 frontend-ui skill references immutability Frontend-UI Rules
ok 16 immutability skill is NOT hardcoded in non-pipeline commands
ok 17 tdd-discipline.md still has Test Immutability Rule
ok 18 tdd-discipline.md still has Return-to-Plan Transition
ok 19 immutability/SKILL.md has dr-prd fragment with routing
ok 20 immutability/SKILL.md has dr-plan fragment with routing
ok 21 immutability/SKILL.md has dr-design fragment with routing
ok 22 immutability/SKILL.md has dr-do fragment with routing
ok 23 immutability/SKILL.md has dr-qa fragment with routing
ok 24 immutability/SKILL.md has dr-compliance fragment with routing
ok 25 immutability/SKILL.md has Frontend-UI Rules fragment
Exit code: 0
```

### Seven consuming files — all references valid

| File | Line | Reference |
|------|------|-----------|
| `commands/dr-prd.md` | 46 | `$HOME/.claude/skills/immutability/SKILL.md` — `/dr-prd Rules` |
| `commands/dr-plan.md` | 35 | `$HOME/.claude/skills/immutability/SKILL.md` — `/dr-plan Rules` |
| `commands/dr-design.md` | 16 | `$HOME/.claude/skills/immutability/SKILL.md` — `/dr-design Rules` |
| `commands/dr-do.md` | 34 | `$HOME/.claude/skills/immutability/SKILL.md` — `/dr-do Rules` |
| `commands/dr-qa.md` | 46 | `$HOME/.claude/skills/immutability/SKILL.md` — `/dr-qa Rules` |
| `commands/dr-compliance.md` | 43 | `$HOME/.claude/skills/immutability/SKILL.md` — `/dr-compliance Rules` |
| `agents/architect.md` | 27 | `$HOME/.claude/skills/immutability/SKILL.md` — per-stage fragments |

### Runtime symlink chain (DEVS)

```
/home/dev/.claude/skills → /opt/datarim/skills
/opt/datarim/skills/immutability/SKILL.md — 14327 bytes, plain file
```

### Operator cross-machine verification

Per the enforcement program brief, the file is present on all three machines:

| Machine | Path | Size |
|---------|------|------|
| Mac | `/.claude/skills/immutability/SKILL.md` | 14.0K |
| DEVS | `/home/dev/.claude/skills/immutability/SKILL.md` | 14327 bytes |
| dev-ai | `/home/aether/.claude/skills/immutability/SKILL.md` | 14327 bytes |

## Confidence in remaining TUNE-0517 audit findings

This is the first finding re-verified from the TUNE-0517 audit backlog
(TUNE-0519..0527). It was stale — the gap it described was already closed by
TUNE-0518. The same pattern could apply to other items in the queue: a
finding accurate at audit time may have been closed by a parallel or
subsequent task before the enforcement program reached it.

**For each remaining TUNE-0519..0527 task:** perform a 60-second
re-derivation check before implementation — does the file/rule/gate already
exist on `main`?

## Lessons learned

- TUNE-0518 not only created the file — it installed 25 enforceable bats
  assertions. That is the pattern the enforcement program requires: load path
  + gate, not prose.
- An audit finding that was correct when made can be stale by the time the
  follow-up task is picked up. This is not an audit failure; it is evidence
  that the framework is evolving faster than the enforcement queue.
- Checking file existence is a 5-second shell command. Doing it before
  writing code is always worth it.

## Operator handoff

Closed without code changes. The immutability contract is intact and
enforced. Proceed to TUNE-0519.
