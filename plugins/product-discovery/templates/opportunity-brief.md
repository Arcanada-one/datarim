---
schema_version: product-artifact/1
id: artifact:<stable-id>
artifact_type: opportunity-brief
revision: 1
status: draft
acceptance_state: not_submitted
source_digest: null
supersedes: null
---

## Data

```product-artifact-data
question: "<non-empty question>"
segment: "<segment>"
actors:
  user: "<user or null>"
  buyer: null
  payer: null
context: "<context>"
claims: []
current_workaround: null
problem_cost: null
alternatives:
  # These are unfilled prompts, not selected options or evidence. Describe at
  # least two distinct build options and an explicit Stop / do-nothing option.
  # For each, fill in the user outcome, smallest scope, Effort, Risk, Reuses,
  # key assumption, and evidence that could distinguish it. For Stop, include
  # the rationale and counterevidence. Leave unknowns visibly unfilled; do not
  # claim evidence, completed actions, or outcomes that were not observed.
  - "<unfilled Minimal option: user outcome; smallest scope; Effort; Risk; Reuses; key assumption; discriminating evidence>"
  - "<unfilled Ideal option: user outcome; smallest scope; Effort; Risk; Reuses; key assumption; discriminating evidence>"
  - "<unfilled Stop / do-nothing option: user outcome; smallest scope; Effort; Risk; Reuses; key assumption; discriminating evidence; rationale; counterevidence>"
distribution_assumptions: []
constraints: []
unknowns: []
# Keep this value unfilled until an action is chosen. Name an action that uses
# only declared or later-authorized inputs, and state which observable result
# would favor each live option. Do not describe the action as completed.
next_discriminating_action: "<unfilled: action and observable result that distinguish the live options>"
source_refs: []
provenance:
  recorder: "<recorder>"
  recorded_at: "<RFC 3339 timestamp>"
  origin_kind: "<origin kind>"
```
