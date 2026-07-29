---
task_id: TUNE-0530
artifact: prd
schema_version: 1
captured_at: 2026-07-29
captured_by: /dr-prd
agent: architect
status: canonical
ships_in: 2.59.0
prd_parent: TUNE-0530
---

# PRD-TUNE-0530 — Rework Stack Selection: From Prescribed Stacks to Justified Proposals

> **Status:** canonical · **Agent:** architect · **Complexity:** L3
> **Research:** INSIGHTS-TUNE-0530 (to be created at `/dr-do` research phase)

## Problem Statement

`skills/tech-stack/SKILL.md` prescribes a single mandatory stack per project type under the heading **"Project Type → Required Stack"** (lines 65-131). There are no alternatives, no trade-offs, and no decision surface. The operator never sees a choice. Systems languages (Rust, Go) are entirely absent from the table — despite being in production across the Arcanada ecosystem (Disk Arcana in Rust, ARAS in Rust, Cubrim in Rust, RTK in Rust).

The **stack-agnostic gate** (`skills/evolution/stack-agnostic-gate.md`) forbids naming concrete technologies in skills, yet `tech-stack/SKILL.md` is whitelisted in its entirety (gate line 61: "explicitly stack-aware by design"). The exemption is coherent on its own terms — tech-stack *is* the designated stack-aware file — but the prescriptive content it protects is the very defect this PRD addresses.

A real case exposed the defect concretely: the Control Arcana redesign. An agent concluded "no MUI" on the false premise that MUI is a paid component (it is not — MUI is MIT-licensed; the purchased artefact is the Minimals.cc template built on top of it). The framework had no mechanism to surface "Tailwind vs MUI" as a decision with trade-offs. The agent defended the incumbent because the table said Tailwind, and a legitimate architectural question never reached the operator.

**The target outcome is informed operator choice at PRD/plan time** — not a different set of hardcoded defaults. Replacing one prescription with another is a failed outcome.

## Scope

### In Scope

1. **Audit** every surface where Datarim prescribes a concrete stack (file:line, who loads it, what happens on deviation)
2. **Design** a replacement mechanism that produces 2-3 viable candidate stacks with explicit trade-offs and a recommendation at PRD/plan time
3. **Implement** the rework: `skills/tech-stack/`, wiring into `/dr-prd` and `/dr-plan`, agent loading updates
4. **Add missing domains**: cross-platform CLI/desktop, systems services, data/ML pipelines
5. **Resolve** the stack-agnostic-gate contradiction coherently
6. **bats tests** asserting wiring and required proposal shape (alternatives + rationale + recommendation)
7. **Validation dry-run** against the Control Arcana case (Tailwind vs MUI)
8. **Decision-making method** reference: ADR template, weighted-criteria scoring, technology-radar quadrant

### Out of Scope

