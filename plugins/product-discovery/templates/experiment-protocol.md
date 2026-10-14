---
schema_version: product-artifact/1
id: artifact:<stable-id>
artifact_type: experiment-protocol
revision: 1
status: draft
acceptance_state: not_submitted
source_digest: null
supersedes: null
---

## Data

```product-artifact-data
hypothesis_ref: {id: "artifact:<id>", revision: 1, digest: "sha256:<64 lowercase hex>"}
method: "<method>"
sampling_rule: "<sampling and recruitment constraints>"
analysis_unit: "<unit>"
randomization_unit: null
randomization_not_applicable_reason: "<reason if not applicable>"
primary_outcome: "<primary outcome>"
secondary_outcomes: []
sample_rule: "<sample rule>"
threshold_decision_map: "<threshold-to-decision mapping>"
exclusion_rule: "<exclusion rule>"
missing_data_rule: "<missing data rule>"
stop_rule: "<stop rule>"
duration_cap: null
budget_cap:
  max_calls: 0
  max_cash_cost: null
  budget_ref: "<finite budget reference>"
grant_ref: null
privacy_disclosure: "<privacy disclosure>"
observation_format: "<observation format>"
analysis_code_pin: null
source_refs: []
provenance:
  recorder: "<recorder>"
  recorded_at: "<RFC 3339 timestamp>"
  origin_kind: "<origin kind>"
```
