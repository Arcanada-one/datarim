---
name: prod-readiness-probe
description: Deploy-class prod-readiness gate: read-only test/prod runner symmetry probe; blocks merge at /dr-qa and archive at /dr-archive until prod is verified.
current_aal: 1
target_aal: 2
---

# Prod-Readiness Probe — Deploy-Class Verification Gate

**Role**: Reviewer / Developer Agent (invoked from `/dr-qa` and `/dr-archive`).

## When this skill is active

Only for **deploy-class** tasks. A task is deploy-class when
`dev-tools/check-deploy-class.sh --task-description <td>` exits 0 — i.e. it
touches a deployment surface (systemd unit files, sudoers, CI cutover jobs,
`.env-deploy` templates). Non-deploy-class tasks return verdict **SKIP** and the
gate is a no-op.

The motivating failure: a worker-cutover passed every check on the test runner,
then failed on the first production `sudo` command because the prod runner's
sudoers lacked the NOPASSWD rules the test runner already had. The lesson — the
test↔prod runner asymmetry was never verified before merge — is exactly what
this gate forces.

## The contract: never propose merge or archive on unverified prod

The framework MUST NOT recommend merging a deploy-class change, and MUST NOT
archive the task, until the production runner has been verified ready (or the
operator has explicitly confirmed out-of-band verification). Prediction and
research happen first; merge/archive happen only after a PASS.

## prod is hard-gated — read-only only

Every automated probe action is **read-only research**. The exhaustive
allow-list of commands the probe may run on a runner:

- `sudo -l` (enumerate the deploy user's NOPASSWD rules — does not execute them)
- `systemctl status <unit>` / `systemctl is-enabled <unit>` / `systemctl is-active <unit>`
- `ss -ltn` or `netstat -ltn` (listening ports)
- `redis-cli info server` (redis version)
- `node --version` (and equivalent `--version` queries for other runtimes)

The probe is a **sensor, never an actuator**. It performs NO writes, NO service
restarts, NO sudoers edits, NO file copies. When the probe finds a gap (e.g. a
missing NOPASSWD rule on prod), it **predicts the impact and reports it** — the
remediation is an explicit operator action, never performed by the framework.

## Verdict vocabulary

| Verdict | Meaning | /dr-qa action | /dr-archive action |
|---------|---------|---------------|--------------------|
| `SKIP` | Not a deploy-class task — probe not invoked. | Allow propose-merge | Allow archive |
| `PASS` | Probe ran; test-runner actual, prod-runner actual, and the declared contract (if present) all align. | Allow propose-merge | Allow archive |
| `FAIL` | Probe ran and found an asymmetry (missing sudoers rule, wrong runtime version, missing unit, port conflict). | Forbid propose-merge | Forbid archive until resolved |
| `BLOCKED` | Probe could not run its read-only sequence (prod unreachable, SSH timeout, sudoers unreadable) AND no operator confirmation was given. | Forbid propose-merge | Forbid archive until operator confirms out-of-band verification |

`BLOCKED` never auto-resolves to `PASS` on an unreachable host — silence is not
success. The operator may convert `BLOCKED` → proceed only by explicitly
confirming verification through another channel; record that confirmation.

## Hybrid execution

**Deterministic mode** — when the consumer project authors an optional
`datarim/deploy-readiness.yml` (validated by
`dev-tools/check-deploy-readiness.sh --validate-yaml`): the probe reads the
declared runners, sudoers command shapes, units, ports, and version floors, runs
exactly the read-only allow-list checks above against the `test` and `prod`
runners, and performs a three-way comparison (test actual vs prod actual vs
declared). Any asymmetry → `FAIL`; an unreachable runner with no operator
confirmation → `BLOCKED`; full alignment → `PASS`.

**Fallback mode** — when the contract is absent: the probe falls back to an
agent-driven checklist investigation guided by the same items below. The agent
performs the read-only checks against both runners, records the evidence, and
maps findings to the same four verdicts. Absence of a contract does NOT default
to `SKIP` for a deploy-class task — the agent must still produce symmetry
evidence.

### Checklist (what to verify, both modes)

1. **sudoers symmetry** — every NOPASSWD command shape the deploy needs exists
   on `prod` exactly as it does on `test` (`sudo -l` on each, diff the relevant
   rules). This is the DEV-class gap.
2. **PATH parity** — the deploy/service user's PATH on prod includes the same
   tool locations as on test.
3. **Listening ports** — ports the new service binds are free on prod (or bound
   by the expected unit), matching the test expectation.
4. **Systemd units** — required units exist and are `enabled` / `running` per
   the contract (a brand-new cutover unit is legitimately absent on first
   deploy — note it, do not fail on first-cutover).
5. **Runtime versions** — node / redis / other runtimes meet the declared floor
   on prod.

## Contract schema (`datarim/deploy-readiness.yml`)

Project-authored, OPTIONAL, **not shipped by the framework**. Follows the
`accepted-risk.yml` / `ecosystem-sync/registry.yml` awk-friendly convention
(`schema_version` header, 2-space indent, one `key: value` per line, lists as
`- item`, no flow-maps, secrets forbidden). Full schema and a worked example
live in `creative/creative-...-datamodel-deploy-readiness.md` and the validator
enforces: secret-prohibition, exactly `{test, prod}` runners, sudoers
command-stem allow-list (`systemctl|cp|mkdir|journalctl`), port typing, and
`>= ` version floors. The validator reads the file as data only (no eval).

## Output (gate report)

Record in the QA / archive report: the verdict, the runner pair probed, the
exact read-only commands run, the captured output, and — on `FAIL` — the
specific asymmetry plus the predicted production impact and the operator
remediation required. A deploy-class wish marked met without a recorded probe
verdict is a gate finding.
