---
task_id: TUNE-0530
artifact: creative
captured_at: 2026-07-29
captured_by: /dr-design
agent: architect
status: canonical
schema_version: 1
consilium: true
consilium_panel: [architect, strategist, planner, security, developer]
consilium_model: fable
---

# creative-TUNE-0530-architecture-stack-proposal-mechanism

## Problem

Datarim's `skills/tech-stack/SKILL.md` prescribes a single mandatory stack per project type under the heading "Project Type -> Required Stack." The skill's "Final Rule" says "Do NOT ask which stack to use. Apply rules automatically." This prevents the operator from ever seeing a choice. A real case exposed the defect: Control Arcana redesign, where Tailwind vs MUI never reached the operator because the table said Tailwind and the agent defended the incumbent.

The design question: **what is the correct replacement mechanism, and what are its edges?**

The PRD (PRD-TUNE-0530) proposed Approach C: Guidance-First Table + Proposal Step + Defaults for Routine Work. This creative document stress-tests that approach through a Fable 5 consilium panel, records dissent, and resolves conflicts using the Priority Ladder.

## Consilium Panel

**Question:** Is Approach C the correct mechanism, and are the specific design choices (trigger classifier, proposal template shape, ADR binding, toolchain reform) safe and sufficient?

**Panel:** architect, strategist, planner, security — each on Fable 5 (`--model fable`)
**Blast radius:** 3 (Cross-system — tech-stack is loaded by 4 agents + /dr-init; changes propagate to every project setup across the ecosystem)

### Panel Positions

| Agent | Position | Core Concern |
|-------|----------|-------------|
| **architect** | Conditional support | Template missing escape-velocity factor; trigger classifier has first-module blind spot; candidate ordering creates rubber-stamp risk; toolchain reform is insufficient (DISSENT) |
| **strategist** | Conditional support | Over-engineered for one Control Arcana data point; stack choices should NOT be immutable; cheaper alternative: three-column table + remove "Do NOT ask" rules (DISSENT on immutability) |
| **planner** | Conditional support | Tech-stack skill's "Do NOT ask" rule contradicts the proposal step — must rewrite skill first; stack proposal should be /dr-plan primary, /dr-prd optional only (DISSENT on dual placement); sticky choices needed for multi-service projects; missing stack-migration trigger |
| **security** | Conditional support | Proposal template omits security as a mandatory factor; five new domains added with zero framework security guidance; no CVE emergency fast-track in immutability contract |
| **developer** | Conditional support | Developer doesn't load tech-stack (correct); but mid-implementation escape path needs concrete step-by-step sequence; trigger classifier needs default catch-all; "When to Reconsider" needs verifiable litmus tests |

### Unanimous Agreements

1. The current prescriptive table is a real defect — all four agents agree the change is warranted
2. The table format change (single-column → multi-column with alternatives) is the minimum necessary fix
3. The trigger classifier is the critical gate — if it fires too often, the mechanism creates friction without value
4. The proposal template needs at least one additional factor: Security posture (per Security)
5. The "Do NOT ask which stack to use" Final Rule must be removed as part of the rework

## Conflicts and Resolutions

### Conflict 1: Mechanism Scope — Table Change vs Full Proposal Engine

| Agent A | Agent B | Conflict | Resolution Path |
|---------|---------|----------|-----------------|
| strategist | architect, planner | Strategist: single-column table + remove "Do NOT ask" rules addresses Control Arcana case at ~5 lines cost; full proposal mechanism is over-engineered for one data point. Architect/Planner: the mechanism is needed for non-routine cases (cross-domain, new-project, stack-migration) that the table alone cannot handle. | Layers 5 (Simplicity) vs 4 (Reliability). The table change is the floor — it ships first and addresses the Control Arcana class of defect. The proposal mechanism ships as a conditional overlay activated only on specific triggers (new-project, cross-domain, stack-migration, operator-request), not on every L3+ task. This keeps routine work friction-free while providing the mechanism for non-routine cases. |

**Resolution:** Both ship. Phase 1a: table format change (Default Recommendation | Viable Alternatives | When to Reconsider) + remove "Do NOT ask" rules. Phase 1b: proposal mechanism wired as a conditional step, activated by the trigger classifier. The table change is the minimum viable fix; the proposal mechanism adds value for the ~20% of cases where the table's default is not obviously correct.

