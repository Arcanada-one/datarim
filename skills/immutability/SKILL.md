---
name: immutability
description: Immutability contract for all pipeline stages: artefact freeze, V-AC parity, non-code parity, anti-tautological rule, and return-to-source transition.
model: inherit
current_aal: 1
target_aal: 1
---

# Immutability — Pipeline Artefact Contract

> **Authority:** RFC 2119 keywords (MUST / MUST NOT / SHOULD / MAY) apply
> throughout. Foundation: Design by Contract (Meyer, 1986) — preconditions
> and postconditions are non-negotiable specifications. ADRs (Nygard, 2011)
> — accepted decisions are immutable; changes are made by superseding, not
> editing. Configuration Management (IEEE 828-2012) — a baseline changes
> only through formal change control procedures.

## Purpose

This skill defines the immutability contract for every Datarim pipeline
stage. An artefact produced by a stage MUST NOT be weakened to accommodate
a constraint discovered in a downstream stage. When a genuine constraint
makes an artefact unsatisfiable, the Return-to-Source Transition provides
the formal revision path.

## Loading

Loaded by every pipeline command (`dr-prd`, `dr-plan`, `dr-design`, `dr-do`,
`dr-qa`, `dr-compliance`) and by the `architect` and `developer` agents.
Frontend-UI tasks additionally load the `## Frontend-UI Rules` fragment.

Each command reads the section matching its stage. The general section
and common rules are always loaded; per-stage fragments are loaded
conditionally by the consuming command.

## Common Rules

#### Artefact Immutability Rule

An artefact produced by a pipeline stage MUST NOT be weakened to accommodate
a constraint discovered in a downstream stage.

An artefact is "weakened" when:
- A requirement (V-AC, D-REQ) is relaxed (broader check, removed criterion,
  lowered threshold).
- A design decision (ADR) is silently reversed without a new creative doc.
- A test or verification command is relaxed to make a failing deliverable pass.
- A checklist item's completion criterion is narrowed to fit an incomplete
  output.
- A QA criterion is re-scoped to avoid failing a deliverable.
- A compliance check is skipped or downgraded from compulsory to optional.
- A visual baseline is replaced without operator diff review.

Valid responses to a constraint that makes an artefact unsatisfiable:
1. **Fix the downstream work** — the artefact is correct, the work is wrong.
2. **The artefact specified the wrong contract** — this triggers the
   Return-to-Source Transition. Do NOT silently weaken the artefact.

#### V-AC Parity Rule

V-AC rows at every stage are subject to the same immutability. A V-AC that
verifies a deliverable MUST NOT be changed to a weaker check so the
deliverable passes without meeting the original criterion. This rule extends
the TDD discipline's V-AC parity rule (`skills/testing/tdd-discipline.md:143`)
to all pipeline stages.

#### Non-Code Parity Rule

For non-code tasks, the to-do / checklist is the "test." A checklist item
MUST NOT have its completion criterion weakened. "Checklist scope reduction"
is the non-code equivalent of weakening a V-AC assertion. This rule extends
`skills/testing/tdd-discipline.md:149` to all stages.

#### Anti-Tautological Rule

A verification criterion MUST be falsifiable. A criterion that always passes
regardless of the state of the implementation is a tautology and MUST be
removed or re-scoped. Examples: "check that the file exists" (always passes
if the implementation creates it), "check that variable X is truthy" (always
passes if the test runner initialises it). This rule generalises
`skills/testing/tdd-discipline.md:101-116` to all verification criteria
across all stages.

#### Return-to-Source Transition

When an artefact genuinely cannot be satisfied as written, the stage executor
MUST NOT silently change it. Instead, follow this transition:

**Trigger:**
A real blocker that genuinely requires changing an immutable artefact (test,
V-AC, checklist item, design decision, QA criterion, compliance criterion,
visual baseline) — not implementation difficulty (which is never a valid
reason), but a discovered constraint (impossible preconditions, wrong level
of specification, newly understood requirement, upstream API change that
invalidates the original contract).

**Who decides:**
The stage executor cannot decide alone. Escalate to the operator with:
(a) the original artefact text verbatim,
(b) the concrete reason it must change,
(c) the proposed new text.

**Where it is recorded:**
In `datarim/tasks/{TASK-ID}-task-description.md` § Decisions, with the format:
```
Return-to-source: <artefact-id> (stage: <stage-name>)
  original: <verbatim original text>
  reason: <rationale for the change>
  proposed: <verbatim proposed new text>
  routes-to: /dr-<target-stage> {TASK-ID}
```
The record is written BEFORE the artefact is changed.

**How the stage resumes:**
After the operator approves the revision and the upstream stage updates its
artefact (or re-issues it), the stage executor resumes work. The CTA after
recording the transition MUST route to the target stage (the stage that owns
the immutable artefact), not continue the current stage.

**Routing table:**

