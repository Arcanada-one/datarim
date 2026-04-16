---
name: ai-quality
description: Five pillars of AI-assisted development (decomposition, test-first, architecture-first, focused work, context). Use for TDD, stubbing, method size limits, DoD, and code quality decisions.
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
|- Authorization prompts to user: 1 sentence risk + 1 yes/no question.
   Threat models → docs, not interactive prompt.
```

**Why:** Broad context = scattered results. Focus = precision.
Source (auth UX): LTM-0001 — user requested simpler prompts after a 7-option authorization table.

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
| **/dr-reflect** | #8 Iterative verification, #10 Review | Was the process followed? |
| **/dr-archive** | #14 Structure | Hierarchical summaries for future context |

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

## INCIDENT-NARRATIVE IN SAFETY GUARDS

When adding a non-obvious safety control (confirmation prompts, destructive-flag guards, permission checks, rate limits), cite in the runtime message the **incident ID + one-line effect** that motivated the control. This turns the guard into its own documentation: the operator sees *why* at the moment it triggers, without needing to open docs or git history.

### Why

A silent guard (`"Confirm? [y/N]"`) teaches nothing. Operators either learn its rationale by accident — when it fires on their own mistake — or they bypass it because they don't understand it. Either path erodes the guard over time.

A narrated guard carries the original lesson forward. Future operators, LLM agents included, learn from the incident without reproducing it.

### Pattern

```bash
echo "WARNING: --force on a live system will overwrite $CLAUDE_DIR"
echo "         TUNE-0003 incident: --force previously destroyed 9 runtime evolutions."
```

Two lines. First states the *what* (effect of proceeding). Second states the *why* (incident that exists because someone already proceeded).

### Rules

1. **One incident per guard** — cite the *founding* incident, not a list. If the guard accretes history, the most-costly incident wins.
2. **Quantify the effect** when possible (files lost, hours spent, users affected). "Destroyed 9 runtime evolutions" is clearer than "caused problems".
3. **Cite by ID, not by date** — IDs (`TUNE-0003`, `DEV-1156`) index into archives; dates rot.
4. **Keep it to ≤ 2 lines** in runtime output. Long narratives belong in docs; this is a reminder, not a lecture.
5. **Update the reference when superseded** — if a later incident replaces the original justification, rewrite both the guard and the archive cross-reference. Do not layer old and new together.

### When to skip

- Guards for completely self-evident constraints (typing `yes` to confirm destructive action). The prompt itself is the narrative.
- Compile-time or lint-level guards that never reach a human at runtime.
- Guards with no user-visible output (internal invariant checks).

### Exemplar

`install.sh:115` (TUNE-0004) — `--force` live-system warning cites TUNE-0003 by ID and quantifies the cost (9 files). The guard fires before any filesystem mutation; the operator has context before making the decision, not after.

---

*These principles reduce bugs by 40-50% and improve code quality by 30-50%.*
