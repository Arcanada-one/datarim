---
schema_version: product-artifact/1
id: artifact:PROD-SYN-001
artifact_type: product-brief
revision: 1
status: ready_for_delivery
acceptance_state: accepted
source_digest: sha256:8988c125c7cb645a3630e36ac9d36610609e1ff1b0fa3a3b316fc7faf3b07634
supersedes: null
---

## Data

```product-artifact-data
accepted_intent: Prepare a bounded synthetic guide fixture change for an existing PRD/task lifecycle.
requirements:
  - The next-step link appears in the synthetic guide fixture.
  - Any evaluation remains synthetic and reports missing outcomes as unknown.
risk:
  - Fixture results do not establish market or customer value.
scope:
  - Synthetic guide content and its fixture-only comparison.
non_goals:
  - No real user research, release, publication, or production behavior.
hypothesis_refs:
  - {id: artifact:HYP-SYN-001, revision: 1, digest: sha256:1ab45e60cba22d7985ec42251c2ff4acf76dec581c0cb52144d79c93bbc7a93b}
input_revisions:
  - {id: artifact:DEC-SYN-001, revision: 1, digest: sha256:d86b1abe3c995d6666e5bfb0bc63f09c175a4cad096e8784333a2390eef48181}
  - {id: artifact:HYP-SYN-001, revision: 1, digest: sha256:1ab45e60cba22d7985ec42251c2ff4acf76dec581c0cb52144d79c93bbc7a93b}
success_criteria:
  - Existing task acceptance owner can verify the link in the fixture.
acceptance_owner: synthetic-example-owner
downstream_task_ref: null
source_refs:
  - {id: artifact:DEC-SYN-001, revision: 1, digest: sha256:d86b1abe3c995d6666e5bfb0bc63f09c175a4cad096e8784333a2390eef48181}
  - {id: artifact:HYP-SYN-001, revision: 1, digest: sha256:1ab45e60cba22d7985ec42251c2ff4acf76dec581c0cb52144d79c93bbc7a93b}
provenance:
  recorder: synthetic-example-author
  recorded_at: "2026-10-14T00:00:00Z"
  origin_kind: synthetic_fixture
```
