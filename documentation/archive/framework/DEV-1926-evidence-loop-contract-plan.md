---
type: operating-model-contract
id: DEV-1926
class: B
status: approved
---

# DEV-1926 Evidence-Loop Operating-Model Contract and Implementation Plan

## 1. Purpose, Boundary, and Ratification

- Authorized-user operating rule: every task acceptance case must exist in the version 1 contract before implementation begins. Evidence must then be executed, discrepancies fixed, tests retested, and independent review repeated until all gates are green.
- No canonical framework PRD exists in this workspace. This approved written contract is the scoped ratification for DEV-1926.
- Scope is the isolated framework checkout only: no deploy, push, or merge.
- The implementation modifies the existing `check-live-evidence.sh`; no new evidence skill is created. The existing immutability skill remains the owner of shared normative rules.
- Contract and implementation must land in the same commit.

## 2. CLI Contract

### Consumption-causality addendum (2026-09-08)

The coordinator ratifies this narrow source-only correction under the user's
explicit autonomous framework-improvement mandate. Backend review reproduced
premature or permanently blocked completion when second-resolution timestamps
were used to infer that an answer had been consumed. A response retry cannot
reliably establish event ordering through wall-clock timestamps.

The existing heartbeat writer gains an opt-in, generic receipt snapshot. Set
`DATARIM_INTERACTION_RECEIPTS_DIR` and `DATARIM_INTERACTION_RUN_ID` together; the
optional path requires Python 3. Every write snapshots at most 128 regular,
non-symlink, bounded JSON receipt files named by interaction UUID. Each strict
record contains runId, interactionId, decisionId, and contextDigest. The run
must match; identifiers and digest are validated. No answers or authorization
are carried. Invalid input cannot overwrite the last valid heartbeat.

The stored heartbeat carries `interaction_run_id` and `interaction_receipts`;
each receipt contains interactionId, decisionId, and contextDigest. Reads never
append newer receipts to old state. A consumer must match the whole tuple and
run, not just a caller-supplied decision UUID (which may be reused). The
completion consumer also rejects future or invalid timestamps on every check.
Without the environment opt-in, existing heartbeat behavior is unchanged.

Acceptance: prove write-time snapshot immutability, same-second later writes,
wrong-run and malformed denial, symlink/oversize denial, partial configuration
denial, legacy compatibility, and retry-safe backend tuple matching. These
checks extend, rather than replace, the evidence-loop acceptance cases below.

`check-live-evidence.sh --contract FILE --evidence FILE --root DIR --stage preflight|snapshot|do|write|edit|publish|qa|compliance|archive|quick`

- Strict structured mode is enabled only when `--contract`, `--evidence`, `--root`, and `--stage` are all supplied.
- Legacy invocation without those flags remains accepted as explicitly uncertified legacy inspection. It must never report a certified green result and must not silently change existing legacy behavior.
- Return code is zero only when the requested strict stage is green; any missing, invalid, failed, blocked, stale, or mismatched evidence is non-zero.

## 3. Contract JSON Schema, Version 1

Top-level required fields:

- `version`: exactly `1`.
- `task_id`: this task identifier.
- `defined_at`: UTC timestamp when the contract was defined.
- `scope`: non-empty array of relative file paths covering the deliverable and its verification inputs, including test paths where applicable. Paths are relative to `--root`; traversal and symbolic links are rejected. Missing paths use an explicit missing sentinel, supporting planned new files and deletion verification.
- `criteria`: array of criterion objects.
- `workflow`: object containing `complexity`, `task_type`, and the selected ordered `route`. ID, complexity, and task type must equal the canonical task-description frontmatter at `datarim/tasks/{task_id}-task-description.md`. The route is part of the immutable contract digest and captured preflight; changing task classification after work cannot reuse the prior baseline or reviews.

