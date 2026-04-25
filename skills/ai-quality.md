---
name: ai-quality
description: Five pillars of AI-assisted development — decomposition, TDD, architecture-first, focused work, context. Method size limits, DoD, stubbing.
---

# AI Quality & Best Practices

> **TL;DR:** These 5 pillars guide AI-assisted development. Apply them consistently for 30-50% better code quality and 40-50% fewer bugs.

## THE 5 PILLARS OF QUALITY AI DEVELOPMENT

### 1. DECOMPOSITION (Rules #1, #3, #9)
> **Break complex tasks into small, focused units.**

```
KEY LIMITS:
|- Max 50 lines per method
|- Max 7-9 objects in working memory
|- One responsibility per function
```

**Why:** AI loses focus with complexity. Small units = better output.

---

### 2. TEST-FIRST (Rules #2, #5, #6)
> **Tests are hallucination filters. Mock edges, not logic.**

```
SEQUENCE:
1. Write tests BEFORE code
2. Define "done" explicitly (DoD)
3. Cover corner cases upfront
4. STRICT mocking: edges only, NO data fitting
```

**Why:** Tests catch AI mistakes. No tests = no safety net.

---

### 3. ARCHITECTURE-FIRST (Rules #7, #8)
> **Approve structure before coding.**

```
APPROACH:
1. Create skeleton with stubs
2. Review architecture
3. Implement one method at a time
```

**Why:** Bad architecture = wasted work. Validate first.

---

### 4. FOCUSED WORK (Rules #10, #11, #12)
> **Narrow context improves quality.**

```
PRACTICES:
|- Review one method at a time
|- Define clear boundaries (what we DON'T do)
|- Verify AI can solve before starting
|- Wire ALL planned features in first pass — if code/prompts are ready
   and wiring is <30 min, do it. "Low risk deferral" is still deferral.
|- Authorization prompts to user: 1 sentence risk + 1 yes/no question.
   Threat models → docs, not interactive prompt.
```

**Why:** Broad context = scattered results. Focus = precision.
Source (auth UX): LTM-0001 — user requested simpler prompts after a 7-option authorization table.
Source (wire-all): LTM-0008 — dedup/rerank deferred as "low risk", user challenged, wiring took <15 min.

---

### 5. CONTEXT MANAGEMENT (Rules #4, #13, #14, #15)
> **Right information at right time.**

```
ELEMENTS:
|- Gather requirements BEFORE coding
|- Document transaction isolation needs
|- Structure datarim hierarchically
|- Engineer prompts carefully
```

**Why:** Bad context = bad output. Quality in = quality out.

---

## STAGE-RULE MAPPING

Load only the rules relevant to your current stage:

| Stage | Rules to Apply | Focus |
|-------|---------------|-------|
| **/dr-init** | #4 Requirements, #12 Complexity | Is the task well-defined? Can AI solve it? |
| **/dr-plan** | #1 Stubbing, #5 DoD, #6 Corner Cases, #7 Skeleton, #11 Boundaries | Decompose, define scope and done criteria |
| **/dr-design** | #6 Corner Cases, #7 Skeleton, #9 Cognitive Load, #13 Transactions | Design quality, keep it simple |
| **/dr-do** | #2 TDD, #3 Method Size, #8 Iterative, #9 Cognitive Load | Write tests first, small methods, one at a time |
| **/dr-qa** | #5 DoD verification, #10 Focused Review | Review one method at a time, check done criteria |
| **/dr-archive** | #8 Iterative verification + #10 Review (Step 0.5 reflection), #14 Structure (Step 2 archive doc) | Was the process followed? Hierarchical summaries for future context |

---

## QUICK RULE REFERENCE

| # | Rule | One-Liner |
|---|------|-----------|
| 1 | Stubbing | Break into 50-line stubs |
| 2 | TDD | Tests before code (Strict Mocking) |
| 3 | Method Size | Max 50 lines, 7-9 objects |
| 4 | Requirements | Context before coding |
| 5 | DoD | Explicit done criteria |
| 6 | Corner Cases | List boundaries first |
| 7 | Skeleton | Architecture before code |
| 8 | Iterative | One method at a time |
| 9 | Cognitive | 7+/-2 objects max |
| 10 | Review | Review one method only |
| 11 | Boundaries | State what's out of scope |
| 12 | Complexity | Verify AI can solve |
| 13 | Transaction | Explicit isolation levels |
| 14 | Structure | Hierarchical summaries |
| 15 | Prompts | Structured prompt creation |

---

## QUALITY CHECKPOINT

Before proceeding, ask:

```
[ ] Is this task decomposed into small units?
[ ] Do I have tests/DoD defined?
[ ] Is the architecture approved?
[ ] Am I focused on one thing?
[ ] Do I have the right context?
```

**If NO to any:** Stop and address before coding.

---

## COMMON MISTAKES

### DON'T
- Write code before tests
- Create methods > 50 lines
- Track > 9 objects per method
- Review entire features at once
- Start without clear requirements
- Skip corner case analysis

### DO
- Tests -> Code -> Review -> Next
- Keep methods small and focused
- One method at a time
- Define boundaries explicitly
- Document requirements upfront

---

## Spec-First with Golden Fixtures (Format-Change Pattern)

When a task changes **output format, structure, or contract across multiple files** (e.g. CTA blocks across 17 commands + 5 agents, response envelopes across N services, log fields across handlers), apply this pattern as a default rule for L3+ tasks:

```
SEQUENCE:
1. Spec-as-skill        → write the canonical specification first as a single
                          source-of-truth skill (e.g. cta-format.md). Define
                          structure, field rules, anti-patterns.
2. Golden fixtures      → create one fixture per variant (single, multi,
                          fail-routing, etc.) under tests/{topic}/fixtures/.
                          These are the visual artefacts agents produce.
3. Spec-regression tests → bats / language-native tests verify:
                          (a) every consumer file references the skill
                          (b) every consumer agent loads the skill
                          (c) fixtures match all spec invariants
                          (d) anti-pattern guards (forbidden chars, etc.)
4. Mechanical propagation → only after 1-3 land, propagate the change to all
                          consumers. Tests guard against drift.
```

**Why:** Without fixtures + tests, the same drift problem re-emerges every time a new consumer is added without spec compliance. Mechanical propagation alone protects current state, not future state.

**When to apply:**
- Format / structure changes affecting ≥5 files of the same kind
- Output-contract changes (CTA, response envelope, log fields, validation messages)
- Cross-cutting style / convention changes that need agent compliance

**When NOT to apply:**
- Single-file changes
- Internal-only refactors with no external contract
- One-off scripts where future drift is not a concern

Source: TUNE-0032 — Approach C (Spec-First with Golden Fixtures) chosen over Approach A (Big Bang refactor) for canonical CTA block. 39 tests now guard 17 commands + 5 agents from drift; mechanical sweep alone (Approach A) would have left the same problem to re-emerge with the next added command.

---

## Fragment Routing

Load only the fragment needed for the current sub-problem:

- `skills/ai-quality/incident-patterns.md`
  Use when adding safety guards, reviewing integration failure attribution, or making scope decisions for untracked files.
- `skills/ai-quality/deployment-patterns.md`
  Use when deploying services (Docker, venv, NestJS DI, CLI connectors in containers).

---

*These principles reduce bugs by 40-50% and improve code quality by 30-50%.*
