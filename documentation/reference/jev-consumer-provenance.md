# JEV decision and consumer provenance

The client distinguishes requested aliases from returned version labels. `model`
is the observed public JEV label, not the alias from configuration. Only a
returned numeric version such as `jev-1.13.0` yields
`resolved_model_status=observed`. An absent, malformed, or alias-only response
remains `not_measured`; this is provider-reported identity, not attestation.

Each successful native request has a random `decision_id` and SHA-256 of the
actual scrubbed wire payload and question catalog. Retries retain the same ID;
separate evaluations get distinct IDs even for identical payloads. Provider
`_client` fields cannot supply these facts. Failed and disabled calls create no
successful-decision evidence. The existing release SHA identifies code when
running an installed release; a source checkout continues to report null.

`JevDecisionEvidence/v1` binds the request to hashes of the effective policy,
candidate catalog and recommendation. It contains no prompt, candidate text,
path or policy values. These hashes are correlation evidence, not authorization
or model accuracy. Do not publish local telemetry indiscriminately: hashes of
low-entropy inputs can still be identifying.

## Native consumer observations

| Outcome | Meaning | `applied` |
| --- | --- | --- |
| advisory | Recommendation produced or emitted; agent use unobserved | false or `not_measured` for hooks |
| deferred | Configuration queued for another turn | false |
| dispatched | A following process was started with queued configuration | false |
| uncertain | Control response timed out | false |
| refused | Runtime adapter rejected the change | false |
| applied | Validated tier accepted by in-process runtime control ACK | true |

`applied` carries `confirmation=runtime_control_ack`. This confirms the control
operation; it does not measure the provider model used for a subsequent answer.
A timed-out command still consumes the policy gate's switch/hysteresis allowance
because late application is possible. Its actual result stays uncertain.
`final_tier` describes configured invocation/control acknowledgement, as labelled
by `final_tier_basis`; an unresolved timeout makes it null. Policy gate state is
recorded separately when it differs.

A `live_switch_dispatch` event links a deferred request to its process start
without rewriting the earlier event. Statistics replace the queued state only
when the full evidence binding matches. Older records claiming application
without a confirmation remain `not_measured`; historical timeout/deferred fields
are conservatively classified. No history is rewritten.

For prompt hooks, `routing_advice` contains decision evidence; its hook context
and the wrapper's `hook_delivery` share a fresh `delivery_id`. Cached advice
retains the original decision identity and gains a new delivery identity. Cursor
prompt hooks cannot inject advice; their native delivery still records
`advice_emitted=false`. Hook emission never confirms component loading, execution,
or a change to the current model. Legacy cache entries without evidence remain
unlinked rather than acquiring invented provenance.

## Statistics compatibility

Component confidence output uses `selected` and `selected_rate`, replacing the
misleading `applied` / `applied_rate` fields. This is a JSON reader migration:
update consumers of `dr-jev stats --json` accordingly. Selection means that a
probability cleared the existing threshold; it is neither execution nor a
classification accuracy measure. Live switch statistics separately report all
outcome states above plus `not_measured` and policy blocks.

The change adds observation only and corrects application accounting. It adds
no model requests, endpoint, host enablement or permission. Existing routing,
namespace/credential policy, candidate validation and deterministic safety
floor remain authoritative. Telemetry still follows its existing enable switch.
Reverting the source change rolls back this observation vocabulary; it does not
undo an earlier runtime operation or alter an existing ledger.

## Offline validation

Run `python3 scripts/jev_provenance_canary.py` to exercise the actual request
client, supervisor, synthetic CLI subprocess, prompt cache and native wrappers.
Its provider transport is a fixture and it performs no model calls. Unit checks
live in `plugins/dr-jev-control/tests/test_consumer_provenance.py`; the full
plugin suite includes existing runtime, kill-switch and ledger checks. Any test
that opens a loopback socket must run inside a private network namespace.

Host adoption, remote CI, actual provider/model use and production accuracy
require separate evidence; this fixture canary establishes none of them.
