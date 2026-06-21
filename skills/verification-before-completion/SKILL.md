---
name: verification-before-completion
description: "Use before claiming work complete, fixed, or passing — and before committing or opening PRs. Run verification commands and confirm output first."
current_aal: 2
target_aal: 3
---

# Verification Before Completion

## Overview

Claiming work is complete without verification is dishonesty, not efficiency.

**Core principle:** Evidence before claims, always.

**Violating the letter of this rule is violating the spirit of this rule.**

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you haven't run the verification command in this message, you cannot claim it passes.

## The Gate Function

```
BEFORE claiming any status or expressing satisfaction:

1. IDENTIFY: What command proves this claim?
2. RUN: Execute the FULL command (fresh, complete)
3. READ: Full output, check exit code, count failures
4. VERIFY: Does output confirm the claim?
   - If NO: State actual status with evidence
   - If YES: State claim WITH evidence
5. ONLY THEN: Make the claim

Skip any step = lying, not verifying
```

## Common Failures

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| Tests pass | Test command output: 0 failures | Previous run, "should pass" |
| Linter clean | Linter output: 0 errors | Partial check, extrapolation |
| Build succeeds | Build command: exit 0 | Linter passing, logs look good |
| Bug fixed | Test original symptom: passes | Code changed, assumed fixed |
| Regression test works | Red-green cycle verified | Test passes once |
| Agent completed | VCS diff shows changes | Agent reports "success" |
| Requirements met | Line-by-line checklist | Tests passing |

## Red Flags - STOP

- Using "should", "probably", "seems to"
- Expressing satisfaction before verification ("Great!", "Perfect!", "Done!", etc.)
- About to commit/push/PR without verification
- Trusting agent success reports
- Relying on partial verification
- Thinking "just this once"
- Tired and wanting work over
- **ANY wording implying success without having run verification**

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Should work now" | RUN the verification |
| "I'm confident" | Confidence ≠ evidence |
| "Just this once" | No exceptions |
| "Linter passed" | Linter ≠ compiler |
| "Agent said success" | Verify independently |
| "I'm tired" | Exhaustion ≠ excuse |
| "Partial check is enough" | Partial proves nothing |
| "Different words so rule doesn't apply" | Spirit over letter |

## Key Patterns

**Tests:**
```
✅ [Run test command] [See: 34/34 pass] "All tests pass"
❌ "Should pass now" / "Looks correct"
```

**Regression tests (TDD Red-Green):**
```
✅ Write → Run (pass) → Revert fix → Run (MUST FAIL) → Restore → Run (pass)
❌ "I've written a regression test" (without red-green verification)
```

**Build:**
```
✅ [Run build] [See: exit 0] "Build passes"
❌ "Linter passed" (linter doesn't check compilation)
```

**Requirements:**
```
✅ Re-read plan → Create checklist → Verify each → Report gaps or completion
❌ "Tests pass, phase complete"
```

**Agent delegation:**
```
✅ Agent reports success → Check VCS diff → Verify changes → Report actual state
❌ Trust agent report
```

## Prototype-Patch Verification Gate

When a fix monkey-patches a shared runtime object (a class prototype, a module
export, an interpreter-level hook), test-runner evidence is structurally
insufficient: test runners commonly deduplicate module instances into one graph,
while the production runtime may load two or more independent copies of the
same library (e.g. dual-build packages resolved differently by different
consumers). The patch then works in every test and never fires in production.

**Gate:** before claiming a prototype/module-patch fix complete, run a probe in
the production-like runtime (container, deployed process — not the test runner)
that asserts the patched object is the SAME instance every consumer uses. If
the library ships multiple builds, resolve it through each loading mechanism
the runtime uses and compare identities:

```
✅ [Probe in target runtime] [See: patched object identity === consumer's object identity] "Patch covers production"
❌ "All specs green" (test runner deduped the module graph; production splits it)
```

If identities differ, the fix must patch every reachable instance, and the
probe becomes part of the verification suite.

## Why This Matters

From 24 failure memories:
- your human partner said "I don't believe you" - trust broken
- Undefined functions shipped - would crash
- Missing requirements shipped - incomplete features
- Time wasted on false completion → redirect → rework
- Violates: "Honesty is a core value. If you lie, you'll be replaced."

## When To Apply

**ALWAYS before:**
- ANY variation of success/completion claims
- ANY expression of satisfaction
- ANY positive statement about work state
- Committing, PR creation, task completion
- Moving to next task
- Delegating to agents

**Rule applies to:**
- Exact phrases
- Paraphrases and synonyms
- Implications of success
- ANY communication suggesting completion/correctness

## The Bottom Line

**No shortcuts for verification.**

Run the command. Read the output. THEN claim the result.

This is non-negotiable.

## Shared Working Tree — Verify the Committed Blob, Not the Tree

In a **shared** git working tree (a framework or workspace repo touched by
multiple parallel agent sessions), another session may `git checkout` a
different branch in the same tree *after* you committed your work. A direct
`grep` / `cat` / `Read` of the working tree then measures the WRONG branch —
you can read a sibling task's pre-fix state and raise a false failure against
your own already-correct commit.

**Rule:** before verifying a task's output, probe the tree's current branch:

```bash
git -C <repo> rev-parse --abbrev-ref HEAD
```

If it differs from your task branch, read your committed state directly from
your branch instead of the working tree:

```bash
# noshellcheck-extract
git -C <repo> cat-file blob <task-branch>:<path>   # or: git show <task-branch>:<path>
```

This applies at every verification gate (self-review, QA, compliance,
archive). The working tree is shared state; your branch is the source of
truth for what you shipped.