Routes preserve the existing framework complexity contract. Normal L1 requires `do` then `archive`; L2 additionally permits QA; L3/L4 require `do`, `qa`, `compliance`, `archive`. Explicit stronger ordered checks are allowed. Quick is the single terminal route `[quick]` at L1. Content tasks use selected real stages from `write`, `edit`, `publish` (at least one, in order), followed by any selected QA/compliance and archive; L3/L4 retain mandatory QA/compliance. Every case belongs to a selected route stage. No fake receipts are created for stages the canonical route skips. Publish means payload preparation only; public sending and production approval remain separately hard-gated.

Standalone content commands without a Datarim/Git task retain their existing supported behavior: define acceptance/checklist cases before work, collect substantive evidence and repeat edits/checks, and explicitly report UNCERTIFIED for the structured gate. They cannot claim a task pipeline passed. A task-bound content command must use the strict route.

All declared string fields require scalar JSON strings; arrays, objects, numbers, booleans, and null are not coercible alternatives. Stage membership uses exact string equality against the selected route. Unknown stages are invalid, including on historical attempts.

Each criterion object:

- `id`: stable criterion id.
- `expected`: criterion-level acceptance statement.
- `evidence_type`: one of `static`, `empirical`, `measurement`.
- `environment`: required environment identifier.
- `cases`: object keyed by `case_id`; each value contains `expected`, the case-level acceptance statement, integer `expected_exit_code` (0 through 255), and `required_stage` from the selected route. Negative probes must name their intended failure and expected exit code. Stage assignment follows the real dependency: production-only acceptance may first be due at archive, never silently removed from the task contract.

The checker computes exact hashes from the contract file and from the current scope manifest generated from the `scope` path list plus current file content and executable-bit classification under `--root`. Those digests are `contract_sha256` and `scope_sha256` on evidence records. Canonical manifest lines are sorted paths formatted `relative_path:content_sha256:executable=0|1`, newline terminated; absent files use `MISSING:executable=0`.

## 4. Evidence Bundle Schema

Top-level fields:

- `task_id`: must match contract `task_id`.
- `preflight`: the JSON receipt emitted by a successful preflight, including task, contract digest, initial scope digest, revision, and UTC timestamp. This is captured before work starts.
- `implementation_started_at`: UTC timestamp no earlier than the preflight timestamp.
- `attempts`: ordered, append-only array of attempt records.

Each attempt record:

- `stage`: one of the selected route stages (`do`, `write`, `edit`, `publish`, `qa`, `compliance`, `archive`, or `quick`). Preflight does not create case-level evidence attempts.
- `timestamp`: UTC timestamp, no earlier than the previous applicable stage attempt used for the same flow.
- `actor`: nonempty producer identity. An editor must differ from the preceding writer when both stages occur. QA must differ from prior authors/implementers; compliance must differ from prior producers and QA. These checks use stage roles, not fixed array positions. Identities are review metadata, not cryptographic authentication.
- `revision`: current git HEAD when the checker ran.
- `contract_sha256`: digest of the exact contract used.
- `scope_sha256`: digest computed by the checker over the relative scope paths and current file content.
- `cases`: array of case records.

Each case record:

- `criterion_id`, `case_id`: identify the contract case.
- `observed`: observed result text.
- `status`: `pass`, `fail`, or `blocked`.
- `evidence_type`: must equal the criterion `evidence_type`; otherwise it is wrong evidence kind.
- `environment`: must equal the criterion `environment`.
- `source`: `live`, `fixture`, or `static`.
- `command`: command or check that produced the evidence.
- `exit_code`: recorded exit code.
- `artifact`: object with `relative_path` and `sha256`; path is relative to `--root`.
- The artifact object is mandatory. A hash without a resolvable regular file is insufficient.

## 5. Stage Semantics