### Conflict 2: Immutability Binding — ADR-Calibre vs Lightweight Decision Note

| Agent A | Agent B | Conflict | Resolution Path |
|---------|---------|----------|-----------------|
| strategist | architect | Strategist: stack choices are implementation detail, not architecture — should be lightweight decision notes, revisable with a one-line rationale at /dr-do time. Architect: without binding, the choice has no enforcement and can be silently swapped mid-implementation (the current defect, reversed). | Layers 2 (Correctness) vs 5 (Simplicity). Correctness wins: a chosen stack must not be silently swapped. But Strategist is right that full ADR-calibre ceremony with creative-doc return-to-source is excessive. Compromise: the stack choice is recorded as a **decision note** in the plan's § Decisions section (not a standalone ADR file), binding for the current task cycle, revisable via Return-to-Plan amendment (not creative-doc rewrite), and with a **security-emergency fast-track** per Security Agent: a CVSS 9+ or KEV CVE in the chosen stack suspends the binding; the agent may propose and implement an alternative with a written notice in the task description decisions section within one turn. |

**Resolution:** Decision note (not ADR) in plan § Decisions. Binding for current task cycle. Revisable via Return-to-Plan amendment. Security-emergency fast-track per Security condition #2.

### Conflict 3: Pipeline Placement — Dual PRD+Plan vs Plan-Only

| Agent A | Agent B | Conflict | Resolution Path |
|---------|---------|----------|-----------------|
| planner | PRD design | Planner: stack proposal should be /dr-plan primary, /dr-prd optional — at PRD time the operator is still exploring requirements, not implementation details. The PRD should document the assumed stack and flag if the choice is architecture-driving; the formal decision lives at /dr-plan Step 6 when concrete pins and lockfile audits are possible. | Layers 6 (Cost) vs 4 (Reliability). At PRD time an architecture-driving stack choice (e.g., Rust vs Python determines whether GPU nodes are needed) must be visible. At plan time the concrete choice with version pins and audit must be confirmed. Split: /dr-prd documents the assumed stack and marks if architecture-driving; /dr-plan runs the formal proposal step with concrete candidates and lockfile-auditable pins. Neither stage is skipped — they serve different purposes. |

**Resolution:** /dr-prd: document assumed stack, flag if architecture-driving, optional proposal generation. /dr-plan: formal proposal step with concrete candidates, version pins, and live audit checkpoint. The operator's formal choice is recorded at /dr-plan.

### Conflict 4: Toolchain Reform — Heading Rename vs Real Decision Surface

| Agent A | Agent B | Conflict | Resolution Path |
|---------|---------|----------|-----------------|
| architect | PRD design | Architect: renaming "Mandatory Toolchains" to "Recommended Toolchains" is the same defect at a smaller scale — toolchains constrain the operating model the same way stacks do, and if the mechanism's purpose is informed operator choice, toolchains deserve a real (if lightweight) decision surface. PRD: toolchains are quality-floor consensus, not architecture choices. | Layer 7 (Elegance) vs 5 (Simplicity). Simplicity wins for v1. Toolchains (uv+ruff+pytest, pnpm+TypeScript+eslint+prettier+vitest) are ecosystem-wide quality-floor choices, not per-project architecture decisions. The heading rename + softening of FORBIDDEN language is sufficient for this task. **But** — the reflection must note the architect's dissent and propose a future lightweight "toolchain deviation" path (a short checklist, not a full proposal) if the toolchain section proves to be the same defect at smaller scale. |

**Resolution:** Keep the heading rename + soften language. Record architect's dissent in reflection for future evaluation. If evidence shows toolchains becoming rigid defaults in practice, spawn a follow-up task for lightweight toolchain-choice mechanism.

## Design Decisions (Resolved)

### D-1: Table Format
Replace "Project Type -> Required Stack" with "Starting Points & Alternatives" — three columns: Default Recommendation | Viable Alternatives | When to Reconsider. Each row carries explicit alternatives.

