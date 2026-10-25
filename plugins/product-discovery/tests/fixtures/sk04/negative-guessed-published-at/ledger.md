---
schema_version: product-artifact/1
id: artifact:LEDGER-SYN-001
artifact_type: source-evidence-ledger
revision: 1
status: recorded
acceptance_state: accepted
source_digest: null
supersedes: null
---

## Data

```product-artifact-data
search_scope: two explicitly synthetic source records
search_completed_at: '2026-10-14T00:00:00Z'
entries:
- id: source:SYN-A
  revision: 1
  locator: bundle://fixtures/SYN-A.txt
  origin_kind: synthetic_fixture
  origin_family: SYNTHETIC-FAMILY-1
  duplicate_group: SYNTHETIC-DUPLICATES-1
  conflict_group: SYNTHETIC-CONFLICT-1
  publisher_or_actor: synthetic-fixture-generator
  observed_by: synthetic-fixture-generator
  observed_at: '2026-10-14T00:00:00Z'
  published_at: '2025-01-01T00:00:00Z'
  published_at_basis_ref: null
  retrieved_at: '2026-10-14T00:00:00Z'
  purpose: claim-quality-control
  raw_ref:
    id: raw:SYN-A
    revision: 1
    digest: sha256:e646f96fd462bc205f304617032491e0546817cfb3fb8b220f9d1726cba0f4f0
  availability: available
  search_status: match_found
  disclosure: synthetic_only
  unavailable_reason: null
  search_method: fixed fixture construction
  media_type: text/plain
- id: source:SYN-B
  revision: 1
  locator: bundle://fixtures/SYN-B.txt
  origin_kind: synthetic_fixture
  origin_family: SYNTHETIC-FAMILY-1
  duplicate_group: SYNTHETIC-DUPLICATES-1
  conflict_group: SYNTHETIC-CONFLICT-1
  publisher_or_actor: synthetic-fixture-generator
  observed_by: synthetic-fixture-generator
  observed_at: '2026-10-14T00:00:00Z'
  published_at: null
  published_at_basis_ref: null
  retrieved_at: '2026-10-14T00:00:00Z'
  purpose: claim-quality-control
  raw_ref:
    id: raw:SYN-B
    revision: 1
    digest: sha256:cc7d6c4dbd6e3decfac99e7eeab9ff92dafa735bdf895806289d4da6e7b39359
  availability: available
  search_status: match_found
  disclosure: synthetic_only
  unavailable_reason: null
  search_method: fixed fixture construction
  media_type: text/plain
source_refs: []
provenance:
  recorder: fixture-runner-1
  recorded_at: '2026-10-14T00:00:00Z'
  origin_kind: synthetic_fixture
```
