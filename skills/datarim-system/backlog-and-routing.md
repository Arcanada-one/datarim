# Datarim System — Backlog and Routing

## Backlog Management (v2.0)

### Two-File Architecture

**Active Backlog** (`backlog.md`)
- contains only `pending` and `in_progress`
- optimized for normal reads
- uses the same `{PREFIX}-{NNNN}` ID the task will keep later

**Backlog Archive** (`backlog-archive.md`)
- stores `completed` and `cancelled` items
- used for history, not routine execution

### When to Update

- On task completion: move from `backlog.md` to `backlog-archive.md`
- On new work: add to `backlog.md` with `pending`

## Complexity Decision Tree

### Level 1

- single file change
- under 50 lines of code
- no architecture changes
- flow: `init → do → archive`

### Level 2

- 2-5 files
- under 200 lines
- minor refactoring
- flow: `init → plan → do → archive`

### Level 3

- 5-15 files
- 200-1000 lines
- requires design
- flow: `init → prd → plan → design → do → qa → compliance → archive`

### Level 4

- 15+ files
- over 1000 lines
- complex architecture
- flow: `init → prd → plan → design → phased-do → qa → compliance → archive`

All levels: `archive` runs reflection internally as mandatory Step 0.5 (v1.10.0, TUNE-0013).

## Date Handling

Use native shell date utilities:

```bash
date +%Y-%m-%d
date -u +%Y-%m-%dT%H:%M:%SZ
```

Or use the current date from session context.

## Plan Drift Discipline

When a `/dr-do` step modifies an Acceptance Criterion in a measurable way — sample size (50 → 41), threshold (≥0.8 → ≥0.5), dataset (full → curated subset), tool (planned model → fallback model) — patch the plan document inline **before commit**, not after QA flags drift. A single-line edit to plan §10 takes seconds; an unexplained drift adds noise to Layer 3 verification and forces the QA report to spend lines explaining a deviation that should have been a planning artefact.

Source: LTM-0012 — pilot subset modified 50 → 41 chunks for ground-truth coverage; the operational decision was correct, but the plan kept saying «50» until QA flagged it. Recurring class with TUNE-0034 (stale `@test` count) and TUNE-0028 (stale skill count): drift between plan and reality is process debt that compounds.

## Embedded Phases (not separate pipeline stages)

- **Research** runs inside `/dr-prd` as Phase 1.3 (L2+). Researcher agent produces `datarim/insights/INSIGHTS-{task-id}.md`. Not a separate pipeline node — no routing change needed. (TUNE-0029)
- **Gap Discovery** runs inside `/dr-do` as Step 7.5. Developer agent spawns researcher subagent on unknowns, appends to insights. Fundamental gaps escalate to `/dr-prd`. (TUNE-0029)

## Mode Transition Optimization

Every transition listed below MUST be surfaced to the user as a canonical CTA block per `$HOME/.claude/skills/cta-format.md`. The text in this section defines WHICH command becomes the primary CTA at each transition; the FORMAT of the CTA block is owned by `cta-format.md` (single source of truth, TUNE-0032 v1.16.0).

### Automatic Transitions (primary CTA after each stage)

| Stage finished | Complexity | Primary CTA in next-step block |
|---|---|---|
| `/dr-plan` | L3-4 | `/dr-design {TASK-ID}` |
| `/dr-plan` | L1-2 | `/dr-do {TASK-ID}` |
| `/dr-design` | L3-4 | `/dr-do {TASK-ID}` |
| `/dr-do` | L3-4 | `/dr-qa {TASK-ID}` |
| `/dr-do` | L1-2 | `/dr-archive {TASK-ID}` (reflection runs Step 0.5) |
| `/dr-qa` PASS / CONDITIONAL_PASS | L3-4 | `/dr-compliance {TASK-ID}` |
| `/dr-qa` PASS / CONDITIONAL_PASS | L1-2 | `/dr-archive {TASK-ID}` |
| `/dr-compliance` COMPLIANT* | L3-4 | `/dr-archive {TASK-ID}` |

### FAIL Return Routing (FAIL-Routing CTA variant)

QA BLOCKED → header `**QA failed для {TASK-ID} — earliest failed layer: Layer N (Layer name)**`, primary CTA per Layer-to-command map:

| Failed Layer | Primary CTA |
|---|---|
| Layer 1 (PRD) | `/dr-prd {TASK-ID}` |
| Layer 2 (Design) | `/dr-design {TASK-ID}` |
| Layer 3 (Plan) | `/dr-plan {TASK-ID}` |
| Layer 4 (Code) | `/dr-do {TASK-ID}` |

Compliance NON-COMPLIANT → header `**Compliance NON-COMPLIANT для {TASK-ID} — ...**`, primary `/dr-do {TASK-ID}` (default) or earlier stage if PRD/plan gap identified.

After fix: resume forward, re-run QA/compliance. Loop guard: 3 same-layer fails → escalate to user via CTA option `Эскалация` (see `cta-format.md` § FAIL-Routing).

### Manual Transitions

- `/dr-plan` → planning mode
- `/dr-design` → creative mode
- `/dr-do` → execution mode
- `/dr-qa` → QA mode
- `/dr-archive` → archive mode (includes reflection as Step 0.5)

### Multi-task awareness (Variant B)

Whenever `## Active Tasks` in `datarim/activeContext.md` lists >1 task, the CTA block MUST append a `**Другие активные задачи:**` menu listing each parallel task with its own recommended next command. This is mandatory for `/dr-status`, `/dr-continue`, `/dr-archive`; agents on other commands MAY append it when context permits. See `cta-format.md` § Canonical Block — Multiple Active Tasks.
