---
schema_version: product-artifact/1
id: artifact:OPP-SYN-001
artifact_type: opportunity-brief
kc_contract: true
revision: 1
status: ready_for_research
acceptance_state: accepted
source_digest: sha256:d32d20b2b99ab9d6ae65568d9db0b60c7f5654076bd169d22bfeb54cbfb35234
supersedes: null
---

## Data

```product-artifact-data
question: Should the synthetic onboarding guide expose a next-step link?
segment: synthetic fixture participants only
actors:
  user: synthetic participant
  buyer: null
  payer: null
context: A fixed synthetic onboarding scenario; no real people or customer data.
claims:
  - id: OPP-CLAIM-001
    claim_type: fixture-observation
    statement: The simulated participant did not locate the next-step link in the fixed fixture.
    scope: one synthetic scenario only
    kind: observed
    supporting_refs:
      - {id: raw:SYN-EV-001-RAW, revision: 1, digest: sha256:54f3d73f2061cc03705b400d8a9553cf2528e48914c181254db0aec89cae66ca}
    contradicting_refs: []
    provenance_ref: {id: raw:SYN-EV-001-RAW, revision: 1, digest: sha256:54f3d73f2061cc03705b400d8a9553cf2528e48914c181254db0aec89cae66ca}
current_workaround: null
problem_cost: null
alternatives:
  - Keep the synthetic guide unchanged.
  - Add a visible next-step link to the synthetic guide.
  - No-build.
distribution_assumptions: []
constraints:
  - Synthetic fixture only.
unknowns:
  - No market demand or real-user outcome is measured.
next_discriminating_action: Compare two synthetic guide fixtures under a frozen protocol.
source_refs:
  - {id: raw:SYN-EV-001-RAW, revision: 1, digest: sha256:54f3d73f2061cc03705b400d8a9553cf2528e48914c181254db0aec89cae66ca}
provenance:
  recorder: fixture-runner-1
  recorded_at: "2026-10-14T00:00:00Z"
  origin_kind: synthetic_fixture
```
