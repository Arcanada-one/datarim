# Pipeline Stages — Detailed Reference

## Overview

Datarim's pipeline consists of 9 stages. Not all stages run for every task — complexity level determines the route.

```
init → prd → plan → design → do → qa → compliance → reflect → archive
```

---

## Stage 1: /init — Task Initialization

**Agent:** Planner
**Purpose:** Create a new task, assess its complexity, set up `datarim/` if needed.

**What happens:**
1. Analyze the user's task description
2. Determine complexity level (L1-L4) based on scope, files, and architecture impact
3. Create/update `datarim/tasks.md` and `datarim/activeContext.md`
4. If `datarim/` doesn't exist, create it (this is the only command that may do so)

**Routing after init:**
- L1 → `/do`
- L2+ → `/prd` or `/plan`

---

## Stage 2: /prd — Product Requirements Document

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

## Stage 3: /plan — Implementation Planning

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

## Stage 4: /design — Architecture Exploration

**Agent:** Architect
**Purpose:** Explore and document architectural decisions (L3-4 only).

**What happens:**
1. For L3-4: Consilium panel — multi-agent discussion with conflict resolution
2. Creative exploration with tradeoff matrices
3. Priority Ladder resolution
4. Architecture Decision Records (ADRs)
5. Output: `datarim/creative/creative-{id}-{name}.md`

---

## Stage 5: /do — TDD Implementation

**Agent:** Developer
**Purpose:** Implement the plan using Test-Driven Development.

**What happens:**
1. Load implementation plan from `datarim/tasks.md`
2. TDD loop: Write test → Fail → Code → Pass
3. Implement one method/stub at a time
4. Follow project patterns and style guide
5. Update `datarim/progress.md`

---

## Stage 6: /qa — Quality Assurance

**Agent:** Reviewer
**Purpose:** Multi-layer verification of the implementation.

**Verification layers (based on available artifacts):**
1. PRD Alignment — implementation matches requirements?
2. Design Conformance — architectural decisions respected?
3. Plan Completeness — all steps completed?
4. Code Quality — tests pass, security, anti-patterns?

**Verdicts:** PASS | PASS_WITH_NOTES | FAIL

---

## Stage 7: /compliance — Post-QA Hardening

**Agent:** Compliance
**Purpose:** 7-step hardening workflow.

**Steps:**
1. Change set vs PRD/task alignment
2. Code simplification (recently modified code only)
3. References and dead code check
4. Test coverage verification
5. Linters and formatters
6. Test execution
7. CI/CD impact analysis

---

## Stage 8: /reflect — Lessons Learned + Evolution

**Agent:** Reviewer
**Purpose:** Document lessons and propose framework improvements.

**What happens:**
1. Review completed task against Definition of Done
2. Document what worked, what didn't, lessons learned
3. **Evolution step:** Analyze insights, propose framework updates
4. Present proposals to user for approval
5. Log approved changes in `datarim/docs/evolution-log.md`

---

## Stage 9: /archive — Task Completion

**Agent:** Planner
**Purpose:** Archive the task and reset for the next one.

**What happens:**
1. Create archive document with full task summary
2. Move task from `backlog.md` to `backlog-archive.md`
3. Reset `activeContext.md`
4. Clear completed items from `tasks.md`

---

## Utility Commands

### /status
Read-only check of current task, progress, and backlog.

### /continue
Resume work from the last checkpoint. Reads `activeContext.md` to determine current phase and routes to the appropriate stage.