| Artefact being changed | Owned by | Routes to |
|------------------------|----------|-----------|
| PRD V-AC / D-REQ | `/dr-prd` | `/dr-prd {TASK-ID}` |
| Plan V-AC / Implementation Step | `/dr-plan` | `/dr-plan {TASK-ID}` |
| Design decision (creative doc) | `/dr-design` | `/dr-design {TASK-ID}` |
| Test / V-AC verification command | `/dr-do` (recorded in plan) | `/dr-plan {TASK-ID}` |
| QA criterion / Layer structure | `/dr-qa` | `/dr-qa {TASK-ID}` |
| Compliance checklist item | `/dr-compliance` | `/dr-qa {TASK-ID}` (re-verify) |
| Visual baseline (frontend) | `/dr-do` (with operator sign-off) | `/dr-do {TASK-ID}` |

**What this is NOT:**
- NOT an escape hatch for implementation difficulty.
- NOT a post-hoc rationalization without evidence.
- NOT a solo decision — operator review is required.

---

## Per-Stage Fragments

Each fragment is loaded conditionally by the command that owns the stage.
The fragment defines the stage's immutable artefact, supersede path, and
stage-specific immutability rules.

### /dr-prd Rules

**Immutable artefact:** PRD V-AC rows and D-REQ requirements in
`datarim/prd/PRD-*.md`.

**Supersede path:** New PRD file with `supersedes:` frontmatter; old PRD
marked `superseded`.

**Return-to-Source trigger:** Requirement contradiction discovered in any
later stage. Route to `/dr-prd {TASK-ID}`.

**Stage-specific rule:** PRD V-AC rows are MUST-level. They define the
specification that all downstream stages satisfy. Changing a PRD V-AC to
accommodate an implementation constraint is forbidden. If the PRD V-AC
specifies the wrong contract, the operator authorises a PRD revision via
the Return-to-Source Transition.

**Mapped from `/dr-qa` FAIL-Routing:** When QA fails at Layer 1 (PRD
Alignment), the CTA routes to `/dr-prd {TASK-ID}` — consistent with this
fragment's routing.

### /dr-plan Rules

**Immutable artefact:** Plan V-AC rows and Implementation Steps in
`datarim/plans/{TASK-ID}-plan.md` (L3-L4) or
`datarim/tasks/{TASK-ID}-task-description.md` (L1-L2).

**Supersede path:** New plan revision (`-v2`) overwrites; original plan
archived in `documentation/archive/`.

**Return-to-Source trigger:** V-AC or Implementation Step change needed
during `/dr-do`. Route to `/dr-plan {TASK-ID}`.

**Stage-specific rule:** Plan V-AC rows are SHOULD-level at plan time,
becoming MUST-level once `/dr-do` begins. A plan V-AC can be refined
(verification method changed) without reaching back to PRD, provided the
underlying requirement does not change. Contradiction between plan and PRD:
the PRD is the higher authority — the plan is wrong.

**Mapped from `/dr-qa` FAIL-Routing:** When QA fails at Layer 3 (Plan
Completeness), the CTA routes to `/dr-plan {TASK-ID}`.

### /dr-design Rules

**Immutable artefact:** ADR-calibre decisions in
`datarim/creative/creative-*.md` (sections that carry Options + Pros/Cons
+ explicit Decision).

**Supersede path:** New creative file with `supersedes:` frontmatter pointing
to the superseded file. L2 tasks MAY use a lightweight `§ Design Amendment`
appendix with operator sign-off instead of a full new creative doc.

> **Prose amendments stay prose — decided 2026-08-02 (TUNE-0562, closing
> TUNE-0546).** A machine-readable immutable-sidecar mechanism (validator,
> creator, template, chain ledger, three suites) was proposed and is NOT
> adopted. Measured demand at decision time: **274 PRDs in the workspace and
> zero `§ Design Amendment` sections in any of them** — the lightweight path
> above has never once been exercised. Building enforcement infrastructure for
> a workflow with no observed usage adds surface to maintain and a gate to keep
> green, in exchange for nothing. Revisit if prose amendments start appearing
> and drift becomes a real problem; the trigger is usage, not tidiness.

**Return-to-Source trigger:** Design deviation discovered during `/dr-do` or
`/dr-qa`. Route to `/dr-design {TASK-ID}`.

**Stage-specific rule:** Not every detail in a creative doc is frozen.
Supporting material (research notes, exploration dead-ends, implementation
notes) is mutable. Only decisions that carry architectural weight (Options
evaluated, explicit Decision, impact across >=2 components) are immutable.
If a `/dr-do` implementation hits an implementation detail the design
explicitly deferred, no Return-to-Source is needed.

**Mapped from `/dr-qa` FAIL-Routing:** When QA fails at Layer 2 (Design
Conformance), the CTA routes to `/dr-design {TASK-ID}`.

### /dr-do Rules

**Immutable artefact:** Tests (code tests, checklist items, V-AC verification
commands). For code tasks, the Test Immutability Rule from
`skills/testing/tdd-discipline.md:117` is the canonical text. This fragment
provides the routing table entry and the generalised V-AC/Non-Code parity
rules.

