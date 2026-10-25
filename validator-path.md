# T5.3 implementation path

Base pin: Datarim `main` `89a010a057c9a4e7c0c8b20aaf1545eb4ad454fd`, tree
`028c9038523535d8c8e76e2bad66295fcfa45159`. The former local inspection copy at
`ae54b30c6365003e55a3a2778d4acf439261bb77` is stale and is not the implementation
base.

## Existing producer and consumers

- `dev-tools/dr-verify-floor.sh` is the executable deterministic finding producer
  for Layer 1. It emits JSONL; it is not the audit-record validator.
- `commands/dr-verify.md` orchestrates aggregation, deduplication, iteration and
  the final audit-log write. Its prior validator and audit-writer description
  delegated schema validation to pseudocode in
  `skills/self-verification/findings-and-audit.md` and
  `skills/self-verification/SKILL.md`.
- `dev-tools/test-self-verification-claude.sh` is an existing post-write
  integration consumer. It reads audit files and checks runtime postconditions;
  it does not validate or normalize finding records.
- `commands/dr-qa.md` Layer 3 is the actual user-facing plan-completion consumer.
  It previously used `Done / Skipped / Modified` in its row template and had no
  required status vocabulary or discrepancy-reason field.
- The source for the requested plan-completion distinctions is pinned gstack
  `review/sections/plan-completion.md` at `15ebd85cdde6c9a1b2fb707e8573aec18e8f7438`.

## Implementation added

`dev-tools/validate-self-verification-findings.py` is the deterministic
validator/normalizer called by `/dr-verify` after its three layers have been
aggregated and deduplicated and before the audit file is written. It preserves
legacy records without `resolution` and `round`; new records must contain both.
It validates the existing evidence/schema rules, auto-discards `absent`, retains
`verified_absence`, rejects `confidence`, and accepts only
`actionable | advisory | unresolved` with a round bound to the current iteration.
At `max_iter`, `unresolved` remains `unresolved`; the validator has no `fixed`
state and never infers closure from the cap.

The verifier Bats suite for this helper is
`dev-tools/tests/self-verification-findings.bats`. It has been authored but is
not run until D5 releases the heavy lane after T5.2.
