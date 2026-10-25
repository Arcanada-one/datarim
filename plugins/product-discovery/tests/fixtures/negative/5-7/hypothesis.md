---
schema_version: product-artifact/1
id: artifact:HYP-SYN-001
artifact_type: hypothesis-card
revision: 1
status: draft
acceptance_state: not_submitted
source_digest: null
supersedes: null
---

## Data

```product-artifact-data
scope: synthetic guide fixture comparison only
segment: synthetic fixture participants only
prediction: In the next fixed fixture, the next-step link will be located within 10 seconds.
alternative_explanation: The fixture result may be caused by the wording of the simulated task.
disconfirming_observation: The simulated participant still fails to locate the link within 10 seconds, or a new critical navigation error appears.
assumptions:
  - The synthetic scenario is unchanged between variants.
measurement_unit: one synthetic scenario completion
applicability_criteria:
  - Applies only to the fixture described by SYN-EV-001.
source_refs: []
provenance:
  recorder: synthetic-example-author
  recorded_at: "2026-10-14T00:00:00Z"
  origin_kind: synthetic_fixture
protocol_ref: null
evidence_refs: []
```
