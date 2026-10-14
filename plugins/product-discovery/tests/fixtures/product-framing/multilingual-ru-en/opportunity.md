---
schema_version: product-artifact/1
id: artifact:synthetic-multilingual-input
artifact_type: opportunity-brief
revision: 1
status: draft
acceptance_state: not_submitted
source_digest: null
supersedes: null
---

## SYNTHETIC FIXTURE OUTPUT

```product-artifact-data
question: "What causes the fictional handoff to be late?"
segment: "Fictional teams with recurring task handoffs"
actors:
  user: null
  buyer: null
  payer: null
context: "Synthetic input in Russian says the speaker cannot hand off a task in time; the English paraphrase says the handoff is often late."
claims: []
current_workaround: null
problem_cost: null
alternatives:
  - "Minimal: inspect one declared handoff example. Effort: low; Risk: low; Reuses: current process."
  - "Ideal: redesign the full handoff workflow. Effort: high; Risk: high; Reuses: current process."
  - "Stop / do nothing: retain the current workflow. Effort: none; Risk: delay may continue; Reuses: existing workflow."
distribution_assumptions: []
constraints:
  - "The artifact language remains English."
unknowns:
  - "Whether the paraphrase matches the original speaker's meaning."
next_discriminating_action: "Confirm the meaning of the supplied statement before interpreting its cause."
source_refs: []
provenance:
  recorder: "Synthetic fixture author"
  recorded_at: "2026-10-14T00:00:00Z"
  origin_kind: "synthetic"
```
