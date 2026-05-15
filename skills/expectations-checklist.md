---
name: expectations-checklist
description: Operator wishlist checklist seeded at /dr-prd or /dr-plan; verified at /dr-qa and /dr-compliance with BLOCKED routing on missed/partial without override.
runtime: [claude, codex]
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
schema_version: 1           # integer — required
captured_at: <YYYY-MM-DD>   # date of first write — required
captured_by: /dr-prd        # /dr-prd | /dr-plan — required
status: canonical           # canonical | amended — required (flips on first append)
agent: architect            # architect | planner — recommended
parent_init_task: <path>    # relative path to init-task file — recommended
parent_prd: <path>          # relative path to PRD file when one exists
---
```

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
- **`Связанный AC из PRD`** is advisory. When the PRD has no matching AC,
  use the em-dash «—». Renames in the PRD are recorded in the item's
  История статусов with `stage: append-merge`.
- **`override`** is plain prose, optional. When the current status is
  `partial` or `missed`, an override of fewer than 10 characters is treated
  as absent and the verify mode emits `BLOCKED`.
- **`#### История статусов`** is append-only by convention. One line per
  status transition. Canonical line format:
  `<ISO> / <local> · <stage> · <prior> → <new> · reason: <plain ru>`. The
  three `·` separators and the literal `reason:` token are required.
- **`#### Текущий статус`** carries the current enum value. Allowed values:
  `pending`, `met`, `partial`, `missed`, `n-a`, `deleted`.

### Status semantics

| Status | When | Verify verdict |
|--------|------|----------------|
| `pending` | item created, not yet verified | non-blocking (PASS) |
| `met` | success criterion verified | non-blocking (PASS) |
| `partial` | partially verified; missing sub-check or flaky signal | blocking unless override ≥10 chars |
| `missed` | success criterion not met | blocking unless override ≥10 chars |
| `n-a` | item became inapplicable (scope changed, environment drift) | non-blocking |
| `deleted` | operator dropped the wish (history retained) | non-blocking |

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
  implementation count in the expectations item's История статусов as a
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
| `/dr-qa` | wish bodies; writes per-item Текущий статус | QA report § Expectations + History entries |
| `/dr-compliance` | wish bodies; writes per-item Текущий статус | compliance report § Expectations + History entries |
| `/dr-archive` | wish bodies; writes final per-item summary | archive doc § Выполнение ожиданий оператора |

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
   pruning via explicit `Текущий статус: deleted`.

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

## Dogfooding

The first task to use this contract is the task that defines it. Its own
expectations file lives at `datarim/tasks/{TASK-ID}-expectations.md` of the
framework workspace; `/dr-qa` and `/dr-compliance` invoked on that task
exercise the verify-routing path against the contract itself before the
rest of the framework adopts it.
