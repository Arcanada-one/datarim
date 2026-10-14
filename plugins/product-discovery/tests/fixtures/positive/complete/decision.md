---
schema_version: product-artifact/1
id: artifact:DEC-SYN-001
artifact_type: decision-record
revision: 1
status: submitted
acceptance_state: accepted
source_digest: sha256:eee8df0a4c88731fc8abe8b97a9b06ea3f206359c8778328117a92370ec3eed1
supersedes: null
---

## Data

```product-artifact-data
question: Which synthetic guide variant should be used for the next fixture comparison?
options:
  - id: keep
    description: Keep the current synthetic guide.
    disposition: rejected
    rationale: The fixture runner failed to locate the next-step link in this one scenario.
  - id: add-link
    description: Add a next-step link to the synthetic guide fixture.
    disposition: selected
    rationale: This is a bounded fixture change for a later synthetic comparison.
  - id: no-build
    description: Make no change.
    disposition: deferred
    rationale: Preserve as an alternative if the next fixture comparison is inconclusive.
selected_option: add-link
business_outcome: continue
evidence_refs:
  - {id: artifact:OPP-SYN-001, revision: 1, digest: sha256:d79785a81db42cbaee9bc2a4957a938f6732f9a0efe9c16188450baf8998e27b}
  - {id: raw:SYN-EV-001-RAW, revision: 1, digest: sha256:54f3d73f2061cc03705b400d8a9553cf2528e48914c181254db0aec89cae66ca}
counterevidence_refs: []
applicable_thresholds:
  - This decision applies only to a synthetic fixture; it is not a product or release decision.
uncertainty:
  - No real-user, buyer, payer, demand, or conversion evidence exists in this example.
reversal_conditions:
  - Reverse the fixture choice if the next synthetic comparison shows no improvement or introduces an error.
owner: synthetic-example-owner
approved_scope_delta: Synthetic fixture comparison only.
source_refs:
  - {id: artifact:OPP-SYN-001, revision: 1, digest: sha256:d79785a81db42cbaee9bc2a4957a938f6732f9a0efe9c16188450baf8998e27b}
  - {id: raw:SYN-EV-001-RAW, revision: 1, digest: sha256:54f3d73f2061cc03705b400d8a9553cf2528e48914c181254db0aec89cae66ca}
provenance:
  recorder: synthetic-example-owner
  recorded_at: "2026-10-14T00:00:00Z"
  origin_kind: synthetic_fixture
```