- `snapshot`: emits current digests for attempt construction, explicitly tagged snapshot. This cannot substitute for the captured preflight receipt.
- `preflight`: validates the contract, scope list, timestamp, and readiness; emits a JSON receipt with the current timestamp and digests. Runs before implementation work and before resumed active task work. It records no case evidence.
- `do`: required latest `do` attempt covers every case due at do exactly once.
- `write`, `edit`, `publish`, `qa`, `compliance`: latest attempts for the selected route prefix must be present; each covers every case due by its stage exactly once. No code do-stage receipt is required for a content route.
- `archive`: validates the selected route, requiring an archive attempt when any case first becomes due at archive. An absent archive attempt is optional only when no case first becomes due there. Any explicitly present archive attempt participates in latest-attempt selection and downstream ordering; a failed, partial, or stale latest archive attempt blocks closure. The final selected attempt must independently cover the full task case set. L1/L2 may close without QA/compliance only where the canonical route permits that omission.
- `quick`: required latest `quick` attempt only; it must cover every contract case exactly once. Quick is standalone and cannot satisfy `do`, `qa`, or `compliance`.

Chronological ordering follows the selected route. Array order must also increase strictly between selected stage attempts, so an appended correction invalidates downstream results even within the same second. No timestamp may lie in the future or normalize to another calendar date. Contract and evidence each contain exactly one top-level JSON document; concatenated streams are rejected. A correction or new attempt invalidates downstream evidence if its position is earlier or its scope or revision no longer matches. Reviewers may inspect and cite the same hashed output without rerunning an unchanged command, but must verify each individual assertion and evidence applicability. A shared log is allowed only with distinct per-case observations.

An intermediate successful result is `STAGE_PASS`, with the pending later-stage cases listed; it never claims task completion or production acceptance. Due cases awaiting operator action remain `WAITING_OPERATOR`/blocked and never pass. Final archive cannot omit any original unsuperseded case.

## 6. Evidence Applicability Rules

- `static` criteria may use `source: static`, `source: fixture`, or `source: live`.
- `fixture` source is valid only for a criterion explicitly declared `evidence_type: static` and only for unit-level deterministic static expectations.
- `empirical` and `measurement` criteria require `source: live`; mock-only or fixture-only empirical evidence fails even if the fixture is otherwise deterministic.
- General tasks do not require production deployment or production fixtures unless the task contract itself says so.
- Existing customer-delivery stronger rules remain in force and are not weakened by this operating model.
- A later-stage attempt must not have a timestamp earlier than the latest prior-stage attempt it builds on.
- Missing coverage, duplicate coverage, stale evidence, skipped or `blocked` cases, wrong environment, wrong revision, dirty scope, contract drift, wrong evidence kind, and corrupted artifact hashes are all red conditions.

## 7. Correction and Retest Path

- Evidence bundles are append-only. Fixing a discrepancy appends a new attempt; historical attempts are not deleted.
- Historical attempts retain schema-valid scalar fields and case records, including `fail` and `blocked` statuses. Only selected latest attempts must pass and match current scope/revision; historical schema validation does not require old artifacts or digests to match current content. A waiting attempt records `status: blocked` and describes the operator dependency in `observed`.
- After any correction or new attempt, rerun the corrected stage and all downstream stages so that the selected latest attempts are internally consistent by timestamp, revision, `contract_sha256`, and `scope_sha256`.
- Ordinary implementation edits change attempt scope hashes, not the original preflight receipt. Preflight captures the before-work baseline and is never rewritten to disguise code changes. A changed requirement/scope declaration requires an explicit superseding contract and new preflight, preserving the old contract and evidence history through Return-to-Source.
- No missing legacy evidence may be treated as green. New tasks and resumed active tasks must undergo explicit `preflight` migration before case evidence is accepted.

## 8. Integration and Mandatory Gate

Direct invocation of planner, developer, tester, reviewer, compliance, writer and
editor roles must load the same immutability contract. Their responsibilities
remain distinct: planning freezes cases before work; authors correct and retest;
testing/review route findings without acquiring unrequested repair authority;
compliance independently checks all due cases and evidence freshness. Content
roles follow the selected content route. Later-stage pending cases do not block
a legitimate intermediate STAGE_PASS, and optional omitted reviews are not
silently made mandatory. Role wiring has its own regression test.

