---
name: expectations-checklist
description: Operator wishlist checklist seeded at /dr-prd or /dr-plan; verified at /dr-qa and /dr-compliance with BLOCKED routing on missed/partial without override.
current_aal: 1
target_aal: 2
---

# Expectations Checklist

> **Why this exists.** The init-task file (see `init-task-persistence.md`)
> preserves the operator's *prompt*. The expectations file preserves the
> operator's *acceptance test* — what the operator wants to verify when the
> work comes back. Each item is one human-readable wish: "did this aspect of
> the task come out the way I asked?" Without it, agents run their own
> `/dr-qa` checks against PRD acceptance criteria, which are an agent's
> paraphrase of operator intent and can drift silently.
>
> Expectations are written in plain Russian (or the operator's most recent
> message language), one bullet per wish, with a verifiable success
> criterion and an advisory cross-link to a PRD acceptance criterion when
> one exists. `/dr-qa` and `/dr-compliance` assign each item a status
> (`met` / `partial` / `missed` / `n-a` / `deleted`); `partial` or `missed`
> without an operator-supplied override blocks the pipeline and routes work
> back to `/dr-do` with the offending wish-ids in focus.

## File location and naming

```
datarim/tasks/{TASK-ID}-expectations.md
```

One file per task. Same `{TASK-ID}` as the corresponding
`{TASK-ID}-task-description.md` and `{TASK-ID}-init-task.md`. The three
artefacts form a sibling triad:

| File | Author | Purpose |
|------|--------|---------|
| `{ID}-init-task.md` | operator (verbatim) | the original prompt |
| `{ID}-task-description.md` | planner | the agent's interpretation + implementation notes |
| `{ID}-expectations.md` | architect (L3+) / planner (L2 no PRD) | the operator's acceptance test |

## When the file is created

| Complexity | Stage | Agent | Trigger |
|-----------:|-------|-------|---------|
| L3, L4 | `/dr-prd` | architect | after PRD acceptance criteria are finalised |
| L2 (no PRD) | `/dr-plan` | planner | after plan acceptance is finalised |
| L1 | — | — | not required (optional; soft window applies) |

Expectations are **canonical first**, **append-merge after**. The first write
creates the file from PRD/plan AC plus the operator's init-task brief. Later
edits (operator amendments, new AC, scope changes) append new items at the
bottom; existing items are not rewritten — instead a History entry records
the transition.

## Artifact schema

Required YAML frontmatter (closed schema):

```yaml
---
task_id: <TASK-ID>          # ^[A-Z]{2,10}-[0-9]{4}$ — required
artifact: expectations      # literal — required
schema_version: 2           # integer — required (current: 2; legacy: 1, sunset 2027-05-23)
captured_at: <YYYY-MM-DD>   # date of first write — required
captured_by: /dr-init       # /dr-init | /dr-prd | /dr-plan — required
status: canonical           # canonical | amended — required (flips on first append)
agent: planner              # architect | planner — recommended
parent_init_task: <path>    # relative path to init-task file — recommended
parent_prd: <path>          # relative path to PRD file when one exists
---
```

**Schema v2 (current):** adds required `evidence_type` field per wish item
(enum: `empirical | static | measurement`). Validator
(`dev-tools/check-expectations-checklist.sh`) rejects items without
`evidence_type` in v2 mode.

**Schema v1 (legacy):** accepted by validator until **2027-05-23** (12 months
from the v1→v2 migration archive). Deprecation warning emitted on every validator
invocation. Migration recipe: add `evidence_type: empirical` (or
`static`/`measurement`) to each wish; bump `schema_version: 2`.

## Body shape

