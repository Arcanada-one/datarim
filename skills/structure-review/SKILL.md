---
name: structure-review
description: "Reviews an artifact's organisation, completeness, and internal consistency — does it hold together as a document, independent of whether each claim is true. The structural sibling of adversarial-review and edge-case-hunter; loaded at /dr-plan and /dr-qa."
current_aal: 1
target_aal: 2
---

# Structure Review — Does the Artifact Hold Together

`adversarial-review` asks whether the artifact is *wrong*. `edge-case-hunter`
asks what inputs it *ignores*. This skill asks a third, orthogonal question:
does the artifact **cohere** — is it organised, complete, and internally
consistent as a document, regardless of whether any individual claim is
correct? A plan can be factually right in every sentence and still fail here,
because two sections contradict each other or a promised section is missing.

## What structure review checks

1. **Completeness against the artifact's own contract.** If it is a plan, does
   every declared component have implementation steps and a validation entry?
   If it is a PRD, does every acceptance criterion trace to a requirement? The
   test is closure: no dangling reference, no promised-but-absent section, no
   requirement with no owner.
2. **Internal consistency.** Grep the artifact against itself. Does §3 assume
   what §7 rules out? Does the summary count differ from the enumerated list?
   Does a "MUST" in one place become a "should" in another? Contradictions
   between sections are the highest-yield structural defect — each one means at
   least one section is acting on a false belief about another.
3. **Traceability.** Can a reader follow each conclusion back to its premise and
   each requirement forward to its verification? Broken chains (a decision with
   no rationale, a test with no requirement, a requirement with no test) are
   structural holes even when every node is individually sound.
4. **Ordering and dependency.** Are steps in an order that can actually execute
   — does step 4 depend on state that only step 6 creates? A plan that reads
   fine top-to-bottom but cannot run in that order is structurally broken.
5. **Right altitude.** Is each section at a consistent level of detail? A plan
   that specifies one component to the line-number and another as "handle
   errors appropriately" has an altitude mismatch that hides the under-specified
   part.

## The counting discipline

Whenever the artifact states a count ("3 components", "the five gates", "both
runtimes"), verify it against the enumeration in the same document. Drifted
counts are a cheap, reliable signal that the document was edited in one place
and not another — and where a count drifted, meaning often drifted too.

## Distinguish structural from substantive

Keep this lens clean. "This section is missing" / "these two sections
contradict" / "this count is wrong" are structural. "This claim is false" /
"this input is unhandled" belong to the sibling skills — note them and route
them, do not resolve them here. Mixing the axes produces a review that is
thorough on neither.

## Output

Findings grouped: **missing** (promised-but-absent), **contradictory** (section
vs section, with both locations quoted), **untraceable** (broken premise→
conclusion or requirement→test chains), **drifted counts**. Each with its two
locations so the author can reconcile them. A structurally sound artifact is a
precondition for the other two reviews to mean anything — run this first when an
artifact is long or was assembled from parts.

## When to load

- `/dr-plan` — before the Transition Checkpoint, to confirm the plan is
  complete and self-consistent before it is attacked for correctness.
- `/dr-qa` — Layer 3 plan-completeness and any long PRD/design artifact.
- Any multi-section document assembled or edited across several passes.
