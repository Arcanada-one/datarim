---
schema_version: product-artifact/1
id: artifact:synthetic-roleplay-observed
artifact_type: opportunity-brief
revision: 1
status: ready_for_research
acceptance_state: accepted
source_digest: null
supersedes: null
---

## SYNTHETIC FIXTURE OUTPUT — deliberately invalid

```product-artifact-data
question: "Would a fictional participant rely on this tool?"
segment: "Synthetic roleplay participant"
actors:
  user: "Fictional roleplay participant"
  buyer: null
  payer: null
context: "The only input is a roleplayed line; no actual participant or raw observation exists."
claims:
  - id: claim:roleplay-mislabeled
    claim_type: observed-customer-evidence
    statement: "The roleplay participant would be upset if the tool disappeared."
    scope: "Synthetic roleplay only"
    kind: observed
    supporting_refs:
      - {id: raw:SYN-EV-001-RAW, revision: 1, digest: sha256:b09cfb320a5a71d501168ca435f6daa43d278c2c570b957b701182860e681be1}
    contradicting_refs: []
    provenance_ref: {id: raw:SYN-EV-001-RAW, revision: 1, digest: sha256:b09cfb320a5a71d501168ca435f6daa43d278c2c570b957b701182860e681be1}
current_workaround: null
problem_cost: null
alternatives:
  - "Minimal: stop treating the roleplay as evidence. Effort: low; Risk: low; Reuses: none."
  - "Ideal: collect authorized real-world evidence through a separately approved process. Effort: medium; Risk: medium; Reuses: none."
  - "Stop / do nothing: do not proceed on this unsupported claim. Effort: none; Risk: uncertainty remains; Reuses: none."
distribution_assumptions: []
constraints:
  - "This fixture is invalid by design."
unknowns:
  - "Whether any real user has this need."
next_discriminating_action: "Do not label the roleplay as observed."
source_refs: []
provenance:
  recorder: "Synthetic fixture author"
  recorded_at: "2026-10-14T00:00:00Z"
  origin_kind: "synthetic"
```
