# Datarim System — Backlog and Routing

## Backlog Management (v3.0 — single-file)

### Single-File Architecture

**Backlog** (`backlog.md`) — thin one-liner index
- contains only `pending` / `blocked-pending` / `cancelled` (transient state)
- optimized for normal reads
- uses the same `{PREFIX}-{NNNN}` ID the task will keep later

`backlog-archive.md` was retired in v1.19.1. Completion archive
is **canonical only** in `documentation/archive/{area}/archive-{ID}.md`
(committed to git). Cancelled tasks live in
`documentation/archive/cancelled/archive-{ID}.md`.

### When to Update

- On task completion: remove from `backlog.md`; archive prose lives in
  `documentation/archive/{area}/archive-{ID}.md` written by `/dr-archive`.
- On task cancellation: write `documentation/archive/cancelled/archive-{ID}.md`,
  then remove from `backlog.md`.
- On new work: add to `backlog.md` with `pending`.

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

All levels: `archive` runs reflection internally as mandatory Step 0.5.

## Date Handling

Use native shell date utilities:

```bash
date +%Y-%m-%d
date -u +%Y-%m-%dT%H:%M:%SZ
```

Or use the current date from session context.

## Plan Drift Discipline

When a `/dr-do` step modifies an Acceptance Criterion in a measurable way — sample size (50 → 41), threshold (≥0.8 → ≥0.5), dataset (full → curated subset), tool (planned model → fallback model) — patch the plan document inline **before commit**, not after QA flags drift. A single-line edit to plan §10 takes seconds; an unexplained drift adds noise to Layer 3 verification and forces the QA report to spend lines explaining a deviation that should have been a planning artefact.

Source: prior incident — pilot subset modified 50 → 41 chunks for ground-truth coverage; the operational decision was correct, but the plan kept saying «50» until QA flagged it. Recurring class with stale `@test` counts and stale skill counts: drift between plan and reality is process debt that compounds.

### Avoid absolute test-count numbers in AC formulation

Test-baseline ACs that pin an absolute number (e.g. «≥159/160 PASS») drift between plan and `/dr-do` whenever an unrelated concurrent task changes the suite (description-length sweep, new spec test, removed assertion). Use **semantic phrasing** that survives baseline shifts:

- ✅ «0 new failures vs HEAD baseline» — durable, captures the intent
- ✅ «test count ≥ HEAD baseline (verify with `git stash && bats tests/`)» — durable + recipe
- ❌ «≥159/160 PASS» — pins to a snapshot that goes stale within hours

When the absolute number IS the AC (e.g. «add 5 new tests, expect +5 pass»), state it as a delta against HEAD baseline measured immediately before the edit, not as an absolute target.

Source: prior incident — plan AC-5 said «≥159/160 PASS», actual baseline at QA time was 158/160 (a pre-existing red surfaced between plan and `/dr-do`). Semantic intent («0 regressions») was met; the absolute number forced QA to spend a paragraph explaining the gap.

### Re-verify quantitative backlog inventories at init/do start

When a backlog item lists specific quantitative claims — «N failing tests #X..#Y», «M hits across K files», «P GHSA in audit», «Q deprecated references in skill foo» — the inventory is a **snapshot** taken when the item was filed. Concurrent unrelated tasks can quietly close a fraction of the inventory between snapshot-time and execution-time, so the inventory must be re-verified before treating it as canonical.

**Recipe at `/dr-init` or `/dr-do` start:**

1. Re-execute the **same diagnostic** the inventory was built from (`bats tests/`, `grep -rln pattern path`, the project's package-manager-native audit command, `scripts/stack-agnostic-gate.sh scope`, etc.).
2. Compare the live count to the inventory count.
3. **reality < inventory** → amend the backlog body inline (strike or rewrite the closed entries with a one-line «closed by {commit-or-task-id}» note), recalibrate the estimate, log the delta in `progress.md`. Do not silently proceed on stale numbers.
4. **reality > inventory** → escalate to the operator as scope expansion. Decide whether to absorb the new items, defer to a follow-up, or split the task.
5. **reality == inventory** → proceed; no action.

Source: prior incident — backlog body listed «10 failing tests» with named root causes. Pre-flight `bats tests/` at /dr-do start showed only 2 actual reds — 8 had been closed in flight by parallel sweep tasks (optimizer rewrite, description-length sweep, stack-agnostic sweep, description trim). Estimate (30-60 min) was 5× the actual (10 min). Skipping re-verification could have caused phantom-debug work on already-passing tests.

Companion to «Avoid absolute test-count numbers in AC formulation» above: same source-of-truth logic applied to inventory-side claims rather than AC-side claims. Both rules answer the same question — «how do we keep backlog text in sync with runtime reality?» — at different points in the pipeline.

## MR-Strategy Heuristic for L3-L4 Tasks

When a Strategist gate must decide between one-MR delivery and per-phase staged release, classify the feature first:

- **Closed-loop feature** — component N+1 depends on component N's outputs being **persisted** (skill writes entries that retrieval reads, sync pushes deltas the digest promotes, etc.). Ship in **one MR** and release design docs (architecture, data-model, algorithm, deploy) BEFORE the code MR opens, so reviewers load the entire shape before reading any one piece. Splitting a closed loop into per-phase MRs creates intermediate states where, e.g., the writer ships before the reader, or the sync runs on entries the digest cannot promote — every intermediate state is broken-by-design.

- **Open-loop feature** — each component is independently testable in production, with no persistence-mediated handoff between components (CRUD endpoints behind a feature flag, parallel notifier backends, additive UI panels). **Stage-release per component** with feature flags; one MR per component is the default; intermediate states are valid runtime configurations.

**Decision recipe at PRD time:**

1. Draw the data-flow graph: which component writes what, and which component reads it on the next pass?
2. If any read depends on a write that the same task introduces → closed-loop → one MR.
3. Else → open-loop → stage-release.

**Why this matters for plan §2 Strategist gate:** the gate's MR-count answer drives Operator workload (one merge vs N), QA cycle count (one cycle covering the whole shape vs N independent cycles), and design-doc scope (full architecture upfront vs per-component appendices). Misclassifying open-loop as closed-loop wastes review bandwidth; misclassifying closed-loop as open-loop ships broken intermediate states.

Source: prior incident reflection §2.4 — 10 phases (model upgrade → knowledge base → evolution skill → retrieval hook → installer → sync cron → digest cron → auto-promotion gate → Aether-internal contract → pre-merge rehearsal) formed a closed loop; one-MR delivery with 4 design docs released before code was the right strategy. Per-phase MRs would have shipped 10 broken intermediate states.

## Embedded Phases (not separate pipeline stages)

- **Research** runs inside `/dr-prd` as Phase 1.3 (L2+). Researcher agent produces `datarim/insights/INSIGHTS-{task-id}.md`. Not a separate pipeline node — no routing change needed.
- **Gap Discovery** runs inside `/dr-do` as Step 7.5. Developer agent spawns researcher subagent on unknowns, appends to insights. Fundamental gaps escalate to `/dr-prd`.

## Mode Transition Optimization

Every transition listed below MUST be surfaced to the user as a canonical CTA block per `$HOME/.claude/skills/cta-format.md`. The text in this section defines WHICH command becomes the primary CTA at each transition; the FORMAT of the CTA block is owned by `cta-format.md` (single source of truth).

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
