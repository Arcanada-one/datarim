---
task_id: TUNE-0521
artifact: task-description
schema_version: 1
created: 2026-07-29
complexity: L1
status: completed
---

# TUNE-0521 — Verify immutability skill file existence claim

## Claim under investigation

The TUNE-0517 audit of MUST/MANDATORY/REQUIRED declarations in `commands/`
and `agents/` produced follow-up tasks TUNE-0519..0527. TUNE-0521 claims:

> `$HOME/.claude/skills/immutability/SKILL.md` does not exist while 7 files
> cite it by absolute path.

## Re-derivation — evidence

### 1. File existence on DEVS (this machine)

```
$ ls -la /home/dev/.claude/skills/immutability/SKILL.md
-rw-r--r-- 1 root root 14327 Jul 29 09:49 /home/dev/.claude/skills/immutability/SKILL.md
```

The symlink chain: `/home/dev/.claude/skills` → `/opt/datarim/skills`.
The file at `/opt/datarim/skills/immutability/SKILL.md` (14327 bytes) is
accessible via the symlink path.

### 2. Canonical source in the repo

```
$ ls -la skills/immutability/SKILL.md
-rw-rw-r-- 1 dev dev 14327 Jul 29 00:06 skills/immutability/SKILL.md
```

The canonical file exists in the Datarim framework repo at commit `b8e26ac`
(HEAD of `main`).

### 3. Git history — the file was created by TUNE-0518

```
cfaf324 2026-07-29 feat(immutability): extend immutability + return-to-plan contract to all pipeline stages (TUNE-0518)
9c4a231 2026-07-28 feat(immutability): add shared immutability skill with per-stage fragments
```

The TUNE-0517 audit (completed 2026-07-26) identified the missing file as
a genuine gap. TUNE-0518 (2026-07-28–29) created the file and wired it into
all 7 pipeline commands + the architect agent. The audit's finding was
**correct at the time** but is **now stale** — the gap was closed by TUNE-0518
before TUNE-0521 was reached in the enforcement queue.

### 4. Seven files reference the immutability skill — all valid

| File | Line | Fragment loaded |
|------|------|-----------------|
| `commands/dr-prd.md` | 46 | `/dr-prd Rules` |
| `commands/dr-plan.md` | 35 | `/dr-plan Rules` |
| `commands/dr-design.md` | 16 | `/dr-design Rules` |
| `commands/dr-do.md` | 34 | `/dr-do Rules` |
| `commands/dr-qa.md` | 46 | `/dr-qa Rules` |
| `commands/dr-compliance.md` | 43 | `/dr-compliance Rules` |
| `agents/architect.md` | 27 | per-stage fragments |

All 7 references resolve correctly to the file that now exists.

### 5. Wiring tests — 25/25 pass on main

```
$ bats tests/immutability-wiring.bats
1..25
ok 1 immutability/SKILL.md exists
ok 2 immutability/SKILL.md contains Artefact Immutability Rule heading
...
ok 25 immutability/SKILL.md has Frontend-UI Rules fragment
Exit code: 0
```

The wiring bats tests (`tests/immutability-wiring.bats`) assert:
- The file exists (test 1)
- All 5 common rule headings present (tests 2–6)
- The routing table present (test 7)
- All 7 consuming files reference the skill (tests 8–14)
- All 6 per-stage fragments have correct headings (tests 19–25)
- The skill is NOT hardcoded in non-pipeline commands (test 16)
- tdd-discipline.md still has its canonical rules (tests 17–18)

### 6. Skill tool loadability

The skill loaded successfully via the Skill tool (`Skill({skill: "immutability"})`).
All per-stage fragments (`/dr-prd Rules`, `/dr-plan Rules`, `/dr-design Rules`,
`/dr-do Rules`, `/dr-qa Rules`, `/dr-compliance Rules`, `Frontend-UI Rules`)
are present and correctly named.

### 7. Operator cross-machine verification

Per the enforcement program brief, the operator verified the file exists on all
three machines:
- Mac: `/Users/ug/.claude/skills/immutability/SKILL.md` (14.0K)
- DEVS: `/home/dev/.claude/skills/immutability/SKILL.md` (14327 bytes)
- dev-ai: `/home/aether/.claude/skills/immutability/SKILL.md` (14327 bytes)

## Verdict

**STALE — closed as no-op.** The TUNE-0517 audit finding was correct when made
(2026-07-26), but the gap was closed by TUNE-0518 (commits `9c4a231` and
`cfaf324`, 2026-07-28–29) which created the immutability skill file and wired
it into all consuming commands and agents with 25 enforceable bats assertions.

No residual gap was found. The file exists on all three machines, the symlink
resolution chain is intact, the wiring tests pass, and the skill is loadable
by the runtime.

## Confidence in remaining TUNE-0517 audit findings

This finding was stale because TUNE-0518 closed the gap between the audit and
now. The same pattern could apply to other TUNE-0519..0527 items — a finding
that was accurate at audit time may have been closed by a parallel or
subsequent task.

**Recommendation:** Before implementing each remaining TUNE-0519..0527 task,
perform a 60-second re-derivation check (does the file/rule/gate already exist
on `main`?) to avoid implementing already-closed gaps. TUNE-0521's 25/25 bats
pass is strong evidence that the immutability contract is fully enforced,
not just documented.

## Decisions

- **Return-to-source: none.** No artefact change was needed. The investigation
  was read-only.