**Return-to-Source trigger:** Failing test or V-AC cannot be satisfied as
written. Route to `/dr-plan {TASK-ID}` (or `/dr-prd {TASK-ID}` if the
requirement itself is wrong).

**Stage-specific rule:** The Test Immutability Rule ("a test MUST NOT be
weakened") is the canonical `/dr-do` discipline. The V-AC Parity Rule and
Non-Code Parity Rule from the common rules apply with equal force. The
Return-to-Plan Transition from `skills/testing/tdd-discipline.md:153` is
the implementation of the Return-to-Source Transition for this stage.

**Relationship to tdd-discipline.md:** This fragment does NOT duplicate
the Test Immutability Rule or the Return-to-Plan Transition. It references
`tdd-discipline.md` as the canonical source for those. The common rules
section of this file provides the generalised template; `tdd-discipline.md`
provides the concrete `/dr-do` discipline.

**Mapped from `/dr-qa` FAIL-Routing:** When QA fails at Layer 4 (Code
Quality), the CTA routes to `/dr-do {TASK-ID}`.

### /dr-qa Rules

**Immutable artefact:** QA Layer structure (what is checked — the Layer
templates, the DoD checklist items). The committed QA report after a
verdict is issued is append-only.

**Supersede path:** New QA report with `-v2` suffix; original report kept for
audit trail.

**Return-to-Source trigger:** QA criterion needs change that would weaken
a verification gate. Route to `/dr-qa {TASK-ID}` (re-run after operator
approval). If the change originates from a compliance finding, route to
`/dr-qa {TASK-ID}`.

**Stage-specific rule:** The *structure* of what is checked is immutable; the
specific *invocation* (which linter, which threshold, which test runner
command) is mutable. Tool versions, linter thresholds, and test runner
commands evolve as the framework improves — freezing the exact command would
prevent beneficial upgrades. Only the structure of what is checked is frozen.

**FAIL-Routing consistency:** The immutability skill's routing table MUST
match `/dr-qa`'s existing Layer-to-command FAIL-Routing map from
`skills/cta-format/SKILL.md` § FAIL-Routing. The two tables describe the
same routing from different perspectives: the CTA format defines the
CTASE block shape; this skill defines the contractual basis for the routing.

### /dr-compliance Rules

**Immutable artefact:** The 7-step compliance checklist structure. The
committed compliance report after a verdict is issued is append-only.

**Supersede path:** New compliance report with `-v2` suffix.

**Return-to-Source trigger:** Compliance criterion needs change that would
weaken a compliance gate. Route to `/dr-qa {TASK-ID}` (re-verify after the
QA criterion is revised).

**Stage-specific rule:** The 7-step checklist *structure* (which checks are
run, in what order) is immutable; the tool version and threshold per step
(which linter, which coverage floor) is mutable. The Anti-Tautological Rule
applies to every checklist item: a criterion that always passes is a
tautology and MUST be removed or re-scoped.

### Frontend-UI Rules

**Immutable artefact:** Approved visual baseline (explicit screenshots for
L3-L4 tasks; implicit "current production look" for L1-L2 tasks). Design
token values (colour, spacing, typography) as recorded at design approval
time.

**Supersede path:** New baseline capture replaces old at operator approval;
old baseline archived in `datarim/qa/playwright-{ID}/`.

**Return-to-Source trigger:** Visual deviation that is not operator-approved.
Route to `/dr-do {TASK-ID}`.

**Stage-specific rule:** The approved visual baseline MUST NOT be silently
weakened. If a change introduces a visual difference, it MUST be explicitly
approved (the operator reviews the diff and confirms), not silently accepted
as "close enough." This mirrors the Chromatic approval workflow and the
Anti-Tautological Rule's principle that "passing is not sufficient — the
test must be able to fail."

**L1-L2 tiering:** For L1-L2 frontend tasks, the baseline is implicit
("current production look"). The change either looks the same (PASS) or
different (requires operator inspection). Explicit screenshot baselines are
required only for L3-L4.

**Enforcement:** Tier 1 (in-context directive) is the primary mechanism.
Tier 2 (operator diff review via Playwright evidence at `/dr-qa` Layer 4f)
is the safety net. A deterministic pixel-diff gate (Tier 3) is a deferred
future evolution.

---

## Integration

- **Commands:** `dr-prd.md`, `dr-plan.md`, `dr-design.md`, `dr-do.md`,
  `dr-qa.md`, `dr-compliance.md` — load the immutability skill and their
  stage-specific fragment.
- **Agents:** `architect.md`, `developer.md` — load the immutability skill
  (already loaded via the command that spawns them).
- **Skills:** `frontend-ui/SKILL.md` — loads the Frontend-UI Rules fragment.
- **QA:** `/dr-qa` Layer 3 adds an immutability sub-check (future
  enhancement — deferred to TUNE-NNNN).
- **Pre-archive gate:** `dev-tools/check-v-ac-integrity.sh` (future —
  deferred to TUNE-NNNN).
