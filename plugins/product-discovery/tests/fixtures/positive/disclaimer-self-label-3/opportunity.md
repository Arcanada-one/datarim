---
schema_version: product-artifact/1
id: artifact:OPP-SYN-001
artifact_type: opportunity-brief
revision: 1
status: ready_for_research
acceptance_state: accepted
source_digest: null
supersedes: null
---

## Boundary disclaimer

The product artifact serves as a Knowledge Contract.

## Data

```product-artifact-data
question: Should the synthetic onboarding guide expose a next-step link?
segment: synthetic fixture participants only
actors:
  user: synthetic participant
  buyer: null
  payer: null
context: A fixed synthetic onboarding scenario; no real people or customer data.
claims: []
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
source_refs: []
provenance:
  recorder: fixture-runner-1
  recorded_at: "2026-10-14T00:00:00Z"
  origin_kind: synthetic_fixture
```
