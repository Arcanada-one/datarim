# Pipeline Stages — Detailed Reference

## Overview

Datarim's pipeline consists of 8 stages. Not all stages run for every task — complexity level determines the route. Reflection is not a standalone stage — it runs automatically inside `/dr-archive` as mandatory Step 0.5 (v1.10.0, TUNE-0013).

```
init → prd → plan → design → do → qa → compliance → archive
```

> **Visual navigation:** Load `visual-maps.md` skill for mermaid diagrams of pipeline routing, stage flows, and agent-skill-command relationships.

---

## Stage 1: /dr-init 🔒 — Task Initialization (operator-only)

**Agent:** Planner
**Purpose:** Create a new task, assess its complexity, set up `datarim/` if needed.

> **🔒 Operator-only.** `/dr-init` carries `disable-model-invocation: true` in frontmatter and is intentionally invisible to the Skill tool. Agents must surface this stage as a slash-CTA for the operator; they must not invoke it through the Skill tool, and they must not spawn a subagent to create `datarim/` artefacts manually.


**What happens:**
1. Analyze the user's task description
2. Determine complexity level (L1-L4) based on scope, files, and architecture impact
3. Create/update `datarim/tasks.md` and `datarim/activeContext.md`
4. If `datarim/` doesn't exist, create it (this is the only command that may do so)

**Routing after init:**
- L1 → `/dr-do`
- L2+ → `/dr-prd` or `/dr-plan`

---

## Stage 2: /dr-prd — Product Requirements Document

**Agent:** Architect
**Purpose:** Gather requirements, explore solutions, get user approval.

**What happens:**
1. Context analysis — read existing code, identify constraints
2. Discovery interview — systematic questioning with proposed answers (mode based on complexity)
3. Solution brainstorming — generate 3+ distinct approaches
4. For L3-4: optional consilium panel review
5. User consultation — present alternatives, wait for approval
6. Generate PRD document in `datarim/prd/`

---

## Stage 3: /dr-plan — Implementation Planning

**Agent:** Planner
**Purpose:** Create a detailed implementation plan with security analysis.

**What happens:**
1. Analyze PRD and project context
2. Strategist gate (L3-4 mandatory): Value/Risk/Cost assessment
3. Component breakdown — list all modified and new files
4. Interface design — function signatures, API contracts
5. Security design — threat model, controls (Appendix A)
6. Implementation steps with code examples
7. Rollback strategy
8. Validation checklist

---

## Stage 4: /dr-design — Architecture Exploration

**Agent:** Architect
**Purpose:** Explore and document architectural decisions (L3-4 only).

**What happens:**
1. **Determine design type:** UI/UX, Architecture, Data Model, or Algorithm
2. For each component: define problem → explore 3+ options → analyze tradeoffs → decide
3. For L3-4: Consilium panel — multi-agent discussion with conflict resolution
4. Apply quality rules: #6 Corner Cases, #7 Skeleton, #9 Cognitive Load, #13 Transactions
5. Output: `datarim/creative/creative-{task_id}-{type}-{name}.md`

---

## Stage 5: /dr-do — Execution

**Agent:** Developer
**Purpose:** Implement the plan using Test-Driven Development.