- Redesigning Control Arcana or any existing project
- Migrating any existing project to a new stack
- Rewriting `documentation/architecture/backend-stack-standards.md` (separate ecosystem mandate — spawn child task if change is warranted)
- Changing the stack-agnostic gate denylist/whitelist mechanism itself (only the tech-stack exemption's rationale may be updated)
- Adding stack-specific scaffolds for new domains

## Context Analysis — Audit of Prescription Surfaces

### Primary Prescription Surface: `skills/tech-stack/SKILL.md`

| Lines | Content | Nature |
|-------|---------|--------|
| 10 | "select the tech stack STRICTLY based on project type. No guessing, no inventing, no asking." | Prescriptive mandate |
| 65 | Section heading: "Project Type -> Required Stack" | Prescription framing |
| 71-74 | Frontend rows: Static Landing (HTML+Tailwind+Alpine), Web Frontend SEO (Next.js+React+Tailwind+shadcn/ui+Vite), SPA/Dashboard (Vite+React or Vue+Tailwind+TanStack Query) | Single-stack prescription |
| 78-83 | Backend rows: Microservice API (Nest.js+Fastify MANDATORY+PostgreSQL+Prisma+Redis+NATS), High-Load (Node.js+Fastify), Python API (FastAPI+uv+ruff), API Gateway (Node.js+Fastify+Zod+OpenAPI) | Single-stack prescription |
| 87-91 | AI/ML rows: AI/LLM API (Python+FastAPI+uv+ruff+OpenAI/OpenRouter SDK+Redis), AI Pipelines/RAG (Python+FastAPI+uv+ruff+LangChain/LlamaIndex+pgvector/Qdrant+Redis) | Single-stack prescription |
| 95-98 | Real-time rows: Chat (Node.js+Socket.IO or ws+Redis), Audio/Video (Node.js+WebRTC+mediasoup/LiveKit+Redis), WebSockets-Only (Node.js+ws or uWebSockets.js+Redis) | Single-stack prescription |
| 103-107 | Background/Event rows: Background Jobs (Python+FastAPI+Celery/Dramatiq+Redis/Kafka), Event-Driven (Nest.js or FastAPI+NATS/Kafka+OpenTelemetry) | Single-stack prescription |
| 109-113 | Media rows: File Processing (Python+FFmpeg+Celery+S3), Streaming (Node.js+WebRTC+mediasoup+FFmpeg+CDN) | Single-stack prescription |
| 118-122 | Platform rows: Monorepo (Nx+TypeScript+pnpm), Auth (Nest.js+Passport+JWT+OAuth2+Redis), Prototyping/MVP (Next.js+API Routes+PostgreSQL+Prisma) | Single-stack prescription |
| 133-152 | Mandatory Python toolchain (uv+ruff+pytest+mypy+pre-commit, FORBIDDEN: pip without uv, flake8/isort/black when ruff present) | Prescriptive toolchain |
| 154-174 | Mandatory Node/TypeScript toolchain (pnpm+TypeScript+eslint+prettier+vitest+playwright+tsup/swc+lefthook/husky) | Prescriptive toolchain |
| 210-220 | Architecture Rules (9 rules, mostly prescriptive: "Fastify > Express (always)", "Monorepo -> Nx") | Prescriptive rules |
| 221-230 | "Forbidden" list (7 items) | Prescriptive prohibitions |
| 239-245 | "Final Rule" — "Choose simplest valid stack from this document. Do NOT invent new stacks. Do NOT ask which stack to use. Apply rules automatically." | Explicit anti-choice mandate |

**Gap: systems languages entirely absent.** The word "Rust" appears zero times; "Go" appears zero times; "Zig" appears zero times; ".NET" appears zero times. There is no row for: cross-platform CLI tool, desktop application, systems daemon, embedded/edge service, or WASM module — despite the ecosystem shipping Rust in production.

### Wiring: Who Loads tech-stack

| File | Line | Context |
|------|------|---------|
| `agents/architect.md` | 30 | "When making technology decisions or designing architecture for new services" |
| `agents/devops.md` | 26 | "Stack selection guidance" |
| `agents/planner.md` | 32 | "When creating new project/service or selecting technology stack" |
| `agents/researcher.md` | 35 | "when evaluating technology choices" |
| `commands/dr-init.md` | 173 | "If new project/service: Load … tech-stack … and identify required stack" |

**Key finding:** `/dr-prd` and `/dr-plan` do NOT load tech-stack directly. The agents that serve those stages (architect, planner) load it individually. This means the stack proposal step must be wired into both the commands AND the agent personas.

### Stack-Agnostic Gate Contradiction

The gate (`skills/evolution/stack-agnostic-gate.md`) whitelists `skills/tech-stack/SKILL.md` at line 61 with the rationale: "explicitly stack-aware by design. The whole file is exempt; the gate skips it entirely."

**Assessment:** The exemption is coherent — tech-stack is the *designated* stack-aware file. The defect is not the exemption but the prescriptive content it protects. After this rework, tech-stack will remain stack-aware by design (it must, to give concrete recommendations), but its content will shift from prescription to guidance. The gate's whitelist entry should be updated to reflect the new rationale.

## Solution Exploration

### Approach A: Keep the Table, Add an "Alternatives" Column

Expand each row with an "Alternatives & Trade-offs" column. Keep the primary recommendation as the first column.

**Pros:** Minimal change; backward-compatible; agents still get a default.
**Cons:** Table still reads as prescription; no mechanism for surfacing the decision to the operator; the "alternatives" column would be read as secondary by agents.

**Verdict:** Rejected. Does not achieve the target outcome (informed operator choice).

### Approach B: Replace the Table with a Decision-Making Method + Reference Catalog

Remove the prescriptive table entirely. Replace with:
1. A **decision method** (trigger detection → candidate generation → trade-off analysis → recommendation → operator choice → ADR recording)
2. A **reference catalog** of domains × viable stacks with evidence tables (not prescriptions)
3. **Wired proposal step** in `/dr-prd` and `/dr-plan`

**Pros:** Achieves the target outcome; separates method from data; the catalog can be updated independently.
**Cons:** Larger change; agents lose the "just pick this" shortcut for trivial cases.

**Verdict:** Selected with refinement (Approach C below).

### Approach C (Recommended): Guidance-First Table + Proposal Step + Defaults for Routine Work

A hybrid that preserves the table as **guidance with defaults** (not prescriptions), adds a **trigger mechanism** for when to run the full proposal, and wires a **proposal step** into `/dr-prd` and `/dr-plan`. The key structural change:

1. **The table becomes a "Starting Points" reference** — each row names a *default recommendation* plus *viable alternatives* with short trade-off notes. The framing shifts from "Required Stack" to "Starting Point & Alternatives."
2. **A trigger classifier** determines whether the question is worth asking: new project/service → always ask; new component in an existing project → ask if the incumbent stack is a poor fit per defined signals; routine CRUD endpoint in an existing service → default to incumbent, no proposal.
3. **The proposal step** (wired into `/dr-prd` Step 2+ and `/dr-plan` Step 4+) generates 2-3 candidates with trade-offs and a recommendation. The operator chooses; the choice is recorded as an ADR in the plan/PRD and bound by the immutability contract.
4. **New domains** (cross-platform CLI/desktop, systems services, data/ML pipelines) get rows with Rust and Go as first-class options.
5. **Architecture choices** (monolith vs services, SSR vs SPA, sync vs event-driven, SQL vs document) join the proposal scope — they are stack-adjacent decisions the operator should see alongside library choices.
6. **The stack-agnostic gate exemption** is updated to reflect the new rationale: tech-stack remains whitelisted because it is the *designated guidance file for technology selection*, not because it prescribes mandatory stacks.

## Technical Approach

### 1. Rework `skills/tech-stack/SKILL.md`

**Structural change:**

- Replace the `## Project Type -> Required Stack` heading and prescriptive framing with `## Starting Points & Alternatives`.
- Each domain row becomes:
  ```
  | Domain | Default Recommendation | Viable Alternatives | When to Reconsider |
  |--------|----------------------|--------------------|--------------------|
  | SPA / Dashboard | Vite + React + Tailwind + TanStack Query | MUI + Emotion, Mantine, shadcn/ui + Radix | Complex data grids, enterprise admin, design-system requirement |
  ```
- The "Default Recommendation" is guidance, not mandate. The "When to Reconsider" column defines triggers.
- **Mandatory toolchains** (Python: uv+ruff+pytest; Node: pnpm+TypeScript+eslint+prettier+vitest) remain as *strong defaults* — these are ecosystem-consensus tooling choices, not stack prescriptions, and they serve a different purpose (quality floor, not architecture choice). Rename to "Recommended Toolchains" and soften FORBIDDEN to "Prefer X over Y unless…".
- **Architecture Rules** (lines 210-220) move to a separate `## Architecture Guidance` section with rationale per rule, not just "X > Y (always)."

**New domains to add:**

| Domain | Default Recommendation | Viable Alternatives | When to Reconsider |
|--------|----------------------|--------------------|--------------------|
| Cross-Platform CLI | Go + Cobra | Rust + clap, Zig | Performance-critical, ultra-low binary size, C-interop needed |
| Desktop Application | Tauri (Rust) + React | Go + Fyne, Electron | Web-tech vs native look, bundle-size budget, platform-specific features |
| Systems Daemon / Service | Rust + tokio | Go + standard library, Zig | Team Rust fluency, GC-pause tolerance, rapid-prototyping priority |
| Data / ML Pipeline | Python + FastAPI + Celery | Go + temporal.io, Rust + rayon | Throughput-critical, memory-bound, GPU-orchestration needed |
| WASM Module | Rust + wasm-bindgen | Go (tinygo), Zig | Host-runtime constraints, binary-size floor, JS-interop complexity |

### 2. Stack Proposal Step in `/dr-prd` and `/dr-plan`

**Trigger classifier** (invoked at PRD Step 2 / Plan Step 4):

| Signal | Action |
|--------|--------|
| New project or service scaffold | Full proposal required |
| New component whose domain differs from the incumbent stack | Full proposal required |
| Operator explicitly requests ("compare X vs Y for Z") | Full proposal required |
| Bug fix, minor feature, same-domain addition to existing project | Skip; use incumbent |

**Proposal shape** (mandatory structure when triggered):

```markdown
## Stack Proposal for {Component}

### Context
{1-2 sentences: what is being built, key constraints}

### Candidate Stacks

#### Candidate 1: {Stack Name} (Recommended)
| Factor | Assessment |
|--------|-----------|
| Fit for domain | {rationale} |
| Ecosystem maturity | {evidence} |
| Team/AI familiarity | {assessment} |
| Performance profile | {assessment} |
| Licence & cost | {assessment} |
| Bundle/runtime cost | {assessment} |
| Operational fit (Arcanada) | {coherence with existing ecosystem} |

#### Candidate 2: {Alternative Name}
{same structure}

#### Candidate 3: {Alternative Name} (if applicable)
{same structure}

### Trade-off Summary
{1-paragraph synthesis of the key differentiators}

### Recommendation
{Agent's recommendation with rationale}

### Operator Decision
- [ ] Candidate 1 (Recommended) — {short label}
- [ ] Candidate 2 — {short label}
- [ ] Candidate 3 — {short label}
- [ ] Other (operator specifies)
```

**Architecture choices** included in the proposal scope:
- Monolith vs services (when the scope crosses service boundaries)
- SSR vs SPA (for frontend projects)
- Sync vs event-driven (for backend projects with async requirements)
- SQL vs document store (for data-persistence projects)

These are surfaced as a sub-section of the proposal, not a separate document.

### 3. Recording and Binding the Operator's Choice

- The chosen stack is recorded in the PRD/plan document with an **ADR header**: `## ADR-{N}: Technology Stack for {Component}`.
- The ADR references the proposal, records the operator's choice, and cites the rationale.
- The **immutability contract** (`skills/immutability/SKILL.md`) binds the choice downstream: changing the stack mid-implementation requires a Return-to-Source transition (return to PRD/plan, revise the ADR).
- `/dr-qa` Layer 3b verifies that the implemented stack matches the ADR.

### 4. Resolving the Stack-Agnostic Gate Contradiction

**Current state:** `tech-stack/SKILL.md` is whitelisted entirely (gate line 61). The rationale is "explicitly stack-aware by design."

**After rework:** The whitelist entry remains — `tech-stack/SKILL.md` is still the designated stack-guidance file. The rationale is updated to: "`skills/tech-stack/SKILL.md` — designated technology guidance file; names concrete technologies to give actionable recommendations while presenting alternatives and trade-offs rather than single mandated answers."

**No change to the gate mechanism itself.** The whitelist precedent system stands; only the rationale for this specific entry is updated.

### 5. Agent Loading Updates

| File | Current | After |
|------|---------|-------|
| `agents/architect.md:30` | "When making technology decisions or designing architecture for new services" | "When making technology decisions or designing architecture for new services — generates stack proposals with alternatives and trade-offs" |
| `agents/planner.md:32` | "When creating new project/service or selecting technology stack" | "When creating new project/service or selecting technology stack — produces candidate options, not a single mandated answer" |
| `commands/dr-prd.md` | No tech-stack reference | Add Step 2+: trigger classifier + stack proposal generation |
| `commands/dr-plan.md` | No tech-stack reference | Add Step 4+: trigger classifier + stack proposal generation (or verify ADR from PRD) |

### 6. Decision-Making Method Reference

The reworked `tech-stack/SKILL.md` includes a `## Decision-Making Method` section:

- **ADR template** — lightweight YAML frontmatter ADR for recording stack choices (title, status, context, decision, consequences)
- **Weighted-criteria scoring** — a simple 1-5 scale across the standard factors (fit, maturity, familiarity, performance, licence, coherence) with explicit weights; the total is indicative, not algorithmic
- **Technology-radar quadrant** — adopt/assess/trial/hold classification for ecosystem-level posture; the reference catalog uses these labels per domain
- **Escape velocity** — how hard it is to migrate away from the choice later (lock-in, portability, skill availability)

## Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Agents ignore the proposal step and default to the table's first column | High | Wire the trigger check into `/dr-prd` and `/dr-plan` as a mandatory step; bats test asserts proposal presence when trigger fires |
| The new mechanism adds ceremony to routine work | Medium | The trigger classifier skips the full proposal for routine cases; the table still provides a default recommendation |
| The "Default Recommendation" column becomes a de-facto prescription again | Medium | The "Viable Alternatives" and "When to Reconsider" columns are structurally present in every row; agents are instructed to read all three |
| Rust/Go rows are added but agents lack expertise to evaluate them | Medium | The reference catalog includes evidence; the proposal step requires explicit factor-by-factor assessment; AI models in 2026 have broad Rust/Go familiarity |
| `backend-stack-standards.md` diverges from reworked tech-stack | Low | Separate ecosystem mandate — flag in PRD risks section; spawn child task if divergence is material |

## Success Criteria

### D-REQ-1: Audit Completeness

**V-AC-1:** Every stack-prescribing line in `skills/tech-stack/SKILL.md` is catalogued with file:line, prescription text, and proposed replacement.
Covers: D-REQ-1
Evidence: audit table in PRD § Context Analysis (above)

### D-REQ-2: Mechanism Design

**V-AC-2:** The reworked `skills/tech-stack/SKILL.md` contains:
- (a) A "Starting Points & Alternatives" table with ≥3 columns per row (Default, Alternatives, When to Reconsider)
- (b) New rows for: cross-platform CLI, desktop application, systems daemon/service, data/ML pipeline, WASM module
- (c) A "Decision-Making Method" section referencing ADR template, weighted criteria, and technology-radar classification
- (d) Rust and Go present as first-class options in ≥3 rows each
Covers: D-REQ-2
Evidence: `grep -c` on the reworked file; manual review of new rows

### D-REQ-3: Wiring into PRD and Plan

**V-AC-3:** `/dr-prd` command file references the stack-proposal step with a trigger classifier; `/dr-plan` command file references the stack-proposal step or ADR-verification step.
Covers: D-REQ-3
Evidence: `grep -n "stack.proposal\|tech-stack\|trigger.classifier" commands/dr-prd.md commands/dr-plan.md` returns ≥1 hit per file

### D-REQ-4: Agent Loading Updates

**V-AC-4:** `agents/architect.md` and `agents/planner.md` tech-stack loading lines are updated to reflect the guidance-not-prescription framing.
Covers: D-REQ-3
Evidence: `grep -n "tech-stack" agents/architect.md agents/planner.md` shows updated descriptions

### D-REQ-5: Stack-Agnostic Gate Coherence

**V-AC-5:** The whitelist entry for `tech-stack/SKILL.md` in `skills/evolution/stack-agnostic-gate.md` is updated with rationale reflecting the reworked guidance nature.
Covers: D-REQ-2
Evidence: `grep -A2 "tech-stack" skills/evolution/stack-agnostic-gate.md` shows updated rationale

### D-REQ-6: bats Tests — Wiring

**V-AC-6:** A bats test asserts that a stack proposal emitted for a new-project trigger contains the mandatory sections: Context, ≥2 Candidate Stacks with factor assessments, Trade-off Summary, Recommendation, Operator Decision checklist.
Covers: D-REQ-3
Evidence: `bats tests/` — test file with name matching `*stack-proposal*` or `*tech-stack*`; test asserts `grep -q "Candidate 1"` and `grep -q "Operator Decision"` on proposal output

### D-REQ-7: bats Tests — Trigger Behaviour

**V-AC-7:** A bats test asserts that the trigger classifier returns "skip" for routine same-domain work and "full" for new-project/scaffold work.
Covers: D-REQ-3
Evidence: `bats tests/` — test file exercising the trigger classifier function

### D-REQ-8: Validation Dry-Run

**V-AC-8:** A dry-run applying the new mechanism to the Control Arcana case (React + Tailwind vs MUI + Emotion for an admin dashboard) produces ≥2 candidate stacks with explicit trade-offs, demonstrating that the prescriptive old mechanism would not have surfaced the choice.
Covers: D-REQ-2, D-REQ-3
Evidence: dry-run section in archive or compliance report

### D-REQ-9: Immutability Binding

**V-AC-9:** The reworked skill documents that a stack choice recorded in a PRD/plan ADR is bound by the immutability contract; changing it mid-implementation requires a Return-to-Source transition.
Covers: D-REQ-2
Evidence: `grep -n "immutability\|ADR\|Return-to-Source\|binding" skills/tech-stack/SKILL.md` returns ≥1 hit

### D-REQ-10: Documentation and Visual Maps

**V-AC-10:** The decision-tree diagram in `skills/tech-stack/SKILL.md` § Stack Selection Decision Tree is updated to reflect the new trigger-classifier flow (not the old "pick from table" flow). Any visual-map references are updated.
Covers: D-REQ-2
Evidence: Mermaid diagram in the reworked file contains a node for trigger classification or proposal generation.

---

## Research Summary (abridged — full in INSIGHTS-TUNE-0530)

### Frontend: Tailwind vs MUI vs shadcn/ui vs Mantine

For **data-dense admin dashboards** (the Control Arcana case), Mantine wins on completeness — it ships a free data table (`mantine-datatable`), 60+ hooks, first-class dark mode, and form management in one dependency. MUI + MUI X has the best data grid but the Pro tier is paid ($14/dev/mo). shadcn/ui gives full design control but requires assembling 8+ separate packages. Tailwind alone is rarely the right choice for dashboards.

For **content-heavy marketing sites**, Tailwind + Astro or plain HTML wins on bundle size and SEO. The current table is not wrong to recommend Tailwind for static sites — but it's wrong to not mention the dashboard-vs-content distinction.

### Meta-Frameworks: Next.js vs Remix vs Astro vs SvelteKit

Next.js remains the safe general-purpose choice with the most rendering modes (SSG+SSR+ISR+PPR) and largest ecosystem. Astro dominates content sites (zero JS by default). Remix/React Router v7+ offers the simplest mental model for CRUD-heavy apps. SvelteKit wins on developer satisfaction and bundle size. The choice depends on the *type* of frontend — not just "SEO or not."

### Systems Languages: Rust vs Go vs Zig

Go wins on development velocity and cross-compilation simplicity (`GOOS/GOARCH`). Rust wins on memory safety guarantees and performance ceiling. Zig wins on binary size and cold-start latency but lacks mature ecosystem. For CLI tools: Go (Cobra) for speed-to-ship, Rust (clap) for correctness. For desktop: Tauri (Rust) is the strongest option for cross-platform GUI.

### Backend: NestJS vs Fastify vs Hono vs Encore

Fastify wins on throughput; NestJS on team structure; Hono on edge deployment; Encore.ts on AI-agent productivity (36/36 production rubric at lowest cost in benchmarks). The ecosystem standard (`backend-stack-standards.md`) already mandates NestJS+Fastify+Prisma — this PRD does not override that.

### Decision Methods

**ADR** (Nygard 2011): lightest-weight, already in the framework vocabulary. **Weighted-criteria scoring:** a simple matrix with explicit weights makes trade-offs visible and challengeable. **Technology radar** (Thoughtworks adopt/trial/assess/hold): useful for ecosystem-level posture, less for per-project decisions. The recommended approach layers ADR (recording) + weighted criteria (analysis) with the radar quadrant as an ecosystem-level annotation on the reference catalog.
