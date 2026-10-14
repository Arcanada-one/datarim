---
schema_version: product-artifact/1
id: artifact:SYN-DECISION-LEDGER-002
artifact_type: source-evidence-ledger
revision: 1
status: recorded
acceptance_state: accepted
source_digest: null
supersedes: null
---

## Data

```product-artifact-data
search_scope: "Two synthetic structural-control observations only."
search_completed_at: null
entries:
  - id: source:SYN-DECISION-SUPPORT-002
    revision: 1
    locator: bundle://fixtures/support.txt
    origin_kind: synthetic_fixture
    publisher_or_actor: structural-control
    observed_by: structural-control
    observed_at: "2026-10-14T00:00:00Z"
    published_at: null
    retrieved_at: "2026-10-14T00:00:00Z"
    purpose: synthetic-decision-record-control
    raw_ref: {id: raw:SYN-DECISION-SUPPORT-002, revision: 1, digest: sha256:5783171fe3ae5310d88118ad1813fdbcf13e15088d171933a7a54b62174d5b77}
    availability: available
    search_status: match_found
    disclosure: synthetic_only
    unavailable_reason: null
    search_method: fixture
    media_type: text/plain
  - id: source:SYN-DECISION-COUNTER-002
    revision: 1
    locator: bundle://fixtures/counterevidence.txt
    origin_kind: synthetic_fixture
    publisher_or_actor: structural-control
    observed_by: structural-control
    observed_at: "2026-10-14T00:00:00Z"
    published_at: null
    retrieved_at: "2026-10-14T00:00:00Z"
    purpose: synthetic-decision-record-control
    raw_ref: {id: raw:SYN-DECISION-COUNTER-002, revision: 1, digest: sha256:da215666f394ffb789ff084685b89e215b1ffdc2807906ecde905f4cf82c2bcb}
    availability: available
    search_status: match_found
    disclosure: synthetic_only
    unavailable_reason: null
    search_method: fixture
    media_type: text/plain
source_refs: []
provenance:
  recorder: synthetic-fixture-author
  recorded_at: "2026-10-14T00:00:00Z"
  origin_kind: synthetic_fixture
```