### D-2: Proposal Mechanism
Conditional overlay activated by trigger classifier. Not a mandatory pipeline step for every task.

### D-3: Trigger Classifier
Five triggers:
1. **new-project** — full proposal required
2. **new-component-cross-domain** — full proposal required (domain-axis heuristic: crosses runtime boundary, introduces new data-persistence model, or changes primary interaction pattern)
3. **stack-migration** — full proposal required (task description or PRD explicitly names a stack change)
4. **operator-request** — full proposal required
5. **routine-same-domain** — skip; use incumbent stack

Additional L1 exclusion: L1 tasks never trigger a proposal.

### D-4: Proposal Template — Eight Mandatory Factors
1. Fit for domain
2. Ecosystem maturity
3. Team/AI familiarity
4. Performance profile
5. **Security posture** (CVE history, sandbox model, supply-chain trust, audit tooling, secure-config baseline maturity) — added per Security Agent
6. Licence & cost (including transitive-license risk where assessable)
7. Bundle/runtime cost
8. Operational fit (Arcanada ecosystem coherence)
9. **Escape velocity** (migration cost/portability) — added per Architect Agent

### D-5: Candidate Ordering
Candidates listed alphabetically or by neutral sort. The recommendation is stated in the dedicated `### Recommendation` section, not implied by position. No "Recommended" label on Candidate 1.

### D-6: Choice Recording
Decision note in plan § Decisions (not standalone ADR). Binding for current task cycle. Revisable via Return-to-Plan amendment.

### D-7: Security-Emergency Fast-Track
CVSS 9+ or KEV CVE in the chosen stack suspends the binding. Agent may propose and implement an alternative with written notice in task description decisions section within one turn. Normal immutability process applies to all non-security artefacts.

### D-8: Sticky Choices / Child-Task Inheritance
Once a stack is chosen for a project, subsequent same-project components auto-inherit unless explicitly overridden. Child tasks inherit the parent's stack for the same component automatically. Proposal fires only when the child introduces a component in a domain the parent did not address.

### D-9: Pipeline Placement
- `/dr-prd`: document assumed stack; flag if architecture-driving; optional proposal generation
- `/dr-plan` Step 6: formal proposal step with concrete candidates, version pins, live audit
- `/dr-init`: update language from "identify required stack" to "identify starting-point stack"

### D-10: Backend-Standards Boundary
Tech-stack file notes that `documentation/architecture/backend-stack-standards.md` is the authoritative mandate for Arcanada backend projects. The tech-stack row functions as guidance within that constraint.

### D-11: Stack-Agnostic Gate
Whitelist entry updated with rationale: "designated technology guidance file; names concrete technologies to give actionable recommendations while presenting alternatives and trade-offs rather than single mandated answers."

### D-12: Toolchain Reform (with Architect Dissent Noted)
Heading "Mandatory Toolchains" → "Recommended Toolchains." Soften FORBIDDEN language. **Dissent recorded:** Architect believes toolchains need a real (lightweight) decision surface, not a heading rename. Reflection to note for future evaluation.

### D-13: Trigger Classifier Default Catch-All (Developer)
When the trigger classifier cannot unambiguously classify a task (ambiguous domain boundary, uncertain incumbent fit), default to FULL proposal. "The cost of an unnecessary proposal is lower than the cost of suppressing a legitimate choice." The classifier produces an explicit output token: `Trigger: FULL` or `Trigger: SKIP`.

### D-14: Concrete Return-to-Source Escape Sequence (Developer)
The reworked skill includes a named sub-section "Changing the Stack During Implementation" with 6 explicit steps: (1) Stop /dr-do work, (2) Record concrete reason, (3) Return to /dr-plan or /dr-prd, (4) Revise ADR via proposal mechanism, (5) Operator approves, (6) Resume /dr-do with updated ADR. This prevents agents from either ignoring the binding or over-applying it.

### D-15: Verifiable "When to Reconsider" Litmus Tests (Developer)
Each "When to Reconsider" entry pairs with a simple, falsifiable litmus test. Example: instead of "Complex data grids," write "More than 5 distinct table views with sorting, filtering, and inline editing." Without verifiable triggers, agents either always reconsider (proposal inflation) or never reconsider (de-facto prescription).

