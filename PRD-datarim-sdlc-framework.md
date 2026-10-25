# Datarim SDLC Framework PRD: Autonomous Evolution Amendment

## Authority and scope

This amendment specifies the evolution decision and application contract for
`/dr-auto` and `/dr-orchestrate`. It also specifies the interactive path and the
framework versus consumer workspace boundary. Other framework behavior remains
governed by the existing runtime contracts.

Operator decision, 2026-10-25 (quoted from the approved work brief):

> evolution must happen **automatically** during `/dr-auto` and
> `/dr-orchestrate` runs. The agents themselves decide, per proposal, whether an
> improvement is applied or not, and take the best decision without waiting
> for the operator.

The same decision authorizes this Class B approval-model amendment and the
contract updates for versioned QA charters and case environment invariants.

## Required behavior

1. A passing `/dr-compliance` creates or refreshes the reflection and then
   executes an explicit evolution decision step when effective autonomous mode
   is active. `/dr-auto` and `/dr-orchestrate` both reach this step through
   `/dr-compliance`. An interactive run presents pending proposals for a human
   decision. `/dr-archive` presents unresolved proposals even if it reuses a
   fresh reflection.
2. Each proposal receives exactly one current decision: `apply`, `decline`, or
   `defer`. The decision records recurrence evidence, impact, blast radius,
   reversibility, applicable gate results, and rationale. A Class A proposal
   may be applied after all gates pass. A Class B proposal requires this PRD
   update or an equivalent project contract draft and concurrence from an
   independent blind reviewer that did not write the change. Without
   concurrence the proposal is deferred with a reason.
3. Before any instruction-surface write, the agent checks the proposed bytes
   for stack neutrality, history neutrality, and English-only prose in an
   isolated candidate tree. It then runs Bats tests reading every touched
   candidate file and the full Bats suite in sequence before publishing any
   candidate bytes to the live instruction surface. A failed gate removes only that proposal's changes and records
   `declined: gate <name> failed`; no partial application remains.
4. Every decision is appended to the current KB's
   `datarim/history/evolution-log.md`; the reflection's proposal status becomes
   `applied`, `declined`, or `deferred`. The `/dr-auto` summary reports these
   outcomes with evidence rather than requesting pending approval.
5. The target is resolved from the workspace root. The Datarim framework
   source repository is the framework KB: its changes go to a signed feature
   branch, PR, normal review, and CI. Every other workspace is a consumer KB:
   its executable changes go to `datarim/local/` with recorded upstream base
   hashes, while project rules may also be written to project-owned `AGENTS.md`.
   The installer composes this overlay into the runtime and all client adapters.
  Every reusable
   consumer proposal, including a locally applied one, is separately recorded
   as a promotion candidate in that consumer KB's evolution log. Its local
   decision and framework promotion status are distinct fields. Consumer
   agents never write or push the public framework repo. The cross-KB digest
   exposes these logged candidates to framework work.
6. `datarim/config/evolution.yaml` may set `auto_apply: false`. Absence means
   `true` in auto and orchestrator modes. Disabling automatic application still
   requires decisions, logging, and clear `deferred` status.
7. The L1 Inline Resolution Rule governs task-local gaps and does not authorize
   framework evolution. The evolution decision step has its own gates and
   scope rules.

## Related contract updates

- A superseding acceptance contract names the prior version and the new
  version. Before QA records PASS against the new contract, the QA charter
  declares that same new version and covers the new contract's required
  criteria. A charter for the superseded version cannot certify the successor,
  even if an older run passed. QA refuses PASS until a current charter and
  evidence are available.
- A case `environment` precondition names an observable invariant over the
  verification window and the guard or measurement that proves it at the time
  the case runs. The case records the guard result as evidence. A mechanism
  (such as a paused scheduler) may be an example, but cannot substitute for
  the protected invariant; changing the mechanism does not silently waive the
  invariant or its proof.

## Acceptance evidence

- Tests show the evolution step is reachable from both autonomous routes and
  that interactive archive presents unresolved proposals on a fresh reflection.
- Tests cover decision status, local-only consumer routing, the opt-out, and
  refusal when required gates or blind review fail.
- The QA charter and environment template contracts have regression tests.
- Per-proposal tests and the sequential full Bats suite pass before a proposal
  is recorded as applied.