```markdown
# {TASK-ID} — Ожидания оператора

## Ожидания

- **<N>. <Plain-language title ending with a period>**
  - wish_id: <kebab-slug; cyrillic letters allowed>
  - Что хочу проверить: <one or two sentences>
  - Как проверить (success criterion): <one concrete signal — file path,
    command output, visible behaviour>
  - Связанный AC из PRD: V-AC-<N> или «—»
  - evidence_type: <empirical | static | measurement>  # v2 — required
  - override: <optional reason text, only used when status flips to
    partial/missed and the operator decides to ship anyway>
  - #### История статусов
    - <ISO 8601> / <local time> · <stage> · <prior> → <new> · reason: <plain ru>
  - #### Текущий статус
    - <pending | met | partial | missed | n-a | deleted>

## Append-log (operator amendments)

_(empty on first write)_
```

### Item rules

- **`wish_id`** is a kebab-slug derived from the title. Cyrillic letters,
  ASCII letters, digits, and hyphens are allowed. Used as the focus key in
  FAIL-Routing CTA (`/dr-do <ID> --focus-items <wish_id_1,...,N>`).
- **`Связанный AC из PRD`** is advisory. When the PRD has no matching AC, <!-- allow-non-ascii: russian-expectations-field-name-cited-from-canonical-schema -->
  use the em-dash «—». Renames in the PRD are recorded in the item's
  История статусов with `stage: append-merge`. <!-- allow-non-ascii: russian-status-history-section-name-from-canonical-schema -->
- **`override`** is plain prose, optional. When the current status is
  `partial` or `missed`, an override of fewer than 10 characters is treated
  as absent and the verify mode emits `BLOCKED`.
- **`#### История статусов`** is append-only by convention. One line per <!-- allow-non-ascii: russian-status-history-section-name-from-canonical-schema -->
  status transition. Canonical line format:
  `<ISO> / <local> · <stage> · <prior> → <new> · reason: <plain ru>`. The
  three `·` separators and the literal `reason:` token are required.
- **`#### Текущий статус`** carries the current enum value. Allowed values: <!-- allow-non-ascii: russian-current-status-section-name-from-canonical-schema -->
  `pending`, `met`, `partial`, `missed`, `n-a`, `deleted`.
- **`evidence_type`** (schema v2, required) declares what kind of evidence
  `/dr-qa` must produce for this wish at Layer 3b. Allowed enum:
  - **`empirical`** — runtime check: command invocation, smoke test, E2E
    test, integration probe. Per-wish QA report MUST contain actual
    command + stdout/exit-code, not only a grep-against-markdown.
  - **`static`** — static check: `grep`, `test -f`, line-count, regex match
    against the source tree or a documentation file. Cheapest tier; if all
    wishes in a task are `static`, the validator emits an advisory warning
    (`--all` mode) because the task likely lacks runtime evidence.
  - **`measurement`** — numeric measurement: latency p95, throughput,
    coverage %, token cost, file count vs target. Per-wish QA report MUST
    contain the measured value + comparison to expected (`X = 87ms <
    budget 100ms`).

### Status semantics

| Status | When | Verify verdict |
|--------|------|----------------|
| `pending` | item created, not yet verified | non-blocking (PASS) |
| `met` | success criterion verified | non-blocking (PASS) |
| `partial` | partially verified; missing sub-check or flaky signal | blocking unless override ≥10 chars |
| `missed` | success criterion not met | blocking unless override ≥10 chars |
| `n-a` | item became inapplicable (scope changed, environment drift) | non-blocking |
| `deleted` | operator dropped the wish (history retained) | non-blocking |

<!-- gate:history-allowed -->
> **Glossary note.** `closed` is NOT an enum value here, although the word often appears in QA/PRD prose to mean "success criterion verified". The correct enum for that semantics is `met`. The validator (`dev-tools/check-expectations-checklist.sh --task <ID>`) rejects `closed` as a structural error; pipelines fail late at `/dr-compliance --verify` rather than at write time. Source: TUNE-0295 Phase H L2-F-8 wrote `closed`, surfaced only at `/dr-compliance` re-validation.
<!-- /gate:history-allowed -->