## Failure Mode Table

| What Can Fail | Probability | Impact | Detection | Mitigation |
|--------------|-------------|--------|-----------|------------|
| Agent classifies cross-domain component as same-domain, skips proposal | Medium | High — operator never sees alternatives | bats test T2; /dr-qa Layer 3b verifies trigger classification | Domain-axis heuristic baked into classifier step description; structured output (trigger_result: full/skip) visible to downstream verification |
| Default Recommendation column becomes de-facto prescription again | Medium | Medium — same defect, softer framing | Time-based: no mechanism catches this automatically | "When to Reconsider" column is structurally present; /dr-qa Layer 3 can sample proposal presence on new-project tasks |
| Operator not ready at PRD time, defers choice, proposal never re-fires at plan | Low | Medium — stack chosen by agent default | /dr-plan verifies ADR presence; missing → re-fires proposal | Default-fallback documented in template: "Defaulting to <prescribed-stack> per framework standard. Revisit at /dr-plan." |
| Agent proposes insecure stack, operator approves via checkbox | Medium | High — production runs on vulnerable foundation | Security factor in template; live audit checkpoint at plan time | Security factor is mandatory in proposal; `/dr-plan` Step 11 live audit gate catches dependency-level CVEs |
| CVE in chosen stack during /dr-do, agent blocked by immutability | Low | High — implementation stalls during emergency | Security-emergency fast-track documented; agent knows the path | Fast-track: CVSS 9+ or KEV suspends binding; agent may switch with written notice |
| Five new domains shipped without security guidance | High (near-certain) | Medium — operators inherit blind spots | Security Agent condition #4: evolution proposal in reflection | Deferred to follow-up task; tech-stack rows note "security guidance for this domain is framework-minimal — consult domain-specific hardening references" |
| ADR bloat: every L3+ task produces standalone ADR for obvious choices | Low (mitigated by decision-note format) | Low — document clutter | Plan § Decisions format is inline, not standalone | Decision note (not ADR file); sticky choices prevent N copies of the same choice |
| Toolchain section becomes rigid-default problem at smaller scale | Low (architect dissent — monitoring) | Low — toolchains genuinely are ecosystem consensus | Reflection records dissent; operator can observe in practice | Deferred to follow-up task if evidence materializes |

## Consilium Verdict

**Approach C is confirmed with modifications.** The consilium panel (5/5 conditional support, 0 oppose) validates the core mechanism but identifies specific design gaps that must be closed before implementation:

1. **Add Security posture** as mandatory factor #8 in the proposal template (Security)
2. **Add Escape velocity** as factor #9 (Architect)
3. **Separate candidate ordering from recommendation** — no positional "Recommended" (Architect)
4. **Add security-emergency fast-track** to immutability contract (Security)
5. **Split pipeline placement**: PRD optional, Plan primary (Planner)
6. **Add stack-migration trigger** to classifier (Planner)
7. **Add sticky choices / child-task inheritance** (Planner)
8. **Record choice as decision note, not standalone ADR** (Strategist, Planner)
9. **Note backend-standards.md boundary** in tech-stack file (Architect)
10. **Add domain-axis heuristic** to trigger classifier (Architect)
11. **Record toolchain dissent** in reflection for future evaluation (Architect)

**Strategist's cheaper alternative (three-column table only, no proposal mechanism) is incorporated as the floor** — it ships as the minimum fix in Phase 1a, with the proposal mechanism shipping as a conditional overlay in Phase 1b. This satisfies the strategist's concern about over-engineering while retaining the mechanism for non-routine cases.

## Implementation Plan

The consilium results feed back into the plan (TUNE-0530-plan.md) as design refinements. The phased breakdown from the plan remains valid; the specific modifications are:

- P1 (Rework tech-stack): incorporate D-1, D-4, D-5, D-10, D-12
- P2 (Gate): incorporate D-11
- P3 (Commands): incorporate D-3, D-9
- P4 (Agents): no change from plan
- P5 (Tests): extend T1 to include security factor and escape velocity; extend T2 to include stack-migration trigger and domain-axis heuristic cases
- P6 (Dry-run): no change from plan
- P7 (Docs): no change from plan