## Finalization amendment

Operator extension, 2026-10-25: the same release adds `/dr-finalize` and an
optional autonomous route through finalization. The design selects a separate
command that invokes or reuses `/dr-archive` first. `/dr-archive` keeps its
knowledge-record contract; `/dr-finalize` coordinates delivery and cleanup.

`/dr-finalize` is idempotent. It records `done`, `skipped: <reason>`,
`failed: <reason>`, or `not measured` for each of nine steps: archive,
documentation publication, task-owned commits and pushes in every touched
repository, safe return to each repository's observed default branch,
task-created worktree removal, merged task-branch removal, task-owned
temporary artifact removal, configured tracker completion, and one final
human report. A failed step blocks dependent steps only. Foreign dirty files
are reported and preserved.

The task records its created worktrees, branches, temporary files, caches,
processes, and containers in a per-task ownership ledger under `datarim/`
when they are created. Cleanup accepts only exact ledger entries. Branch
deletion additionally requires clean checkout state and proof that the branch
is represented in the observed default branch, including a squash-merge
content check. Unmerged branches and unrecorded items are preserved and
reported. The Jev and host safety floor remains authoritative.

Tracker integration and final-status mapping come from project configuration.
If unavailable, the tracker step is `not applied: <reason>` in the final
report, with no invented completion claim.

### Autonomous finalization setting

The setting is `autonomy.finalize`, with `off` (default), `on_request`, and
`always`. Project configuration is `datarim/config.yaml`; user-global
configuration is `$XDG_CONFIG_HOME/datarim/config.yaml` or
`~/.config/datarim/config.yaml`. These paths are independent of whether
Datarim was installed in a project or linked from shared skills. A task's
explicit request is recorded as `finalize_requested: true` in its init-task
frontmatter. Project mode overrides user-global mode; absence falls back to
`off`. A task request activates `on_request`, but never overrides an effective
`off`; `always` activates without a task request. The resolver reports the
effective mode, source, task request, and whether finalization will run.

When enabled, `/dr-auto` and `/dr-orchestrate` dispatch `/dr-finalize` after
their passing compliance, reflection, and evolution step. When disabled, they
retain the current terminal point before archive. `/dr-doctor` and
`/dr-status` display the effective value and its source.

Acceptance tests cover each setting level and precedence, all three routing
values in both autonomous entry points, refusal to delete unmerged branches
and unledgered items, and `not applied` for an unconfigured tracker.

## Project-local overlay amendment

Operator extension, 2026-10-25: every consumer workspace can evolve its own
skills, commands, agents, templates, and dev-tools without writing to the
fetch-only framework clone. The project tracks overrides in `datarim/local/`.
Each file carries its upstream base SHA-256 in `datarim/local/manifest.json`;
`null` denotes a file created only in the project. A helper registers new
entries at creation. Manual files without a manifest entry are refused until
registered, preventing an unknown comparison baseline.

The installer composes upstream and overlay at install/update time in the
project's `.datarim-runtime`. Composition happens before client adapters are
generated, so Claude, Codex, and Cursor entrypoints expose the same effective
commands and opted-in discoverable skills. It is chosen because the current
client adapters point to project-local runtime files and can reuse those
paths; load-time resolution would require changing every client and entrypoint.
For matching relative paths the overlay bytes win; new paths are added.

Updates never mutate `datarim/local/`. When a recorded upstream base hash
differs from the incoming upstream file, the installer emits a drift report
and still composes the override. A direct edit to a managed installed runtime
file is refused before any replacement, with the exact path and instruction
to register that content in the overlay. The runtime manifest records hashes
for managed runtime files and the overlay digest, so neither direct edits nor
overlay changes are hidden by an unchanged-source short circuit. Uninstall and
rollback preserve the overlay. Project-local composition also applies when
the source runtime is shared or globally linked; no other project's overlay
is consulted.

Autonomous evolution in a consumer KB writes executable changes to this
project overlay and a separate promotion-candidate record. The source clone
remains fetch-only. Framework-KB evolution still writes source changes on a
feature branch and PR. `/dr-doctor` reports overlay presence/count, upstream
base drift, and direct runtime edits. Tests cover adapter composition, update
byte preservation and drift, direct-edit refusal, consumer routing, and
uninstall/rollback preservation.