**What happens:**
1. Load implementation plan from `datarim/tasks.md`
2. **Pre-flight check** (L3-L4 code tasks): verify plan exists, design docs complete, dependencies available, project builds
3. TDD loop: Write test → Fail → Code → Pass
4. Implement one method/stub at a time (apply rules #2, #3, #8, #9)
5. Follow project patterns and style guide
6. Update `datarim/progress.md`

**Note:** For content-focused tasks (articles, research, documentation), `/dr-write` replaces `/dr-do` as the execution stage.

---

## Stage 6: /dr-qa — Quality Assurance

**Agent:** Reviewer
**Purpose:** Multi-layer verification of the implementation.

**Verification layers (based on available artifacts):**
1. PRD Alignment — implementation matches requirements?
2. Design Conformance — architectural decisions respected?
3. Plan Completeness — all steps completed?
4. Code Quality — tests pass, security, anti-patterns?

**Verdicts:** PASS | PASS_WITH_NOTES | FAIL

---

## Stage 7: /dr-compliance — Post-QA Hardening

**Agent:** Compliance
**Purpose:** 7-step hardening workflow. Adaptive: detects the task type (code, content, research, documentation) and applies the appropriate checklist for that domain.

**Steps:**
1. Change set vs PRD/task alignment
2. Code simplification (recently modified code only)
3. References and dead code check
4. Test coverage verification
5. Linters and formatters
6. Test execution
7. CI/CD impact analysis

---

## Stage 8: /dr-archive 🔒 — Reflection + Task Completion (operator-only)

**Agents:** Reviewer (Step 0.5 reflection) + Planner (Steps 1-7 archive)
**Purpose:** Reflect on the task, archive it, reset for the next one.

> **🔒 Operator-only.** `/dr-archive` carries `disable-model-invocation: true` in frontmatter and is intentionally invisible to the Skill tool. After a COMPLIANT verdict from `/dr-compliance`, the compliance / planner agent MUST surface the slash-CTA for the operator and MUST NOT spawn a subagent to perform the archive manually — manual paths skip the schema gate, staged-diff audit (Step 0.1), prefix→subdir mapping, and Operator-Handoff section.


**What happens:**
0. Pre-archive clean-git check (mandatory gate)
0.5. **Reflect (mandatory, non-skippable)** — invokes `skills/reflecting.md`:
   - Review completed task against Definition of Done
   - Document what worked, what didn't, lessons learned → `datarim/reflection/reflection-{id}.md`
   - Generate evolution proposals (skill/agent/claude-md/template updates + new components)
   - Class A vs Class B classification per `skills/evolution.md`
   - Human approval gate for Class A; hold Class B until PRD update
   - Apply approved changes to runtime; log in `datarim/docs/evolution-log.md`
   - Health-metrics check; suggest `/dr-optimize` if thresholds exceeded
   - Collect follow-up-task list for Step 4
1. Archive-area determination (by task-ID prefix)
2. Create archive document with full task summary (embeds reflection insights)
3. Move task from `backlog.md` to `backlog-archive.md`
4. Follow-up-task entries from reflection → new backlog items
5. Update Archived Tasks table in `tasks.md`
6. Reset `activeContext.md`
7. Clear completed item from Active Tasks section of `tasks.md`

**Historical note:** Prior to v1.10.0 (TUNE-0013), reflection ran as a separate Stage 8 `/dr-reflect` command. It was consolidated into `/dr-archive` to eliminate the "mandatory gate disguised as optional" defect. The `/dr-reflect` command no longer exists.

---

## Utility Commands

### /dr-status
Read-only check of current task, progress, and backlog.

### /dr-continue
Resume work from the last checkpoint. Reads `activeContext.md` to determine current phase and routes to the appropriate stage.

---

## Content Commands

### /dr-write — Create Content
**Agent:** Writer
**Purpose:** Create written content — articles, blog posts, documentation, research papers, social media.

**What happens:**
1. Research and plan: gather sources, create outline
2. Draft: write from outline, one section at a time
3. Self-review: check structure, flow, naturalness
4. Mark sections needing editorial review

### /dr-edit — Editorial Review
**Agent:** Editor
**Purpose:** Fact-check, remove AI patterns, enforce style, polish to publication quality.

**What happens:**
1. Fact verification: extract claims, verify against sources
2. AI pattern removal: vocabulary, structure, formatting, linguistic patterns
3. Editorial polish: style consistency, cross-references, naturalness
4. Report changes for author approval

---

## Framework Management Commands

### /dr-addskill — Extend Framework
**Agent:** Skill Creator
**Purpose:** Research, design, and create new skills, agents, or commands.

### /dr-optimize — Framework Optimization
**Agent:** Optimizer
**Purpose:** Audit framework health, prune unused, merge duplicates, sync docs.

### /dr-dream — Knowledge Base Maintenance
**Agent:** Librarian
**Purpose:** Organize datarim/ directory — index, cross-reference, lint, consolidate.
