---
schema_version: product-artifact/1
id: artifact:synthetic-contradiction
artifact_type: opportunity-brief
revision: 1
status: draft
acceptance_state: not_submitted
source_digest: null
supersedes: null
---

## SYNTHETIC FIXTURE OUTPUT

```product-artifact-data
question: "Did the fictional team try the prototype?"
segment: "One fictional internal team"
actors:
  user: "Fictional team"
  buyer: null
  payer: null
context: "Two synthetic inputs disagree about whether access was provided."
claims:
  - id: claim:synthetic-conflict
    claim_type: conflicting-inputs
    statement: "One declared input says three trials occurred; another says access was never granted."
    scope: "Synthetic fixture only"
    kind: unknown
    supporting_refs: []
    contradicting_refs: []
    unknown_reason: "The supplied statements conflict and neither has a raw reference."
current_workaround: null
problem_cost: null
alternatives:
  - "Minimal: reconcile the two supplied records. Effort: low; Risk: low; Reuses: both declared inputs."
  - "Ideal: trial the prototype with a separate fictional workflow. Effort: medium; Risk: medium; Reuses: current prototype."
  - "Stop / do nothing: defer a decision. Effort: none; Risk: uncertainty remains; Reuses: none identified in supplied inputs."
distribution_assumptions: []
constraints:
  - "Do not resolve the conflict by choosing one statement."
unknowns:
  - "Whether any trial occurred."
next_discriminating_action: "Compare the fictional access record with the fictional trial log if both become declared inputs."
source_refs: []
provenance:
  recorder: "Synthetic fixture author"
  recorded_at: "2026-10-14T00:00:00Z"
  origin_kind: "synthetic"
```
