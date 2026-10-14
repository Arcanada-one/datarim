---
schema_version: product-artifact/2
id: artifact:SYN-DECISION-002
artifact_type: decision-record
revision: 1
status: submitted
acceptance_state: submitted
source_digest: null
supersedes: null
---

## Data

```product-artifact-data
question: "Should this synthetic control keep the narrow decision-record scope?"
options:
  - id: continue-narrow
    description: Keep the narrow synthetic structural control.
    disposition: selected
    rationale: It directly checks the requested decision-record fields.
  - id: expand-fixture
    description: Add broader synthetic product behavior.
    disposition: deferred
    rationale: Broader behavior is outside this structural control.
selected_option: continue-narrow
business_outcome: continue
strategist_recommendation: GO
evidence_acceptance: pending
authority_to_act:
  status: granted
  authority_ref: null
evidence_refs:
  - {id: raw:SYN-DECISION-SUPPORT-002, revision: 1, digest: sha256:5783171fe3ae5310d88118ad1813fdbcf13e15088d171933a7a54b62174d5b77}
counterevidence_refs:
  - {id: raw:SYN-DECISION-COUNTER-002, revision: 1, digest: sha256:da215666f394ffb789ff084685b89e215b1ffdc2807906ecde905f4cf82c2bcb}
applicable_thresholds:
  - The fixture tests structural presence and local reference resolution only.
uncertainty:
  - Synthetic controls do not establish user impact or evidence quality.
reversal_conditions:
  - Revise this record if the structural contract or accepted outcome changes.
owner: synthetic-fixture-author
scope_delta: "none; no execution authority or product scope change"
source_refs: []
provenance:
  recorder: synthetic-fixture-author
  recorded_at: "2026-10-14T00:00:00Z"
  origin_kind: synthetic_fixture
```
