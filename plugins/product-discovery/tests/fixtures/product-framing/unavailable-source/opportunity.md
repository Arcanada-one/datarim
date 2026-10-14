---
schema_version: product-artifact/1
id: artifact:synthetic-unavailable-source
artifact_type: opportunity-brief
revision: 1
status: draft
acceptance_state: not_submitted
source_digest: null
supersedes: null
---

## SYNTHETIC FIXTURE OUTPUT

```product-artifact-data
question: "What does the inaccessible scheduling report say about handoff delays?"
segment: "Fictional team using a scheduling report"
actors:
  user: null
  buyer: null
  payer: null
context: "The declared input says the report cannot currently be opened."
claims: []
current_workaround: null
problem_cost: null
alternatives:
  - "Minimal: restore access to the declared report. Effort: low; Risk: low; Reuses: the referenced report."
  - "Ideal: evaluate workflow changes after the report is readable. Effort: medium; Risk: medium; Reuses: the report."
  - "Stop / do nothing: defer analysis while access is unavailable. Effort: none; Risk: uncertainty remains; Reuses: current workflow."
distribution_assumptions: []
constraints:
  - "Unavailable does not mean no matching evidence exists."
unknowns:
  - "Report contents and whether it supports the delay claim."
next_discriminating_action: "Retry the declared report through its authorized owner when access is available."
source_refs: []
provenance:
  recorder: "Synthetic fixture author"
  recorded_at: "2026-10-14T00:00:00Z"
  origin_kind: "synthetic"
```