### Numeric literals in success criteria

Avoid hardcoded counts in success criteria when the count is derived from
the codebase (skill count, line count, test count, file count). A literal
number locks the AC to plan-time arithmetic and drifts when implementation
revises the scope — for example, when a phase absorbs an unmerged branch
and adds an extra artefact.

Prefer one of two formulations:

- **Formula.** «Counter X equals the number of files matching pattern Y
  plus the agreed delta Z.» Verification is `find ... | wc -l` plus an
  inline comparison, which stays correct under scope revisions.
- **Re-derive at /dr-do time.** When the literal is genuinely required
  (e.g. user-visible counter on a landing page), record the actual
  implementation count in the expectations item's История статусов as a <!-- allow-non-ascii: russian-status-history-section-name-from-canonical-schema -->
  one-line `stage: implementation-count` entry, and treat that line as
  the authoritative target. PRD-side AC remains an estimate.

Drift on a literal is recorded as «implemented with documented drift»
rather than `missed`; the verify verdict still PASSes because operator
intent (counter reflects new artefacts) is satisfied. Repeated occurrences
of the same drift class across tasks indicate the AC was authored as a
literal where a formula would have served.

## Mandatory read by pipeline commands

After the file is created, every later pipeline command MUST read it and
reconcile any divergence in its own output document:

| Command | What it reads | Where divergence is recorded |
|--------|---------------|------------------------------|
| `/dr-design` | wish bodies | design doc § Decisions |
| `/dr-do` | wish bodies; `--focus-items` ⇒ those wish-ids first | task-description § Implementation Notes |
| `/dr-qa` | wish bodies; writes per-item Текущий статус | QA report § Expectations + History entries | <!-- allow-non-ascii: russian-current-status-field-cited-in-table-row -->
| `/dr-compliance` | wish bodies; writes per-item Текущий статус | compliance report § Expectations + History entries | <!-- allow-non-ascii: russian-current-status-field-cited-in-table-row -->
| `/dr-archive` | wish bodies; writes final per-item summary | archive doc § Выполнение ожиданий оператора | <!-- allow-non-ascii: russian-archive-section-name-cited-in-table-row -->

## Append-merge contract

When `/dr-prd` or `/dr-plan` runs a second time on a task that already has
an expectations file:

1. Load existing items by `wish_id`.
2. For each new wish derived from updated PRD/plan AC, look up by wish_id:
   - **No match** → append as a new item at the bottom; record one History
     line `stage: append-merge` with reason "added at <current-stage>".
   - **Match** → leave the item body untouched; record a History line
     `stage: append-merge` only if the linked AC reference changed.
3. Do not rewrite, reorder, or delete existing items. Operators control
   pruning via explicit `Текущий статус: deleted`. <!-- allow-non-ascii: russian-current-status-enum-value-cited-from-canonical-schema -->

## Multi-phase umbrellas (phase-level verify)

When the task being verified is one phase of a multi-phase umbrella whose
expectations file lives at the **umbrella** task ID (no separate
`{PHASE-ID}-expectations.md` exists), `/dr-qa` and `/dr-compliance` invoked
on the phase ID MAY legitimately:

- Update `#### Текущий статус` only for wish-ids that fall in the phase's <!-- allow-non-ascii: russian-current-status-field-cited-in-bullet -->
  scope (e.g. flip from `pending` to `met` when the phase delivers the
  underlying success criterion).
- Leave umbrella close-gate wish-ids and later-phase wish-ids as
  `pending`. These are not `n-a` (the wish remains in scope; it is just
  not yet verifiable) and not `partial`/`missed` (no failure to record at
  this point in the pipeline).