Templates for task, PRD, and compliance documents, plus commands `init`, `quick`, `plan`, `do`, `write`, `edit`, `publish`, `qa`, `compliance`, `archive`, and `auto`, must wire this gate.

- The generated mandatory stage gate is part of operating-model compliance.
- Advisory spec-graph edges cannot downgrade or skip the mandatory stage gate.
- Plans may add stricter edges but never weaker ones.
- Parent independent review is required before task completion.

## 9. Implementation Plan

1. Extend `check-live-evidence.sh` with strict mode argument parsing and legacy-mode uncertified output.
2. Add version 1 contract and evidence bundle validators matching the schemas above.
3. Implement scope manifest generation under `--root`, including relative path strings, current content hashes, and empty-scope rejection.
4. Implement per-stage required attempt selection, mandatory case coverage, timestamp ordering, revision checks, contract and scope digest checks, artifact hash checks, environment checks, and evidence-kind checks.
5. Wire templates and commands to call the strict gate.
6. Add the acceptance tests below to the framework test suite. They are planned additions; no claim is made that they have already run.

The checker verifies declared structure, hash integrity, current scope/revision, and chronology. It cannot authenticate a fabricated log, retroactive timestamp, producer identity, or deliberately incomplete scope; independent review must verify those semantics. It never executes commands supplied in evidence. A small implementation helper may sit beside the existing gate; this is not a second gate or skill.

## 10. Required Acceptance Tests

The implementation must add automated acceptance tests for at least:

- valid static flow passes strict `do` and downstream gates;
- valid empirical/measurement flow passes with live evidence;
- missing contract case coverage fails;
- dirty scope after an evidence attempt fails;
- evidence recorded at the wrong git revision fails;
- corrupted or missing evidence artifact hash fails;
- contract drift changes `contract_sha256` and fails;
- evidence bundle uses wrong `evidence_type` or wrong source and fails;
- empirical evidence supplied only from mock fixtures fails;
- stale QA after a corrected `do` attempt fails;
- correct retest path appends attempts chronologically and reaches green;
- legacy invocation still behaves as explicitly uncertified legacy inspection.

These tests are requirements of this contract, not records of previously executed tests.

Independent-review regression requirements: reject invalid/failed/duplicate JSON documents before or after a valid document in both inputs; reject normalized impossible dates in both timestamp validators; accept canonical L1/L2 routes without synthetic skipped receipts; reject route downgrade, metadata mismatch, and missing mandatory L3/L4 reviews; exercise actual content stages, missing content cases, independent review, and later publication pending. Standalone content cannot claim structured certification.

## 11. Source verification checkpoint (2026-09-08)

The coordinator reran the six-file targeted Bats set (evidence loop, QA bypass,
provenance, immutability wiring, TDD wiring, heartbeat): 76/76 passed. This includes
the structured checker suite's 48 Python scenarios. Four additional receipt
snapshot tests passed; the new three role-wiring tests passed after initial RED.
Independent role review caught two due-stage/content-route wording conflicts;
both were corrected and the reviewer confirmed closure with the three tests.

Independent receipt-boundary review passed 18 runner, 31 backend and four
framework tests and found no important remaining defect in that boundary.
Real isolated Claude and Codex probes then read an unpredictable operator
response, wrote the exact response value, and invoked this framework heartbeat
writer; both persisted the matching receipt tuple. These are transport/protocol
proofs, not proof of completing an application task or applying its answer.

ShellCheck passes for changed shell helpers at the S1 warning threshold. Bandit
1.9.4 at the S2 medium/high threshold reports zero medium/high findings for the
new receipt helper and two Python test files. Gitleaks 8.30.1 (release asset
verified against the SHA-256 pinned in this repository's CI) reports no findings
in agents, commands, skills, templates and dev-tools/lib. Stack/history changed-line
gates pass. This is scoped source verification, not full cross-platform CI,
live framework rollout, task compliance, or authorization to deploy production.
