# Multisurface Contract Map

Use this fragment when writing or reviewing a QA charter. Map each claimed
behaviour to its real entrypoint and list only the applicable surfaces. Prefer
observable contracts and state effects over implementation-only assertions.

## Probe design

For each behaviour, specify its contract, risk, entrypoint, isolation boundary,
exit condition, source, commands, and inputs. Add independent probes for the
applicable cases below:

- **Success and durable effect:** the intended result is visible at the real
  consumer boundary and any promised state change is present.
- **Invalid input:** reject the input and prove forbidden state did not change.
- **Authentication and authorization:** cover valid identity, denial, and a
  wrong-owner attempt where ownership applies.
- **CLI contract:** assert exit status, stdout, and stderr separately; a message
  alone does not establish the command result.
- **State transition:** cover the declared before/after states and disallowed
  transitions.
- **Timeout and cancellation:** show the bounded outcome and retained state.
- **Retry and idempotency:** repeat the request and compare durable effects;
  distinguish a response from completion.
- **Concurrency:** exercise both relevant request orderings and identify the
  expected winner or commutative result.
- **Partial-failure recovery:** fail one step and verify the documented recovery
  path without claiming that an attempted action completed.
- **Asynchronous surfaces:** for worker and webhook flows, bind the initiating
  request to correlated completion or an explicit timeout/failure. A 2xx
  response is not completion unless the contract says the synchronous effect
  itself is complete.

These are design prompts, not a requirement to test irrelevant surfaces. Mark a
probe optional only when the charter explains why it is not part of the
contract. Do not turn a skipped required probe into a pass by relabeling it not
applicable.

## Outcomes and evidence

Use exactly one outcome per recorded probe:

| Outcome | Meaning |
|---|---|
| `pass` | The named assertion was observed at the declared boundary. |
| `fail` | The assertion ran and the observed result contradicted it. |
| `blocked` | The probe could not reach its declared precondition or environment. |
| `not run` | No execution was attempted. |
| `inconclusive` | Execution occurred but did not resolve the assertion. |
| `n.a.` | The probe is explicitly optional and its reason is recorded. |

Keep command, exit code, stdout/stderr, and artifact digest distinct where the
surface exposes them. Missing, stale, failed, blocked, not-run, or inconclusive
required evidence cannot produce charter-coverage PASS. Keep each evidence run
in a new `run-<UTC>/` directory; never overwrite a previous run or use `latest`
as the baseline path.

The coverage validator checks structure, pins, path safety, required-probe
presence, outcomes, and artifact digests. It does not judge whether the
assertion is semantically adequate; `/dr-qa` independently reviews evidence
against the charter.
