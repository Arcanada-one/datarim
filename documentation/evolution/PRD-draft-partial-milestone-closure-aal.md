# PRD Draft — Partial Milestone Closure Pattern for the AAL Mandate

> **Status:** DRAFT — Class B prerequisite. This document is the PRD draft that
> the evolution Class A/B gate requires before the AAL Mandate amendment it
> proposes may be presented for approval and applied. It defines the contract;
> it does **not** itself amend the shipped mandate. Applying the amendment is a
> separate, sign-off-gated step (see § Rollout).
>
> **Deliverable scope of the spawning task:** this draft only. The mandate
> amendment under the framework `CLAUDE.md` § AAL is deferred pending Class B
> sign-off.

## 1. Problem

The AAL (Autonomous Agents Levels) Mandate models a component's autonomy
maturity with `current_aal` / `target_aal` frontmatter and a set of milestone
"weakest links" that must all close before the component earns an AAL bump. In
practice a milestone (M{N}) is frequently **not** closed by a single task: its
weakest links land across several child tasks over days or weeks. The mandate,
as written, has no vocabulary for a *partial* milestone closure. That produces
two failure modes:

- **Premature bump.** A child task that closes some — but not all — of a
  milestone's weakest links bumps `current_aal` because the milestone "feels
  done", overstating the component's real autonomy maturity.
- **Lost provenance.** When the closure is genuinely deferred, there is no
  structured record of *which* links closed, *which* remain, and *which* task
  owns the remainder — so the next agent re-derives it from prose or misses it.

A reference implementation already exists in the wild and worked well: a
multi-task epic tracked its M2 closure as an explicit "Partial M2 closure"
append-log entry with a per-link ✓-closed / ✗-deferred breakdown, an explicit
"AAL bump deferred" rationale, and a cross-link to the closing child task; the
bump only happened when the last weakest link shipped. This PRD generalises that
ad-hoc practice into a named, schema'd pattern.

## 2. Goals / Non-goals

**Goals**

- Define an append-log entry schema for partial and full milestone closure.
- Define parent/child responsibility for AAL tracking across a multi-task
  milestone.
- Define reopen-on-fallback semantics (a shipped link that later regresses).
- Keep the pattern runtime-agnostic and machine-greppable.

**Non-goals**

- No change to how AAL levels themselves are defined (L1..L5 semantics).
- No new command or gate script in this PRD (a follow-up may add a validator).
- No change to the frontmatter key names (`current_aal` / `target_aal`).

## 3. Proposed contract

### 3.1 Append-log entry schema

The parent task's init-task `## Append-log` (or the milestone-owning task
description's append-log) carries one entry per closure event.

**Heading format** (partial):

```
### <ISO-date> — Partial M{N} closure via {CHILD-ID} {short-desc}
```

**Heading format** (full — the entry that authorises the AAL bump):

```
### <ISO-date> — M{N} full closure via {CHILD-ID} — AAL L{X} reached
```

**Body — per-link status list.** One bullet per weakest link named in the
milestone, each stamped with a status word from the closed set:

| Status word | Meaning |
|-------------|---------|
| `✓ closed`  | The weakest link is shipped and verified. |
| `✗ deferred → {CHILD-ID}` | Not yet closed; the named child task owns it. |
| `✗ deferred → backlog:{ID}` | Not yet closed; spawned as a backlog item. |
| `⟲ reopened` | A previously `✓ closed` link regressed (see § 3.3). |

**Mandatory sub-lines** on a partial entry:

- `**AAL bump deferred:**` — one line stating that `current_aal` is held and
  naming the condition (which link, in which task) that will authorise the bump.
- `**Rationale:**` — one line stating why the shipped subset does not yet meet
  `target_aal` maturity (protects PRD integrity — the bump reflects real
  capability, not shipped convenience).

**Cross-link convention.** Every `✗ deferred → {CHILD-ID}` link MUST be mirrored
in the named child's init-task `## Append-log` (a back-reference to the parent
milestone and link), so the dependency is discoverable from either end.

### 3.2 Parent/child responsibility split

- **The parent task (or milestone-owning task) owns AAL tracking.** It holds the
  authoritative `current_aal` frontmatter and the closure append-log. Child
  tasks do not bump the parent's AAL.
- **A child task that closes one or more links** records its contribution in its
  own archive and appends a `Partial M{N} closure` entry to the parent's
  append-log (or requests the parent do so), flipping the relevant links to
  `✓ closed`.
- **The AAL bump frontmatter change is applied ONLY by the task that ships the
  LAST weakest link** — i.e. the child whose closure makes the per-link list
  all-`✓`. That task writes the full-closure heading and updates `current_aal`.

### 3.3 Reopen-on-fallback semantics

If a link recorded `✓ closed` later regresses (a revert, a discovered gap, a
dependency that fell away):

- Append a new closure entry flipping that link to `⟲ reopened` with a one-line
  cause and the task that will re-close it.
- If the milestone had already reached full closure and bumped AAL, the reopen
  entry MUST also **step `current_aal` back down** to the prior level in the
  owning task's frontmatter — an AAL level is a claim about present capability,
  not a historical high-water mark. The step-down is itself a closure event and
  follows the same schema.

## 4. Acceptance criteria (for the eventual amendment task)

- AC1 — The framework `CLAUDE.md` § AAL section (or a new § Partial Milestone
  Closure) documents the § 3.1 schema, § 3.2 split, and § 3.3 reopen rule.
- AC2 — The status-word set is a closed, enumerated set (no free-form status).
- AC3 — The reference-implementation epic is cited as the founding precedent.
- AC4 — A greppable example append-log block is shown verbatim.
- AC5 — (Optional, may spawn a child) a validator that checks: no `current_aal`
  bump in a task whose parent milestone append-log still carries a `✗ deferred`
  link.

## 5. Rollout

1. **Class B sign-off** on this draft (evolution gate).
2. Spawn the amendment task; apply the § 3 contract to the framework `CLAUDE.md`
   § AAL as a single reviewable edit.
3. (Optional) spawn the AC5 validator as a child L1/L2 task.

Until step 2 lands, teams SHOULD follow the reference-implementation practice
(explicit partial-closure append-log entries + deferred-bump rationale) by
convention; this draft is the specification they are converging on.
