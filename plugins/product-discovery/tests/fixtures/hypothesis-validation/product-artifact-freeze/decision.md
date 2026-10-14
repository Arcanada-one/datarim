---
schema_version: product-artifact/1
id: artifact:DEC-HV-FREEZE-001
artifact_type: decision-record
revision: 1
status: submitted
acceptance_state: accepted
source_digest: sha256:683cdf600673706f617fad4a53c2267362273ea6b013a70be42cd4d06b02dcd1
supersedes: null
---

## Data

```product-artifact-data
question: Does the frozen synthetic protocol remain the referenced basis for this decision?
options:
  - id: retain-protocol
    description: Retain the exact revision and bytes referenced below.
    disposition: selected
    rationale: The worked decision records the exact protocol digest.
selected_option: retain-protocol
business_outcome: continue
evidence_refs: []
counterevidence_refs: []
applicable_thresholds: []
uncertainty: Synthetic structural control only.
reversal_conditions:
  - A later accepted decision references a superseding protocol revision.
owner: synthetic-example-author
approved_scope_delta: null
source_refs:
  - {id: artifact:EXP-SYN-001, revision: 1, digest: sha256:0bb3fa4a16482efed5ea558d12faaeec2270db04a5a8d25b271baece5bcf44ab}
provenance:
  recorder: synthetic-example-author
  recorded_at: "2026-10-14T00:00:00Z"
  origin_kind: synthetic_fixture
```
