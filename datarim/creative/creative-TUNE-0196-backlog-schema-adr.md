---
task_id: TUNE-0196
artifact: creative
captured_at: 2026-08-02
captured_by: /dr-design
agent: architect
status: decided
schema_version: 1
consilium: true
---

# TUNE-0196 · Backlog Follow-up Schema Decision

## Decision

The original A/B/C fork is **SUPERSEDED**. Preserve the current relaxed
`backlog.md` contract and do not change runtime behavior:

- a backlog item may keep a long, single-line inline description;
- a `tasks/{ID}-task-description.md` pointer is optional in `backlog.md`;
- the wider backlog status vocabulary and priorities P0-P4 remain accepted;
- `tasks.md` and `activeContext.md` remain strict thin indexes whose entries
  require a description pointer.

The shared strict-index regex retains `pending`, `blocked-pending`, and
`cancelled` as compatibility inputs for legacy and migration paths. Canonical
active-index writers emit `in_progress`, `blocked`, or `not_started`; backlog
intake and cancellation flows own the other statuses.

The framework must synchronize its shipped documentation and template to that
already-ratified distinction and add a falsifiable regression. TUNE-0196 is not
closed as option C: current authority deliberately chose a more permissive
backlog ledger after the original fork was filed.

## Authority and chronology

The 2026-05-12 TUNE-0194 archive left 42 paragraph-length follow-up bullets as
an open A/B/C operator decision and explicitly classified the cohort as “not a
framework defect.”

Commit `a0e7b136eb9d3979c1d23f205cfaaf7f0ae7574b` (merged PR #62,
2026-05-31) later resolved the same behavior on live evidence:

- `BACKLOG_ITEM_RE` made the pointer optional and accepted a nonempty inline
  description, wider statuses, optional bold priority/complexity, and P0-P4;
- `SCHEMA_BACKLOG_RE` mirrored the backlog behavior for the pre-archive gate;
- `/dr-doctor` routed `backlog.md` through the relaxed pattern while retaining
  `ONELINER_RE` for active indexes;
- the hotfix reduced the live workspace from 572 findings to zero, and the
  merged extraction preserved that deployed behavior.

Current `origin/main@f6e1845ae69fb874e72009c488fafca3f5f30df6` retains those
runtime rules, but the Datarim system skill, Doctor skill, and backlog template
still describe the older pointer-required 80-character schema. That is the
remaining defect.

## Consilium

This was a genuine design fork. Cursor Agent independently returned
`SUPERSEDED`; the orchestrating OpenAI model independently reached the same
verdict from the later commit and current source. Anthropic Claude could not
participate because its CLI reported a non-transient weekly subscription limit
until 2026-08-04 11:00 UTC; it was not retried and supplied no evidence.

## Rejected alternatives

### A — Split and truncate

Rejected. Automatic truncation discards operator-authored pending-work context
and contradicts the later field-proven rule. Description externalization may
still happen when a task enters the active workflow, but Doctor must not invent
that transition merely to normalize a backlog line.

### B — Informational finding

Rejected as current behavior. The later rule accepts the line as compliant;
emitting a finding would reintroduce noise for a shape the canonical regex
explicitly allows. A new measurable usability defect could justify a separate
advisory in the future.

### C — Explicit rejection

Rejected. Restoring a mandatory pointer would reverse a later deliberate
decision and reopen accepted downstream ledgers without a current failure.
Strict rejection remains correct for a pointerless line in `tasks.md` or
`activeContext.md`, not for `backlog.md`.

## Required changes

1. Split the shipped operational-schema prose into strict active-index and
   relaxed backlog-ledger contracts.
2. Update the backlog template to show both pointerless and pointer-bearing
   examples without embedding real project identifiers.
3. Record the supersession in the unreleased changelog.
4. Add a regression proving the same rich-inline pointerless line is accepted
   by both backlog regexes and rejected by both active-index regexes. Pin the
   documentation and template wording in the same suite.

No Doctor runtime, regex, migration, archive, or version behavior changes in
this task.

## Mutation proof

- Substitute `ONELINER_RE` for `BACKLOG_ITEM_RE`: the pointerless backlog case
  must fail.
- Substitute `SCHEMA_TASKS_RE` for `SCHEMA_BACKLOG_RE`: the same case must
  fail.
- Remove the explicit optional-pointer statement from any shipped schema
  surface: the contract test must fail.
- Remove the required-pointer statement for active indexes: the contract test
  must fail.

## Reopen conditions

Reopen only with new measured evidence, such as a live consumer that fails on
pointerless backlog entries, a bounded-context or operator-scanability
regression attributable to long inline descriptions, or a new product
requirement that makes the backlog machine-only. Any future strict migration
must preserve existing prose and include a downstream migration plan; it must
not relabel the superseded 2026 fork as still undecided.