- Append one `История статусов` line per touched item with `reason:` text <!-- allow-non-ascii: russian-status-history-section-name-cited-in-bullet -->
  that names the phase scope explicitly (e.g. «ожидание относится к <!-- allow-non-ascii: russian-example-status-reason-illustrating-phase-scope -->
  фазе 3 (audit coverage); в фазе 1 не реализуется»). The phase mention <!-- allow-non-ascii: russian-example-status-reason-illustrating-phase-scope -->
  in the reason is what lets the umbrella close-gate auditor distinguish
  «pending because phase X hasn't run» from «pending because no one looked».

The validator still PASSes when `Текущий статус` is `pending` for these <!-- allow-non-ascii: russian-current-status-field-cited-in-prose -->
items; the audit clarity comes from the History entry, not the status enum.
On umbrella close (the last phase's `/dr-archive` or a follow-up umbrella
QA pass), the remaining `pending` items are reconciled to `met` /
`partial` / `missed` per the actual umbrella-wide outcome.

## Verify-routing contract

`/dr-qa` and `/dr-compliance` both invoke
`dev-tools/check-expectations-checklist.sh --verify <ID>` after running
their own structural checks. Three verdicts (single source of truth: the
validator's stdout markers):

- **`PASS`** — every item is `met`, `n-a`, `pending`, or `deleted`. The
  command proceeds.
- **`CONDITIONAL_PASS`** — at least one `partial`/`missed` item, but every
  such item carries an operator override ≥10 characters. The command
  proceeds; the report records the conditional state.
- **`BLOCKED`** — at least one `partial`/`missed` item without a valid
  override. The validator prints `Focus items: <wish_id_1,...,N>` and
  `Next step: /dr-do <ID> --focus-items <wish_id_1,...,N>`. The command
  refuses to continue and emits a FAIL-Routing CTA (see `cta-format.md`).

## Backwards-compatibility window

- **Per-task 30-day rolling soft window.** Tasks created before the
  expectations contract existed (or in the first 30 days after adoption)
  are protected from blocker-level findings.
- **Below L3 is optional.** L1 and L2 tasks may skip the file entirely;
  `--all` advisory does not flag them.
- **Archive immunity.** Tasks with `status: archived | completed |
  cancelled` are never flagged.
- **Legacy marker.** Operators MAY set `legacy: true` in the description's
  frontmatter to suppress findings indefinitely.

## Validation

`dev-tools/check-expectations-checklist.sh` is the canonical validator.

- `--task <ID>`: structural validation. Exit 0 / 1 / 2.
- `--verify <ID>`: verdict mode. Exit 0 (PASS / CONDITIONAL_PASS) /
  1 (BLOCKED or malformed) / 2 (usage).
- `--all`: advisory scan for L3+ tasks without expectations. Always exit 0;
  severity ladder `info` (<30d) → `warn` (≥30d).

**Full verdict requires both passes.** `--task` exit 0 is necessary but
not sufficient for `--verify` PASS — `--task` checks schema validity and
status presence; `--verify` additionally parses verdict routing
(PASS / CONDITIONAL_PASS / BLOCKED) and enumerates focus-items on block.
For complete pre-archive verdict, run both in sequence: first
`--task <ID>` to confirm schema/status, then `--verify <ID>` to obtain the
routing verdict.

## Dogfooding

The first task to use this contract is the task that defines it. Its own
expectations file lives at `datarim/tasks/{TASK-ID}-expectations.md` of the
framework workspace; `/dr-qa` and `/dr-compliance` invoked on that task
exercise the verify-routing path against the contract itself before the
rest of the framework adopts it.

## Related skills

See also `skills/v-ac-axis-split/SKILL.md` for V-AC group composition rule
(deterministic vs statistical axis separation). When drafting success
criteria, identify whether each axis is rule-based (deterministic — single
bats assertion or grep evidence) or rate-based (statistical — threshold over
a measurement window with sample size and confidence interval). Mixing the
two in one wish item masks which axis is the actual uncertainty source and
yields false confidence at `/dr-qa` time. Split early; cite the measurement
window for statistical criteria; cite the assertion evidence for
deterministic criteria.
