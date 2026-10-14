---
schema_version: product-artifact/1
id: artifact:EXP-SYN-001
artifact_type: experiment-protocol
revision: 1
status: protocol_frozen
acceptance_state: accepted
source_digest: sha256:4379fc0b7b58ecbd28613ba9266d3447d3e3574d302c69aa89743007f39bbfed
supersedes: null
---

## Data

```product-artifact-data
hypothesis_ref: {id: artifact:HYP-SYN-001, revision: 1, digest: sha256:6667013af34f31e0ec9894f5652a332d98d21f1d38db878b30072704e922d5d5}
method: Compare two fixed synthetic guide fixtures with one scripted simulator path each.
sampling_rule: One deterministic simulator execution per fixture; no people recruited.
analysis_unit: One synthetic scenario completion
randomization_unit: null
randomization_not_applicable_reason: Fixture variants are run in fixed order for this design example.
primary_outcome: Simulated next-step link located within 10 seconds (yes/no).
secondary_outcomes:
  - Count of simulated navigation errors.
sample_rule: Exactly one simulator path per variant; descriptive only, no statistical inference.
threshold_decision_map: Continue fixture iteration only if variant B locates the link and has no new critical error; otherwise revise or mark inconclusive.
exclusion_rule: Exclude no completed run; record a missing/failed simulator run as incomplete.
missing_data_rule: Preserve missing outcome as unknown; do not impute success.
stop_rule: Stop on any real-world side effect or on fixture-budget exhaustion.
duration_cap: 2 minutes per fixture run.
budget_cap:
  max_calls: 2
  max_cash_cost: 0
  budget_ref: synthetic-disabled-budget
grant_ref: null
privacy_disclosure: Synthetic fixture only; no real data is collected.
observation_format: One JSON row per simulator event with event id and result.
analysis_code_pin: null
source_refs:
  - {id: artifact:HYP-SYN-001, revision: 1, digest: sha256:6667013af34f31e0ec9894f5652a332d98d21f1d38db878b30072704e922d5d5}
provenance:
  recorder: synthetic-example-author
  recorded_at: "2026-10-14T00:00:00Z"
  origin_kind: synthetic_fixture
```
