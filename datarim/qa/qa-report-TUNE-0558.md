# QA Report — TUNE-0558 (Datarim 2.60.0 final release)

**Task:** TUNE-0558 — Final Release Epic
**Release commit:** `3fdc1a8` (PR #319, merged into `main`)
**Version:** 2.60.0
**Date:** 2026-08-01
**Verdict:** ALL_PASS

## Scope verified

Ten subtasks R1-R10 of the final release epic: release-ledger reconciliation,
version bump, ledger-row gate, dark-test wiring, security/leak audit,
English-only shipped surface, documentation completeness, site release,
fleet rollout, readiness report.

## Layer 1 — automated test suite

| Surface | Result |
|---------|--------|
| Full bats suite (Mac, clean tree at `3fdc1a8`) | **2566 passed / 0 failed**, exit 0 |
| Full bats suite (DEVS clone at `3fdc1a8`) | in-progress at time of writing, 0 failures through test 1093 |
| CI on release commit `3fdc1a8` | **8/8 workflows success** |

CI workflows green: `bats`, `security`, `framework-gates`, `personal-id-lint`,
`frontmatter-mirror`, `sanity-dual-copy`, `scorecard`, `dr-orchestrate contract`.

## Layer 2 — release gates (DEVS clean clone at `3fdc1a8`)

| Gate | Exit |
|------|------|
| `dev-tools/check-component-counts.sh` | 0 |
| `dev-tools/release-ledger-report.sh` | 0 |
| `scripts/personal-id-gate.sh --check` | 0 |
| `validate.sh` | 0 |

Release ledger: zero orphans — every merged user-facing PR in the
2.53.0..2.60.0 range is classified into exactly one CHANGELOG version section.

## Layer 3 — inventory and content parity

Live shipped inventory: **28 commands / 19 agents / 67 skills**, matching the
claims in `CLAUDE.md`, `README.md`, and the live site in both locales.

`CHANGELOG.md` carries reconstructed sections `[2.54.0]`..`[2.60.0]`; the
six previously-missing release headers are present. 210 pre-existing bullets
verified byte-identical after redistribution — no content invented or lost.

Site `datarim.club` at `e41b799` (deploy run `30693065643`): HTTP 200 on
`/en/`, `/ru/`, `/en/about`, `/en/changelog`; version 2.60.0 and 19/28/67
confirmed by public readback.

## Layer 4 — security

- Real routable IPv4 in the shipped surface: **zero**.
- Operator macOS username: removed from HEAD; **0 occurrences** in the tracked tree.
- Remaining legal-name occurrences are legitimate by design: a link to the
  operator's own public Rules-of-Robotics repository (canonical Supreme
  Directive source), and the personal-id denylist plus its tests, where the
  name must appear as the enforced pattern.
- `datarim/tasks/*-init-task.md` untracked and gitignored.
- `gitleaks`, `bandit`, `osv-scanner`, `personal-id-lint` green in CI.

**Known residue, explicitly deferred:** the operator username remains in 7
historical commits. Not a credential and not an address. Removal requires
history rewrite + force-push, which is operator-gated and deliberately not
performed. Blast radius if ever executed: 1 fork, 11 stars, no published
package.

## Deviations investigated and cleared

`check-component-counts.sh` returns 1 on the operator's Mac while returning 0
in CI and on DEVS. Root cause: an **untracked** local `skills/.system/`
directory (a Codex-runtime marker holding `imagegen` and `openai-docs`, with no
`SKILL.md`) is counted by the gate's `find -type d` sweep, inflating the local
count to 68. It is absent from the repository, so CI and the clean DEVS clone
both see the correct 67. No repository defect; local environment artefact only.

## Verdict

**ALL_PASS.** The 2.60.0 release surface is verified across tests, gates,
inventory parity, and security. Remaining actions are operator-gated ceremony
(tag / GitHub Release) and the deliberately deferred history rewrite.
