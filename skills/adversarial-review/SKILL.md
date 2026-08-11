---
name: adversarial-review
description: "Forces an adversarial mindset on a plan, PRD, design, or code change — break it rather than bless it. Loaded at the /dr-plan checkpoint and /dr-qa."
current_aal: 1
target_aal: 2
---

# Adversarial Review — Break It Before Production Does

The default failure mode of review is confirmation: a reader who wants the
artifact to be correct finds reasons it is. This skill inverts the stance. Your
job is to construct the strongest case that the artifact is **wrong,
incomplete, or unsafe** — and only then weigh that case against its defence.

This is the *general* adversarial lens. Two sibling skills sharpen specific
axes: `edge-case-hunter` (boundary and failure inputs the artifact does not
handle) and `structure-review` (organisation, completeness, internal
contradiction). Load whichever the task calls for; this skill covers the
mindset and the whole-artifact attack.

## The core rule: "no findings" is an alarm, not an all-clear

If an adversarial pass produces zero findings, that is evidence the pass was
shallow — not that the artifact is flawless. Before you may record "no
material findings", you MUST have done at least one of:

- named the artifact's single most load-bearing assumption and tried to falsify it;
- traced one concrete failure scenario end-to-end and shown it cannot occur;
- identified what the artifact does NOT claim to handle, and confirmed that scope cut is deliberate and stated.

A clean pass with none of the above is not a pass — it is an un-run review.

## How to attack an artifact

Work outside-in. Cheap, high-yield attacks first.

1. **Attack the premise.** What must be true for this to be the right thing to
   build/ship at all? If that premise is unstated or unverified, that is the
   finding — everything downstream inherits it.
2. **Attack the strongest claim.** Find the sentence the artifact most depends
   on ("this is idempotent", "this cannot deadlock", "the gate blocks X").
   Assume it is false and look for the path that makes it false.
3. **Attack the boundaries.** Empty input, maximal input, concurrent callers,
   partial failure, retry, the second run, the resumed run. (Hand off depth
   here to `edge-case-hunter`.)
4. **Attack the seams.** Every interface between two components is a place
   where each side assumes the other's contract. Name one assumption each side
   makes that the other does not guarantee.
5. **Attack reversibility.** If this is wrong in production, how is it detected,
   and how is it undone? An action that cannot be observed-wrong or rolled back
   raises the bar on every finding above.

## Steelman before you dismiss

For each finding, before discarding it as "won't happen", write the one-line
scenario in which it does. A finding you cannot even phrase as a concrete
scenario is genuinely out of scope; a finding you *can* phrase but dismiss on
gut feel is a deferred incident. Record the scenario either way — it is the
audit trail for the decision.

## Output

Report findings ranked most-severe first. For each: one-sentence defect + a
concrete failure scenario (inputs/state → wrong outcome). Separate confirmed
defects from open questions. End with the single highest-leverage thing to fix.
Never soften a real finding to preserve momentum — a blocked artifact caught in
review is cheaper than a shipped one caught in production.

## When to load

- `/dr-plan` Transition Checkpoint — after "is the plan testable?", ask "what would break this plan?" before locking it.
- `/dr-qa` — as an explicit adversarial layer over the implementation, not only a conformance check.
- Any Level 3-4 design or PRD decision where a wrong call is expensive to reverse.
