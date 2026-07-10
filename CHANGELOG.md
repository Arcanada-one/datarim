# Changelog

All notable changes to the Datarim framework are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.52.0] — 2026-07-10

### Added

- **New Reference skill `image-prompting`** — a reusable playbook that turns a content brief into a precise, repeatable prompt for instruction-following image generators (the gpt-image family and equivalents): blog/article covers, video thumbnails, social-post images, illustrations, infographics/diagrams, logo marks, and edits of existing images. Covers the full method — intake → spec → prompt → verify loop, prompt anatomy, composition, style/medium, camera/lens, light, mood, palette, text-in-image constraints, negative constraints + invariants, native aspect/size handling, iterative refinement, plus a `prompt-templates.md` fragment with nine fill-in-the-blank templates and a ship-readiness verification checklist. Wired into the `writer` and `editor` agents (load-when-needed) and the agent↔skill dependency visual map. Completes the deferred merge of TUNE-0466 (skill authored + archived COMPLIANT, branch merge was an outstanding operator action). (TUNE-0466, TUNE-0480)

### Changed

- **Skill registries synced to 60 skills** (`CLAUDE.md`, `README.md`, `documentation/reference/skills.md`) with the "supporting fragment directories" count corrected to 13 and an inline definition. (TUNE-0466, TUNE-0480)

### Fixed

- **English-only shipped surface passes cleanly.** Canonical Russian schema/section names and operator-output tokens cited verbatim in `skills/expectations-checklist/SKILL.md` and the RU TTS-normalization examples in `skills/publishing/SKILL.md` (a content-work skill) are now wrapped in `allow-non-ascii` markers, so `check-body-english.sh` reports PASS across the whole `commands`/`skills`/`agents` surface without relying on the validator's advisory tolerance. (TUNE-0480)


## [2.51.1] — 2026-07-09

### Fixed

- **Codex skill fanout is atomic.** `install.sh --with-codex` now builds generated `~/.codex/skills` adapters in a staging directory and swaps the completed tree into place, preventing transient `missing SKILL.md` startup warnings when Codex launches while the installer is regenerating wrappers.
- **Codex skill wrapper source paths point at nested SKILL.md files.** Generated adapters for `skills/<name>/SKILL.md` now reference `code/datarim/skills/<name>/SKILL.md` instead of the invalid `code/datarim/skills/SKILL.md`, making diagnostics and manual source lookup accurate.

## [2.51.0] — 2026-07-08

### Fixed

- **Coworker model routing is split by task semantics.** Runtime delegation now uses `doc-read` and `classifier` with `deepseek-v4-flash` for literal documentation extraction and short routing only, while meaningful Datarim draft generation uses `datarim-write` with `deepseek-v4-pro`.
- **Adversarial verification no longer routes through Coworker.** `/dr-verify` rejects external coworker providers such as `deepseek`; AC verification, hidden-gap discovery, architecture judgment, root-cause analysis, and other semantic review stay in the selected agent runtime.
- **Legacy Coworker profiles fail closed.** `code`, `codex`, `social`, and legacy `datarim` are documented as disabled Arcanada runtime defaults; source-code reading and voice-bearing content remain native to the selected agent model.
- **Security workflow shellcheck install is resilient to transient runner apt source failures.** The shellcheck jobs now use a preinstalled binary when available and disable broken Microsoft apt source entries before installing Ubuntu's `shellcheck`, preventing external apt repo drift from blocking releases.

## [2.50.2] — 2026-07-06

### Fixed

- **Installer bypasses RTK `find` shims for compound predicates.** `install.sh --with-codex` now resolves a real `find` binary (overrideable with `DATARIM_FIND_BIN`) before cleaning Codex skill wrappers and listing bundled plugins, preventing RTK shim failures when Codex launches the installer with RTK shims already in `PATH`.

## [2.50.1] — 2026-07-06

### Fixed

- **Codex installer self-heals stale temporary probe hooks.** `install.sh --with-codex` now replaces missing `/tmp/*probe*` commands in `~/.codex/hooks.json` with the canonical `~/.local/bin/coworker-hook-guard`, preventing repeated `PreToolUse hook exited with code 127` failures after `/tmp` is cleaned. Valid custom hooks are preserved.

## [2.49.0] — 2026-06-28

### Changed

- **BREAKING (canon): the documentation root is renamed `docs/` → `documentation/`** and split
  into the four Diátaxis categories (`tutorials/`, `how-to/`, `reference/`, `explanation/`),
  with `archive/`, `evolution/`, `release-audit/`, `ephemeral/` as reserved sibling directories
  (a Diátaxis category may NOT take these names). The framework's 19 root docs moved into their
  categories; history is preserved via `git mv`. `documentation/` is now the single canonical
  documentation root ecosystem-wide — the `diataxis-docs` mandate, the `/dr-init` scaffold, the
  Documentation Taxonomy Mandate, and the `/dr-optimize` drift detector all target it.
- **Hard-flip compatibility:** the drift detector now treats a repo still on legacy `docs/` as
  drift. Consumer repos on `docs/` should self-migrate by running
  `/dr-doctor --scope=docs-migration` (idempotent, opt-in, rollback-safe `git mv` + split +
  reference rewrite).

## [2.48.0] — 2026-06-28

**Stop the four shipped framework surfaces from writing the abolished `backlog-archive.md`; add a data-loss-safe terminal-task pruner wired into `/dr-doctor` and `/dr-dream`.** Root-cause fix for completed tasks accumulating in `backlog.md` (68 terminal entries / 107 KB found 2026-06-28). (TUNE-0462)

### Fixed

- **`commands/dr-archive.md` — Step 3 + Cancellation no longer write `backlog-archive.md`.** Step 3b/3c and the Cancellation block told the archiver to write the abolished `backlog-archive.md` (`## Completed` / `## Cancelled`), directly contradicting the same file's Step 7 («abolished v1.19.1») and the canonical SKILL `datarim-system/backlog-and-routing.md`. Because «remove from backlog» was coupled to writing an abolished file, terminal tasks were marked `done` in place and never removed. Both paths now route completion prose to `documentation/archive/{area}/archive-{ID}.md` and cancellation to `documentation/archive/cancelled/archive-{ID}.md`; the `backlog.md` entry is simply removed. (TUNE-0462)
- **`skills/datarim-system/SKILL.md` § Task Disposition Patterns — fourth contradiction removed.** The disposition table still routed `completed`/`cancelled`/`absorbed`/`superseded` prose to the abolished `backlog-archive.md`; all four rows now route to `documentation/archive/{area}/archive-{ID}.md`. (TUNE-0462)

### Added

- **`dev-tools/prune-backlog-terminal.sh`** — a standalone, data-loss-safe pruner that removes terminal-status (`done`/`archived`) entries from `backlog.md`. A terminal entry **with** a corresponding `documentation/archive/{area}/archive-{ID}.md` is pruned; a terminal entry **without** an archive doc is **preserved and surfaced** (never silently dropped — Supreme Directive Law 1). Dry-run by default (`--check`); writes only under `--fix`. Standalone tool, not a branch inside `datarim-doctor.sh` (Validation Discipline). (TUNE-0462)
- **`/dr-doctor` backlog terminal-task cleanup pass** — invokes the pruner in its dry-run/`--fix` model; surfaced archive-less IDs route to a `MAINT-*` follow-up. (TUNE-0462)
- **`/dr-dream` propose-then-apply terminal-task cleanup** — surfaces the terminal-entry count at Step 7 (Lint), proposes the prune at Step 9 (Consolidate), applies only on approval. (TUNE-0462)
- **Tests** — `tests/pre-archive-check.bats` T48/T49 (archive removes the backlog line; never re-creates `backlog-archive.md`) and the new `tests/prune-backlog-terminal.bats` (12 cases covering the prune / preserve-and-surface / leave-pending matrix). (TUNE-0462)

## [2.46.0] — 2026-06-23

**Compliance Step 7 stale-test-count classification rule + deterministic classifier-script template.** Two Class-A evolution follow-ups from reflection-AGENT-0086 land in one release.

### Added

- **`skills/compliance/SKILL.md` Step 7 — stale test-count classification (non-blocking).** When a commit message claims N/N tests pass but a live re-run reports M/M with M > N, and the additional tests are grep-verifiable in the commit, the discrepancy is classified as informational non-blocking (a normal polish-test addition committed after the run that produced the message) — the live count is recorded as authoritative, not treated as a re-commit trigger or compliance failure. (TUNE-0433)
- **`templates/classifier-script-template.sh`** — a minimal Bash template for a deterministic type-signal classifier: header, `--message-file` parse with an S1 guard, a `msg_matches()` helper, priority-ordered comment > question > task > ambiguous stubs, an exit-code table, and a mandatory-priority note. Generalises the AGENT-0086 `classify-message.sh`. (TUNE-0434)

### Note

- v2.45.0 → v2.46.0 also carries the already-merged **verification_mode durability mechanism** (TUNE-0454, commit `35a5f9a`): a per-wish `verification_mode ∈ {one-off, reproducible}` axis orthogonal to `evidence_type`, with a `verification-not-wired` gate (advisory at `/dr-qa`, hard at `/dr-compliance`) requiring a committed `evidence_artifact` for reproducible wishes. Schema is additive/opt-in (v1/v2 unaffected; absent → one-off). See expectations-checklist schema v3.

## [2.45.0] — 2026-06-23

**`/dr-auto` L1 doc-only fast-path + deferral-prose path guard.** Two Class-B follow-ups from reflection-VERD-0059.

### Added

- **`/dr-auto` L1 doc-only fast-path** — for a narrow class (one markdown file, small, no runtime behaviour) the orchestrator now runs a lightweight inline style/banlist + cross-reference check and writes a `qa-stub` artefact instead of silently skipping `/dr-qa`; the compliance Documentation Checklist recognises the stub (no spurious "QA report absent" advisory). (TUNE-0445)

### Fixed

- **`dev-tools/check-deferral-prose.sh` `--file` guard** now accepts paths containing spaces while keeping path-traversal protection (explicit `..` and control-character rejects); bats regression added. (TUNE-0446)

## [2.44.0] — 2026-06-22

**`/dr-save` resume block — `/dr-continue {SESSION-ID}` copy-paste command + task-name label.** The resume block prints `/dr-continue {SESSION-ID}` as the deterministic single-session selector (defeats latest-by-mtime foreign-session resume in a shared workspace), annotated with a sanitised task-name from the active-task index and a saved-time derived from the session id. Multi-task saves list only the other active ids; single-task suppresses the line. Producer-only — `/dr-continue` already accepts `{SESSION-ID}`, no schema change. New byte-identity mirror gate `dev-tools/check-resume-block-mirror.sh` locks the two resume-block fences. (TUNE-0441)

## [2.43.0] — 2026-06-20

**Spec-traceability embedded in the pipeline.** The spec-graph is now woven through the pipeline stages so PRD → plan → implementation traceability is carried structurally rather than reconstructed after the fact. (TUNE-0435)

## [2.42.0] — 2026-06-19

**Spec-traceability R8 — CI + pre-commit enforcement, `/dr-spec` command, 4-surface sync.** Adds CI and pre-commit enforcement of spec-traceability, documents the `/dr-spec` command, and synchronises the contract across its four surfaces. (TUNE-0432)

## [2.41.0] — 2026-06-18

**POSIX re-exec preamble + multi-distro Docker install-matrix harness.** install.sh now includes a POSIX-safe re-exec preamble (before `set -euo pipefail`) that transparently re-execs under bash when invoked via `sh`; prints an actionable error and exits 2 when bash is absent. Verified across 7 Docker images (rockylinux:9, almalinux:9, fedora:latest, redhat/ubi9-minimal, debian:stable-slim, ubuntu:latest, alpine:latest) via the new `dev-tools/install-matrix.sh` harness — claude, codex and cursor vendors all install (vendor-aware post-install assertions). RedHat family installs — previously broken when invoked via `sh` — now pass. Codex install on Windows (Git Bash) is fixed: an unmaterialised `AGENTS.md` symlink now falls back to copying `CLAUDE.md`. Added TDD preflight bats and per-vendor post-install container assertions. Docs updated: bash + git prerequisites and "run via bash, not sh" in README and getting-started.md; OS matrix in use-cases.md.

## [2.39.0] — 2026-06-16

Pre-archive unpushed-commits gate. `/dr-archive` now stops when a touched repository has committed-but-unpushed commits and the task type is `bugfix`/`feature`/`refactor`, closing the archived-but-unmerged gap (Step 0.1 covered only the dirty working tree).

### Added

- **`/dr-archive` Step 0.12 — Pre-Archive Unpushed-Commits Gate** — a sibling sub-step of Step 0.1 (not a rewrite). Per touched repo it runs the new detector and, on committed-but-unpushed commits for an in-scope task type, halts with a three-way prompt: Push / Verify cherry-picked or merged elsewhere / Accept loss (recorded in the archive doc Known Outstanding State section, never a silent continue).
- **`dev-tools/check-unpushed-commits.sh`** — detection helper emitting `stop` / `advisory` / `clean`. Comparison base resolves `@{u}` then `origin/<default-branch>` via `git symbolic-ref` then last-resort `origin/main`; fail-open on an unresolvable base (detached HEAD, no origin, shallow clone) so it never false-STOPs an archive.
- **`tests/check-unpushed-commits.bats`** — 20 contract cases (trigger set, base-resolution chain, fail-open edge cases, spec-lint of the Step 0.12 prose).


## [2.37.0] — 2026-06-14

Artifact Language Policy. The free-generated body of runtime artefacts (creative / PRD / plan / the analytical body of archive / reflection / compliance-report) now defaults to English, with an operator-configurable per-project override. (Version 2.35.0 was a parallel-session duplicate of this entry and is intentionally skipped — see the version note under 2.36.0.)

### Added

- **`CLAUDE.md` § Artifact Language Policy** — declares the English default for the free-generated body of runtime artefacts, adjacent to the English-Only shipped-surface section. The directive is auto-loaded into context at generation time; the coworker delegation path mirrors it via a new §12 in `skills/coworker-context/SKILL.md`.
- **Operator-configurable language override, no code** — the default is overridable per project with a single documented line in the consumer's own `CLAUDE.md` § Project-Specific Configuration (`Artifact language: <lang>`); a secondary `DATARIM_ARTIFACT_LANG` convention is documented for shell-aware coworker call sites. No new validator, no config file, no change to the closed init-task schema.

### Fixed

- **network-exposure gate no longer false-blocks init-task-only tasks** — at early pipeline stages a task may have only an init-task artefact (no priority/type by schema); the tiered gate now resolves to `skip` (or `advisory_warn` when a network-diff signal is present) instead of fail-closing to `hard_block`. Fail-closed is preserved for genuinely malformed task descriptions. Three new regression tests pin the contract.

### Excluded

- The English default never touches verbatim operator input (init-task brief and append-log), the intentionally operator-facing canonical sections, or ordinary user-project content — content-work skills and commands stay exempt.

## [2.36.0] — 2026-06-14

`/dr-auto` surfaces the compliance outcome before the CTA.

### Changed

- **`commands/dr-auto.md`** terminal-cleanup step now prints one line stating how `/dr-compliance` resolved — the verdict (`COMPLIANT` / `COMPLIANT_WITH_NOTES`) when a compliance stage ran, or a skip-by-design reason at complexity levels whose routing has no compliance stage — immediately before the call-to-action block. Previously the operator saw only a bare archive CTA, which read as "compliance is never proposed".

> Version note: 2.35.0 was assigned in a parallel session to an earlier draft of the Artifact Language Policy and superseded by 2.37.0; the number is intentionally not reused.

## [2.34.0] — 2026-06-14

Self-enforcing `/dr-auto` dispatch contract + navigation-map drift fixes.

### Added

- **Self-enforcing `/dr-auto` dispatch contract** — the `commands/dr-auto.md` Step 5 re-assert sub-bullet is promoted from advisory prose to a mandatory pre-dispatch MUST-gate. Before spawning any stage subagent the orchestrator MUST run `auto-mode-marker.sh reassert` as the first action of every per-stage dispatch.
- **Regression lint `check-dr-auto-reassert-wiring.sh`** — a deterministic shell lint scans `commands/dr-auto.md` Step 5 and exits 1 whenever the executable `auto-mode-marker.sh reassert` invocation regresses to prose-only. Registered in CI (`.github/workflows/dev-tools-lint.yml`). Fence-exclusion logic ensures illustrative fenced blocks do not false-pass.
- **`tests/check-dr-auto-reassert-wiring.bats`** — 3 tests pinning the lint contract: passes on the wired spec, fails on a prose-only synthetic fixture, exits 2 on a usage error.

### Changed

- **Visual-map drift fixes** — `command-dependencies.md` is registered in the routing-invariants drift-mapping, and a `/dr-compliance` row is added to the panels-and-quality Quality Rules table.

## [2.33.0] — 2026-06-14

Autonomous-mode marker resilience. The `/dr-auto` orchestration marker `.auto-mode-active` could vanish mid-cycle during subagent dispatch (a spawned subagent then ran in fail-safe non-auto, correctly but unexpectedly), and the `DATARIM_AUTO_MODE` env-var is not inherited by Agent-tool subagents — so even an intact marker file did not activate the mode for a spawned subagent. This release closes both root causes (Class B — auto-mode activation contract change).

### Added

- **`dev-tools/auto-mode-marker.sh`** — pure-shell helper with two verbs: `reassert` (idempotently restores a vanished or stale marker before a dispatch; a true no-op on a valid marker, so TTL-staleness checks are not perturbed) and `subagent-active` (decides whether a spawned subagent should run autonomously from a valid marker file + task-id match + an explicit prompt auto-signal, without requiring the inherited env-var). The marker path is centralised in a single `MARKER_RELPATH` constant for forward-compatibility with per-task namespacing.
- **`tests/dr-auto-marker-resilience.bats`** — six regression tests: re-assert restores a vanished marker; re-assert is idempotent; a subagent activates without the env-var; fail-safe is preserved on a true mismatch (no marker and no signal); non-auto on a different task-id; non-auto with a valid marker but no auto-signal.

### Changed

- **`skills/autonomous-mode/SKILL.md`** § "When this skill is active" — adds a "Spawned subagents (relaxed activation)" sub-rule: a spawned subagent whose prompt carries an explicit auto-signal activates from a valid marker file + task-id match alone, no inherited env-var required. The top-level cycle still requires all three conditions.
- **`commands/dr-auto.md`** Step 5 — the dispatcher re-asserts the marker before each subagent dispatch and carries the auto-signal into the subagent prompt.

## [2.32.0] — 2026-06-14

Public-surface de-personalisation (Class A — shipped-surface privacy gate).

### Security

- **Public-surface de-personalisation** — personal names, handles, ecosystem hostnames, numeric GIDs, and Vault paths are removed from all shipped framework artefacts. A new CI gate `scripts/personal-id-gate.sh` scans the shipped surface against `dev-tools/personal-id-forbidden.regex` on every PR, blocking any artefact that carries operator-private data. Operator-specific configuration now lives exclusively in the gitignored `${DATARIM_LOCAL}/config/personal.env`, loaded by a new generic `cli/lib/load-local-config.sh` (fail-soft, key-validated, no `eval`/`source`).
- **Security Mandate extended with S3.1** — a new sub-rule in `CLAUDE.md` § Security Mandate and `skills/security-baseline/SKILL.md` § S3.1 codifies the no-personal-data policy for shipped artefacts, references the gate and loader, and defines the inline exemption fence (`<!-- gate:example-only -->`).

### Added

- **Personal config overlay (`~/.claude/local/config/`)** — `install.sh` now creates a `config/` sub-directory inside the local overlay with a self-documenting `README.md` template. The generic loader reads `personal.env` from that path and exports valid keys into the shell environment — without executing any value. Four bats tests cover the injection-safety, bad-key, valid-key, and missing-file contracts.
- **Command-dependency graph** — a machine-readable YAML source of truth (`dev-tools/command-graph.yaml`, 24 commands) records every command's stage, prerequisites, successors, and optional-at complexity levels. A derived Mermaid diagram (`skills/visual-maps/command-dependencies.md`) provides the human-readable view. Four bats tests validate YAML integrity, minimum command count, core-command presence, and diagram content.

### Changed

- **OG-1 resolved: `/dr-help` added to orchestrator rules** — the single outlier in `plugins/dr-orchestrate/rules/default.yaml` is closed; `/dr-help` is now a resolvable pattern (confidence 0.95), aligning the classifier with the soak corpus, three existing surfaces, and the contract test. All 8 rules-loader tests pass.

## [2.31.0] — 2026-06-10

An anti-deferral gate. The framework let an agent label its own unfinished work "out of scope / informational / not a blocker / I'll fix later" and still pass QA, compliance, and archive — discipline-reliance that demonstrably failed (an agent left a stale counter in a runbook paragraph it had just rewritten, called it informational, and moved to archive). The fix is deterministic: prose is not trusted; the touched-file set is the ownership boundary; a deferral is only legitimate when time-dependent or hard-external-blocked AND backed by a verifiable follow-up / `blocked_by` artefact.

### Added

- **`dev-tools/check-deferral-prose.sh`** — scans a QA / compliance report for deferral-tell phrases (a documented, extensible floor) and cross-checks each hit against the touched-file set derived from `git merge-base HEAD origin/main..HEAD`. A deferral phrase co-located with a file the agent touched, lacking a verifiable follow-up / `blocked_by` artefact, exits 1 (BLOCKED). Foreign-scope phrases and artefact-backed deferrals pass. Fail-open-with-warning when the touched set cannot be computed — an infra hiccup never false-blocks. Modelled on `check-banlist-on-prose.sh`; pure shell; exit 0/1/2.
- **Override authorship** in `dev-tools/check-expectations-checklist.sh` — new `override_by` / `override_class` / `override_artifact` fields. `verify_routing` now rejects an agent-authored prose-only override on a `partial`/`missed` wish (the self-certification loophole): an agent override requires an allowed class (`time-dependent` / `external-blocker` / `operator-authorized` / `plan-scope-boundary`) plus an artefact ID that exists in `backlog.md` / `tasks.md`. Operator-authored overrides are accepted unconditionally. Absent `override_by` defaults to `agent` (back-compat, most restrictive). New columns are appended to the emit row — old readers are unaffected.
- **`/dr-archive` Step 0.45** — mandatory "Expectations re-validation + anti-deferral gate", inserted between the network gate (0.3) and reflection (0.5). Placed before reflection on purpose: reflection's follow-up heuristic must not launder a self-inflicted loose end into a backlog item ahead of the gate.
- **Operating rule FB-5a** — canonical text in the consumer mandate (`documentation/mandates/autonomous-agents.md`), machine-readable mirror in `plugins/dr-orchestrate/rules/fb-rules.yaml`: complete reversible authorized work yourself (e.g. an authorized `git push`), do not hand it back; defer only when time-dependent or hard-external-blocked, and only with a traceable artefact.
- **Quoted-phrase exclusion + dual-repo scope** in `dev-tools/check-deferral-prose.sh`. The scanner now ignores deferral-tell phrases inside fenced code blocks or Markdown blockquotes — a report *about* the gate inevitably quotes the tell-phrases next to the gate's own filenames, and the hard compliance gate must not false-block on a quotation; live prose on its own line still scans. New repeatable `--extra-repo <path>` flag adds a nested repository's `merge-base..HEAD` touched-set (additive, fail-open preserved) so the gate is no longer a no-op for dual-repo framework tasks whose reports and code live in different repos; `/dr-compliance` Step 5c and `/dr-archive` Step 0.45 instruct passing it.
- **Regression suites** `tests/check-deferral-prose.bats` (14), `tests/check-expectations-override-authorship.bats` (6), `tests/dr-archive-step04-anti-deferral.bats` (3), `tests/dr-compliance-deferral-gate.bats` (3).

### Changed

- **`/dr-qa` Layer 3b** runs the deferral scan as an advisory (PASS_WITH_NOTES, warns that compliance will hard-block). **`/dr-compliance` Step 5c** runs it as a hard gate → NON-COMPLIANT on a finding. Mirrors the existing evidence-type advisory-at-QA / hard-at-compliance escalation.
- **`skills/expectations-checklist/SKILL.md`** documents the new override fields and the updated CONDITIONAL_PASS / BLOCKED semantics.

## [2.30.0] — 2026-06-06

Prod-readiness gate for deploy-class tasks + anti-self-suppression in self-evolution.

### Added

- **Prod-readiness gate for deploy-class tasks** — a two-stage blocking gate verifies that the production runner is symmetric to the test runner before the pipeline recommends a merge, and again before a task can be archived. `/dr-qa` gains Layer 4g (a read-only test↔prod probe of sudoers, PATH, ports, systemd units, and runtime versions) and `/dr-archive` gains Step 0.4 (archive is blocked until the production merge is done *and* verified). The gate arms only for deploy-class work — tasks touching systemd units, sudoers, CI cutover jobs, or `.env-deploy` templates — detected by a new classifier `dev-tools/check-deploy-class.sh`. Production stays hard-gated: the probe is strictly read-only and predicts impact; any mutation is an explicit operator action.
- **New skill: prod-readiness-probe** — defines what the gate checks and how it reports, with a four-verdict vocabulary (`SKIP` / `PASS` / `FAIL` / `BLOCKED`; `BLOCKED` never auto-resolves to `PASS` on an unreachable host). Hybrid execution: a project may author an optional `datarim/deploy-readiness.yml` contract (validated by `dev-tools/check-deploy-readiness.sh`) for a deterministic probe, or the probe falls back to an agent-driven checklist. The framework core stays stack-agnostic.

### Changed

- **Self-evolution gains an anti-self-suppression rule** — a reflection lesson that recurs (matching a prior reflection or describing a repeat of a known failure) can no longer be declined as "redundant with existing contract" and demoted to a memory note. A new evolution category `promote-recurring-incident-to-gate` turns such a recurring advisory lesson into an enforced gate. The rule fires only on demonstrated recurrence, with cited evidence; genuinely novel lessons may still be declined.

## [2.29.0] — 2026-06-06

Command-surface hygiene plus two workflow reworks. A new `/dr-quick` fast-lane handles trivial fixes without the full pipeline; `/dr-auto` becomes a subagent orchestrator; and reflection moves from archive to the compliance gate with a freshness marker.

### Added

- **`/dr-quick` fast-lane** — a lightweight command for trivial fixes or quick lookups that skips the heavy `init → prd → plan` pipeline. It assigns a `QCK-XXXX` task id (new universal area-prefix, archived under `quick/`), runs a fast context scan on the runtime's cheapest reasoning tier to locate where the change belongs, applies the fix, and writes a short archive entry — no PRD, plan, QA, or compliance. For one-file edits where waiting for full analysis is pure overhead.
- **`dev-tools/reflection-freshness.sh`** — a four-branch freshness helper (absent file / absent marker / stale marker / fresh) backing the reflection-reuse gate, with an 11-case bats regression suite.

### Changed

- **Reflection moves to `/dr-compliance`.** Reflection (lessons-learned + evolution proposals) now runs at a passing `/dr-compliance` verdict and stamps the reflection with a `reflection_basis` marker derived from the compliance report. `/dr-archive` Step 0.5 becomes a freshness gate: it re-runs reflection only when the file is absent, the marker is absent, or the marker is stale versus the current compliance report — otherwise it reuses the existing reflection. The mandatory-reflection guarantee is preserved: a task archived without a prior compliance pass still force-generates. The `reflection_basis` is stamped last, after the compliance report's human-summary append, so the hash matches the final report.
- **`/dr-auto` is now a subagent orchestrator.** Instead of chaining slash commands, `/dr-auto` spawns the matching agent per stage (planner / architect / developer / reviewer / compliance), summarises each result, and routes to the next stage. It drives a task to a passing `/dr-compliance` + reflection and stops there — archival stays an explicit operator step. Re-entering an already-completed stage after a review finding is first-class (the artefact is updated, not recreated).

### Removed

- **Deprecated command aliases.** The `/dr-continue` alias and the `dr-continue-snapshot-replay` skill alias were removed — one canonical name per concept (`/dr-next` and `dr-next-snapshot-replay`). Live inventory is now 24 commands and 54 skills.

## [2.28.0] — 2026-06-01

Tag-driven release environment provisioning, closing a first-publish gap in the autonomous release rails shipped in 2.27.0.

### Added

- **`dev-tools/provision-release-env.sh`** sets up a GitHub deployment environment for a tag-driven publish (`on: push: tags: [v*]`). GitHub creates environments with a default policy that matches protected *branches* and silently excludes *tags*, so the first tag-driven publish of a brand-new package is rejected. The provisioner sets `custom_branch_policies=true` plus a `{name: v*, type: tag}` deployment-branch-policy, and preserves required reviewers on the manual-approval environment. Dry-run by default (only prints planned GitHub API calls unless `--apply`), idempotent (re-running skips a tag policy already present), with the GitHub API edge injected for deterministic testing (13 new regression cases).

### Changed

- **Release docs.** A new how-to walks through provisioning (script quick-path, reviewer-id resolution, manual API equivalent, verification commands). The PyPI first-publish how-to and the release-process playbook now cross-reference it as a one-time prerequisite before the first publish.

## [2.27.0] — 2026-05-31

Autonomous release policy with fail-closed safety rails (Class B). The agent may now publish `patch`/`minor` versions of Arcanada-owned packages to public registries (PyPI / GitHub Releases / npm) end-to-end without an operator prompt, while `major` and any `0.x` breaking change always escalate. Publication is irreversible (PyPI yank ≠ delete; Rekor entries are permanent), so autonomy ships with designed rails, not a one-line mandate edit.

### Added

- `dev-tools/release-classify.sh` — deterministic SemVer bump classifier (Conventional Commits + optional structural API-diff override). `--stamp` mode emits the verdict into an annotated tag; `--test` self-runs fixtures. The API-diff override is fail-closed on tool-absence (`api_diff=unavailable` never downgrades a bump).
- `dev-tools/release-gate.sh` — fail-closed pre-publish gate chain (CI green / `/dr-qa` ALL_PASS / signed pipeline present / branch == main / version not already published / classifier `escalate=false`). Any red aborts before the tag; `major`/`0.x`-breaking exits 10 (escalate); a post-publish install-smoke failure exits non-zero after the tag for rollback. Writes a per-release audit record to `docs/release-audit/`.
- `.github/workflows/release.yml` — a `classify` predecessor job reads the agent-stamped bump level, re-classifies in CI (`max(stamped, ci)`), and the `release` job selects a conditional `environment` (`release-auto` for patch/minor, `release-manual` requiring an operator reviewer for major).
- `docs/how-to/{pypi-first-publish,release-rollback,version-0x-policy}.md` — operator playbooks.

### Changed

- Autonomous-agents mandate gains a narrowly-scoped carve-out for autonomous patch/minor public-package release; every other hard-gated action is unchanged. Machine-readable mirror in `plugins/dr-orchestrate/rules/fb-rules.yaml` (`hard_gate_carve_outs`).

## [2.26.0] — 2026-05-29

A KB-integrity protection bundle. One architectural defect produced three symptoms — a lost `backlog.md` (overwritten via an `awk … > file` redirect with no pre-write backup), a nested `datarim/datarim/`, and append-only ledgers landing in a legacy `datarim/docs/`. Root cause: no shared path resolver, and `--root` meant the `datarim/` dir in the doctor but the repo-root everywhere else.

### Added

- **Canonical KB-root resolver** `scripts/lib/resolve-datarim-root.sh`. `resolve_datarim_root [start]` echoes the **repo-root** (the parent of the KB-marked `datarim/`) using the documented git-toplevel-anchor + walk-up rule; `assert_not_nested_datarim <root>` rejects a root already inside a `datarim/` (the `datarim/datarim/` vector). Replaces three divergent walk-up re-implementations with one source of truth. `--root` now means repo-root everywhere.
- **Pre-overwrite backup primitive** `scripts/lib/kb-backup.sh`. `backup_critical_kb_file <repo-root> <relpath>` copies a critical KB file to `datarim/.backups/<basename>.<ISO-ts>.bak` before it is overwritten, with FIFO rotation (`DR_KB_BACKUP_KEEP`, default 10), `chmod 700` dir / `chmod 600` files, and strict fail-soft semantics (a failed backup never blocks the write). Reuses the portable `acquire_plugin_lock`. Critical allowlist: `backlog.md backlog-archive.md tasks.md activeContext.md progress.md`.
- **Hook-level enforcement.** `coworker-hook-guard.sh` PreToolUse `Write` and `Bash` branches take a fail-soft pre-overwrite backup when the target is a critical KB file — catching both the Write tool and `awk`/`tee`/`>`/`>>` redirect overwrites, on every machine, since neither calls a framework shell library. `datarim/.backups/` is gitignored by the wholesale `datarim/` ignore and added to the `file-sync-config` Syncthing/iCloud/rclone ignore set (host-local recovery ground-truth, never replicated).
- **Recovery how-to** `docs/how-to/recover-datarim-files.md` — per-file source-of-truth priority table (backup → sync-conflict → task artefacts → archive frontmatter → transcripts), restore recipes, and the `datarim-doctor --fix` repair recipe.
- **`datarim-doctor.sh` migration pass** (`--scope=history`, also runs under `--scope=all`/`--fix`): moves the ledgers to `datarim/history/`, relocates any architecture ADR to `documentation/architecture/` (task-id prefix stripped → `ADR-0002-`), rewrites the consumer `.gitignore` to the glob+negation form, and removes the empty `docs/` — idempotently and losslessly. Auto-heals on `/dr-init` Step 2.4. Reuses the existing lock + pre-write backup tarball; leaves the `EMITTED_COUNT` invariant untouched (orthogonal to the ledger move).
- **Regression suites** `tests/resolve-datarim-root.bats` (11), `tests/kb-backup.bats` (13), `tests/datarim-datarim-nesting-regression.bats` (4), `tests/doctor-root-contract.bats` (8), `tests/coworker-guard-kb-backup.bats` (9), plus `tests/datarim-doctor-history-migration.bats` (13) and `tests/datarim-history-gitignore-negation.bats` (5).

### Changed

- **`--root` is repo-root canonical.** `datarim-doctor.sh` now treats `--root` as the repo-root (deriving `<repo-root>/datarim` internally), matching how `/dr-init` Step 2.4 and `/dr-doctor` already invoke it — this is why the `docs→history` migration silently never fired through the pipeline before. A one-release transition shim normalises a legacy `datarim/`-dir argument and warns. The snapshot writer and the `dev-tools/check-*.sh` validators source the resolver so a nested cwd still finds the repo-root.
- **Consumer knowledge bases retire the misleadingly-named `datarim/docs/` ledger directory.** Append-only ledgers (`evolution-log.md`, `activity-log.md`, `patterns.md`) now live in `datarim/history/`, committed to git via a `.gitignore` negation block (`/datarim/*` + `!/datarim/history/` + `!/datarim/history/**`). The generic «docs» name — copied from the framework source-tree — had caused a near-miss deletion when a cleanup agent mistook the live ledgers for duplicate documentation.
- **All framework write-instructions** (`/dr-archive`, `/dr-optimize`, `/dr-dream`, reflecting/evolution/dream skills, optimizer/librarian agents, `/dr-do` patterns reference) now target `datarim/history/`.
- **Storage-contract docs** (`skills/datarim-system/path-and-storage.md`, `CLAUDE.md` state tree, `docs/getting-started.md`) describe `history/`, the gitignore-negation gotcha, and point at the resolver as the canonical implementation of the path rule.

### Note

- The framework source-tree `code/datarim/docs/` (real user documentation + product evolution ledger) is unchanged — only consumer knowledge bases migrate. Bash-redirect backup detection is best-effort (literal `>`/`>>`/`tee` targets); obfuscated/computed redirects are documented as out of scope in the recovery how-to.

## [2.24.0] — 2026-05-28

### Changed

- **coworker-hook-guard Read gate: line-count → estimated-token model.** The `Read`/`view` gate no longer counts lines (`wc -l`, blind to per-line density — a 1-line minified/base64 file read as "1 line"). It now estimates tokens as `wc -c / divisor` (divisor by extension, conservative-downward: `.b64`/`.base64` → 1, `.min.js`/`.min.css` → 2, otherwise → 3) — pure bash, ~1 ms, zero model, zero network. Two env-tunable thresholds: delegation `COWORKER_GUARD_DELEGATE_TOKENS` (default 10000) and a hard ceiling `COWORKER_GUARD_CEILING_TOKENS` (default 100000) that routes to grep-only and never to any LLM. Opt-in fail-soft tokenizer behind `COWORKER_GUARD_USE_TOKENIZER=1` (`COWORKER_GUARD_TOKENIZER_BIN`); absent/erroring binary silently falls back to the heuristic.
- **Legacy line-count vars deprecated, never reinterpreted.** `COWORKER_GUARD_READ_THRESHOLD` / `KIMI_GUARD_READ_THRESHOLD` are ignored under the token model; if set, the guard emits a single SessionStart deprecation note naming the new vars (it does NOT silently reinterpret a stale `=700` as 700 bytes).
- **Two deny messages bound to the crossed threshold, guarded by a defensive invariant.** The delegation deny leads with the Bash-native edit hatch (`python3`/`sed` are not gated, so the `Edit` Read-precondition is moot), then `coworker ask`, then a relaunch-only env-override note (an in-session `! export` never reaches the hook). The ceiling deny steers to `sed`/`grep -n`/`head` windows and MUST NOT suggest `coworker ask`. A § Defensive Invariants precondition guard exits 2 if a future refactor decouples the wording from the crossed tier.
- **Delegation mandate harmonized to the token unit across all surfaces.** The written ">600 lines summed" trigger became ">15000 estimated tokens summed" across the canonical fragment, the Cursor `.mdc`, the regenerated Codex `AGENTS.override.md`, the Cursor rule, and `~/.claude/CLAUDE.md`. The git-diff/log trigger stays line-based (diffs are uniform prose).
- **RTK upgraded 0.40.0 → 0.42.0** and the signal/bulk passthrough re-validated (passthrough/plugin + live pytest green; `git push` passes through with its completion marker intact while bulk reads are still RTK-reduced). Upstream `rtk-ai/rtk#2121` ("built-in signal/bulk classifier") remains OPEN, so the local `rtk-signal-guard.sh` passthrough store is retained, not simplified.

### Fixed

- **`git show <ref>:<path>` blob-read false-positive in the Bash branch.** The guard conflated `git show <commit>` (diff/log dump, delegation-worthy) with `git show <ref>:<path>` (blob read — small, signal not bulk). A colon-shape probe now passes the blob form through, and the reset-case was extended to cover `| sed`, `| awk`, `--no-pager`, and a stdout redirect (`X > file` yields no stdout to pipe into `coworker ask`).

### Added

- **Guard regression suites.** `tests/test-coworker-hook-guard-token-threshold.bats` (delegate/ceiling bands, divisor classes, legacy-var ignore, opt-in tokenizer fail-soft, deny-wording invariant) and `tests/test-coworker-hook-guard-git-show.bats` (blob passthrough vs diff delegation, extended reset-case). The Codex parity suite's Read fixture was re-based on byte size rather than line count.

- **`documentation/infrastructure/Coworker.md` § Hook enforcement — escape-hatch.** Documents the catch-22 Read→Edit unblock (Bash `python3`/`sed`/`grep -n` are not gated), that the deny "approve" is dead in accept-edits / autonomous mode, the in-session `! export` footgun, and the ceiling → grep-only path.

## [2.23.0] — 2026-05-28

### Added

- **Canonical Runtime Support Matrix in `docs/use-cases.md`.** New § Runtime support documents the three supported runtimes (Claude Code primary, Codex CLI parity via `coworker rtk` shim, Cursor parity via its native `beforeShellExecution` hook) with a 5-column matrix (Runtime / Install command / Hook integration / Bulk-read economy via RTK / Status). Cursor RTK parity is delivered by `coworker rtk enable` (Coworker v0.6.2+), which registers `rtk hook cursor` in `~/.cursor/hooks.json`; the prior «no native hook / inherited» framing was inaccurate. All shipped surfaces (`README.md`, `docs/getting-started.md`, `CLAUDE.md`, `templates/coworker-delegation-fragment.md`) link back to this matrix as the single source of truth — zero claim drift across surfaces.
- **RTK realities documented in `templates/coworker-delegation-fragment.md`.** New paragraph in § RTK plugin (opt-in) cites the measured impact of out-of-box `rtk` on macOS (`git status` +108%, `git log --oneline -50` +6924%, lost `git push` completion marker on some repos — upstream issue rtk-ai/rtk#2121) and contrasts it with the `coworker rtk` plugin, which guards signal-bearing git/gh commands via a 13-pattern passthrough allowlist while still applying bulk-read economy to log dumps, file content reads, and `git diff`. Multi-runtime parity preserved via the bundled Codex CLI shim.

### Changed

- **VERSION 2.22.0 → 2.23.0** (minor — documentation refresh + multi-agent narrative correction; no breaking runtime change).
- **CLAUDE.md skill count** corrected from «45 skills, 10 with supporting fragment directories» to live inventory «55 skills, 11 with supporting fragment directories» (drift accumulated across TUNE-0304 universal-layout migration + downstream skill additions through v2.22.0).
- **CLAUDE.md command count** corrected from «23 commands core + 1 plugin» to «24 commands core + 1 plugin».
- **README.md badge + Features section counts** synced to live inventory (18 agents, 55 skills, 24 commands).
- **`docs/getting-started.md` § Choose your runtime** rewritten to enumerate Claude Code / Codex CLI / Cursor with the honest Cursor disclaimer and a link to the canonical matrix in `use-cases.md`.

## [2.22.0] — 2026-05-26

### Added

- **TUNE-0308 epic completion.** Outsider-friendly English instruction surface refresh across 164 shipped files; `dev-tools/check-jargon-gloss.sh` validator + jargon manifest enforcing first-use glosses for in-house terms.
- **TUNE-0319 init-task Q&A round-trip extension.** `dev-tools/append-init-task-qa.sh` extended with `--decided-by agent` rationale-length gate (≥50 non-whitespace chars), `--conflict-with <wish_id>` flag, and `/dr-qa` Layer 3b retroactive backfill detector. Skill `skills/init-task-persistence/SKILL.md` § Q&A round-trip contract; bats coverage in `tests/append-init-task-qa.bats`.
- **`/dr-archive` body-english fail-hard flip.** `dev-tools/check-body-english.sh` flips from advisory warning to fail-hard block at archive time on any shipped artefact carrying non-allowlisted non-ASCII without the `<!-- allow-non-ascii: <reason> -->` marker.
- **English-Only mandate in 4 CLAUDE.md.** `~/.claude/CLAUDE.md`, `~/arcanada/CLAUDE.md`, `Projects/Datarim/CLAUDE.md`, `code/datarim/CLAUDE.md` carry the same English-Only Shipped Instruction Surface rule with shared allowlist and validator-marker contract.
- **V-AC axis-split Pattern 2.** `skills/v-ac-axis-split/SKILL.md` gains Pattern 2 — gate-activation axis dry-run during `/dr-plan` Component Breakdown.

### Changed

- **VERSION 2.21.0 → 2.22.0** (TUNE-0308 epic completion + TUNE-0319 follow-up).
- Surfaces synced: `code/datarim/VERSION`, `code/datarim/CLAUDE.md` (Version line), `code/datarim/README.md` (badge ×2), `Projects/Datarim/CLAUDE.md` (Текущая версия), `Projects/Datarim/README.md` (Версия), `Projects/Websites/datarim.club/config.php` (version key), `Projects/Websites/datarim.club/pages/changelog.php` (new release entry).

## [2.21.0] — 2026-05-25

### Added

- **Universal directory-per-skill layout (TUNE-0304).** Все 55 skills переведены из flat `skills/<name>.md` в canonical agentskills.io v1.0.0 формат `skills/<name>/SKILL.md`. Layout совместим с Claude Code, Codex CLI и Cursor IDE. 11 split-architecture skills (datarim-system, evolution, ai-quality, testing, utilities, visual-maps, и др.) теперь имеют router `SKILL.md` рядом с fragment'ами в одной директории. 55 устаревших flat-источников удалены (Phase 5 contract removal).
- **Runtime-agnostic frontmatter (TUNE-0304).** Поле `runtime:` (52 файла) удалено целиком — datarim-private convention, никем не читалось. Hardcode `model: sonnet|opus|haiku` (15 skills + 18 agents) заменён на `model: inherit` как default + опциональный `metadata.model_tier: reasoning|balanced|fast|cheap` для аудита. Маппинг tier→model вынесен в новый `config/model-tiers.yaml` (current Claude 4.x + OpenAI/Google equivalents).
- **`install.sh --with-cursor` (TUNE-0304).** Новый target: mirror каждого `skills/<name>/SKILL.md` → `$CURSOR_DIR/skills/<name>.md` (flat copy, не symlink — Windows + FAT + R7 deferred-validation posture). `CURSOR_DIR` env var (default `$HOME/.cursor`). Композиция с `--with-claude` / `--with-codex`. Bats T47-T50 + T48b (.system exclusion). **[deferred-validation]** — live smoke в Cursor IDE откладывается до получения operator licence; R7 accepted-risk в PRD.
- **Sibling-reference contract (TUNE-0304).** Внутри SKILL.md ссылки на co-located bundle-файлы переписаны на sibling-relative форму (`pipeline-routing.md` вместо `skills/visual-maps/pipeline-routing.md`). 38 refs across 6 split-arch skills (ai-quality, datarim-system, evolution, testing, utilities, visual-maps). Per agentskills.io v1.0.0 SKILL.md + ассеты считаются единым bundle'ом, переносимым как блок. Новый `dev-tools/check-skill-sibling-refs.sh` enforce'ит invariant (6/6 bats green).
- **Dev-tools для миграции (TUNE-0304).** Пять новых script + 48 bats: `check-skill-layout.sh` (V-AC-1 strict + `--allow-flat-coexistence` hybrid mode), `check-skill-frontmatter.sh` (rewritten under new schema), `migrate-skill.sh` (per-skill flat→nested migrator, idempotent), `rewrite-skill-refs.sh` (repo-wide `skills/<name>.md` → `skills/<name>/SKILL.md` rewriter for `.md/.sh/.yaml/.yml`), `check-skill-sibling-refs.sh` (sibling-ref invariant).
- **Migration runbook (TUNE-0304).** `docs/how-to/migrate-to-skill-md-layout.md` — operator runbook (Steps 1–5 + rollback + frontmatter normalisation contract).
- **Evolution log entry (TUNE-0304).** `docs/evolution/2026-Q2-TUNE-0304-universal-skills.md` — rationale, migration matrix, deferred items.

### Changed

- **VERSION 2.20.0 → 2.21.0** (minor — schema migration, no breaking runtime change для consumer'ов на symlink-default operating model; copy-mode users — прогнать `git pull && ./install.sh --copy --force --yes` для resync).
- **`dev-tools/hooks/dr-output-stop.py`** — 4 residual reference на legacy `skills/cta-format.md` / `skills/human-summary.md` обновлены до canonical `skills/cta-format/SKILL.md` / `skills/human-summary/SKILL.md`.
- **`config/model-tiers.yaml` location.** Per Constraint C3 — Codex `.system/` namespace зарезервирован под bundled skills (imagegen, openai-docs, plugin-creator, skill-creator, skill-installer); Datarim runtime configuration живёт в `config/model-tiers.yaml` at repo root. PRD V-AC-5 draft path переопределён task-description C3 (init-task Q&A round 1).

### Deferred

- **Codex 55→1 dir-symlink collapse** — direct conflict между PRD V-AC-7 (`~/.agents/skills/<name>`) и plan §6.5 (`~/.codex/skills/datarim`) + Constraint C5 «existing paths must remain resolvable during transition». Operator-decision L5 architectural pick откладывается; existing TUNE-0297 `fanout_codex_ux` wrappers продолжают работать (Codex live smoke 2026-05-25 confirms discovery через `~/.codex/skills/`).

### Operator action required

- **Symlink-default users**: после `git pull` рестарт Claude Code session обязателен для подхвата нового layout.
- **Copy-mode users**: `git pull && ./install.sh --copy --force --yes`.
- **Cursor users**: добавить `--with-cursor` к invocation для нового target (`$HOME/.cursor/skills/`).

### Added

- **Codex CLI UX parity — native discoverability of Datarim artefacts (TUNE-0297).** `./install.sh --with-codex` now generates SKILL.md adapter wrappers (`~/.codex/skills/<name>/SKILL.md`) for every top-level source skill, restores Codex's bundled `.system/` skills from the TUNE-0296 backup, and emits a Codex-only catalogue manifest at `~/.codex/AGENTS.override.md` with three sections (Available Datarim Commands / Skills / Agents). `~/.codex/skills/` flips from symlink to a real directory under the new UX default; `detect_existing_topology` is now scope-aware so repeat runs do not trip the mixed-topology guard. The shared AGENTS.md symlink chain (~/.codex/AGENTS.md → source AGENTS.md → CLAUDE.md) is byte-stable by design — Codex-specific catalogue text lives only in the override file. Opt-out via the new `--no-codex-ux` flag (CI / bisect / baseline-topology debugging). Five new bats tests (T42 wrapper generation, T43 negative regression under `--with-claude`, T44 manifest + AGENTS.md byte-stability, T45 `.system/` restore + idempotency, T46 opt-out).
- **Multi-runtime parity for Codex CLI (TUNE-0296).** `./install.sh --with-codex` now symlinks `~/.codex/AGENTS.md → <repo>/AGENTS.md` (which is itself a symlink to `CLAUDE.md`), in addition to the existing seven directory symlinks (`agents/`, `skills/`, `commands/`, `templates/`, `scripts/`, `tests/`, `dev-tools/`). Codex CLI now reads the canonical Datarim ecosystem-router from the same source repo as Claude Code. The patch is gated on `runtime_name=codex` — `--with-claude` topology is unchanged (T41 regression guard in `tests/install-tune-0114.bats`).
- `tests/install-tune-0114.bats` — three new tests (T40 / T41 / T40b) covering AGENTS.md install / non-install and dry-run wording for both runtimes.
- `docs/how-to/multi-runtime.md` — operator-facing how-to: install both runtimes, verify topology, register the Coworker `codex` profile, and the troubleshooting recipe for the pre-existing `~/.codex/skills/.system/` bundled-skills conflict.

### Documentation

- `README.md` § Activate in Your Project — new subsection **«Optional: External CLI (`datarim` binary)»** (TUNE-0271 v2 doc-fanout). Explains that `./install.sh --with-claude` does **NOT** symlink the `datarim` binary used by non-interactive agents; the standalone CLI installer at `code/datarim/cli/install.sh` is opt-in (AAL 3) and must be run separately. Resolves the `zsh: command not found: datarim` discoverability gap reported post-archive.
- `docs/getting-started.md` § Installation — new subsection **«Optional: external `datarim` CLI»** mirroring the README pointer at the tutorial-mode reader funnel. Cross-link to `docs/cli.md` for the full reference (subcommands, exit codes, AAL 3 mitigations, kill-switch sentinel, audit retention).
- `docs/cli.md` — new section **«Backend listener requirement»** explaining that `datarim run` is an HTTP client only and the `127.0.0.1:8090` backend is `adnanh/webhook` (open-source Go binary, MIT, **not bundled**) reachable via the `dr-orchestrate` plugin. Documents the loopback-only (Tier 1) bind, the three-step stand-up recipe (`/dr-plugin enable dr-orchestrate` + install `webhook` + start with `-hooks ... -port 8090`), and clarifies that the listener is optional for Claude-Code-session users. Resolves the operator-discoverability gap surfaced post-archive («что это за сервер и почему я о нём не знаю»).
- `README.md` § Optional: External CLI — added heads-up block pointing at `docs/cli.md § Backend listener requirement` to close the same gap at the entry-level reader funnel.

## [2.19.0] — 2026-05-24

**Autonomous execution mode (`/dr-auto`).** New meta-command activates `documentation/mandates/autonomous-agents.md` (FB-1..8) + the L1 Inline Resolution Rule + autonomous-ops scope as default-on for the duration of one task cycle. Question Suppression Ladder (5 levels — codebase grep → runtime probe → MEMORY.md feedback → coworker delegation → operator) suppresses pipeline Q&A. L1 Class A gaps discovered mid-cycle close inline; L2+ / Class B gaps spawn backlog items; hard-gated actions (verbatim `autonomous-agents.md:30-32`) escalate to operator. Activated via env var `DATARIM_AUTO_MODE=1` + per-task file marker `datarim/.auto-mode-active`. Two modes: Continue (`/dr-auto {TASK-ID}` resume from snapshot) and Bootstrap (`/dr-auto "<free-text>"` full pipeline from `/dr-init`). Class B operating-model change — does not introduce new rules, only changes activation default of existing mandates.

### Added

- `commands/dr-auto.md` — canonical command, 8-step instructions, Continue + Bootstrap modes, hard-gated escalation contract.
- `skills/autonomous-mode/SKILL.md` — canonical contract: Question Suppression Ladder + L1 Inline Resolution Rule decision tree + Hard-gated Action Boundary (verbatim cite + cross-project boundary) + Failure modes.
- `dev-tools/classify-inline-gap.sh` — L1 Inline classifier (--files / --loc / --contract / --hard-gated → L1-A | L2+/B | HARD). Used by `/dr-do` under auto-mode.
- `tests/dr-auto-l1-inline-classifier.bats` — 11 test cases covering boundary at 50 LoC, multi-file, contract change, hard-gated override, usage errors.

### Changed

- All 7 pipeline commands (`dr-init`, `dr-prd`, `dr-plan`, `dr-do`, `dr-qa`, `dr-compliance`, `dr-archive`) — added `## /dr-auto Mode` section after `## Instructions`. Section describes stage-specific Q&A suppression hooks and references `skills/autonomous-mode/SKILL.md` § Question Suppression Ladder as canonical source.
- `commands/dr-help.md` — added `/dr-auto` row in the Pipeline Commands table.
- `docs/commands.md` — added `/dr-auto` row.
- `docs/getting-started.md` — new `## Autonomous Mode (/dr-auto)` section with Continue/Bootstrap modes, Ladder summary, L1 Inline Rule overview, when-to-use guidance, failure modes.
- `CLAUDE.md` — added `/dr-auto` row to commands table; updated command count `22 → 23 commands core`.
- `README.md` — added `/dr-auto` row to Commands section; updated count references `22 → 23 commands`.
- `VERSION` — `2.18.0 → 2.19.0`.

## [2.14.0] — 2026-05-22

**Business-facing archive and compliance report contract (TUNE-0255).** The archive and `/dr-compliance` report templates now answer the operator's question «что я просил и что вы сделали» in plain Russian, in four mandatory top-level sections in strict order — «Начальная задача», «Как решили», «Артефакты задачи», «Следующие шаги» — followed by an audit addendum under a `---` horizontal rule that carries the technical surface (`verification_outcome` mirror, AC table, lessons learned, operator handoff, related). The «Как решили» section is a single-level bullet list that maps every operator-brief bullet (in original order) to a quoted item + Russian status word («выполнено» / «частично» / «не выполнено» / «неприменимо» — never the schema enum) + one or two plain-language sentences; expectations from `tasks/{ID}-expectations.md` fold into the same list with marker «(уточнение брифа)». The previous top-level `## Выполнение ожиданий оператора` heading is retired — its content is folded into «Как решили». The same contract applies to `/dr-compliance` via a new canonical template.

### Added

- `templates/compliance-report-template.md` — new canonical template mirroring the archive shape (four operator-facing top sections + audit addendum carrying the 7-step verdict table, remaining risks, related links). Frontmatter: `task_id`, `date`, `verdict` (COMPLIANT / COMPLIANT_WITH_NOTES / NON-COMPLIANT), optional `scope`.
- `dev-tools/check-banlist-on-prose.sh` — fence-aware awk one-shot validator. Bash wrapper does argparse + path-traversal regex (`^[A-Za-z0-9._/-]+\.md$`). Awk one-shot skips YAML frontmatter (first `---` block) and honours `<!-- gate:literal -->` and `<!-- gate:example-only -->` fence markers; tokenises ASCII tokens of length ≥3, lowercases, looks up `skills/human-summary/whitelist.txt` then `skills/human-summary/banlist.txt`. Exit 0 clean / 1 offences (`file:line:token`) / 2 usage. Shellcheck `-S warning` clean.
- `tests/tune-0255-archive-business-structure.bats` — 10 cases. Guard the four-section canonical order in `archive-template.md`, the `dr-archive.md` Step 2 mapping instructions, the expectations-fold marker, audit-addendum invariants, the four Russian status words, the schema-enum prohibition, the no-tables / single-level-bullets rules, the banlist-clean check on the template, and the validator's exit-0 contract.
- `tests/tune-0255-compliance-template-shape.bats` — 4 cases. Guard the compliance template shape, the skill/command cross-link, the validator pass on the template, and the frontmatter fields.

### Changed

- `templates/archive-template.md` — rewritten under the four-section + audit-addendum layout. Frontmatter and `verification_outcome` contract unchanged. The top layer carries «Начальная задача», «Как решили», «Артефакты задачи», «Следующие шаги»; the audit addendum below the `---` rule carries `### verification_outcome`, `### Acceptance Criteria`, `### Lessons Learned`, `### Operator Handoff`, `### Related`. The `Operator Handoff` section moved from a top-level placement to the audit addendum (the existing structural guard on the `Operator Handoff` heading remains green).
- `commands/dr-archive.md` Step 2 — rewritten under the new contract. The placeholder strings «Task summary / Implementation details / Reflection insights» and the explicit `## Выполнение ожиданий оператора` block were removed. The new block enumerates the four top sections in strict order, the audit addendum with its five sub-sections, the expectations fold-into-«Как решили» semantics with the «(уточнение брифа)» marker, and the no-tables / no-anglicisms rules. Status-word translations preserved. Step 0.05 and Step 8 (Human Summary) updated to reference the new source sections.
- `commands/dr-compliance.md` Step 7 — rewritten to reference `templates/compliance-report-template.md`. The same four-section + audit-addendum contract applies; the 7-step verdict table inside the addendum is wrapped in `<!-- gate:literal -->` so English column headings bypass the banlist.
- `skills/compliance/SKILL.md § Output` — rewritten to reference the new template and the four-section contract.
- `skills/human-summary/SKILL.md` — new `## See also` section linking the shared banlist to the archive and compliance templates and to `dev-tools/check-banlist-on-prose.sh`.
- `VERSION` 2.13.0 → 2.14.0; touchpoints across `CLAUDE.md`, `README.md`, `Projects/Datarim/{CLAUDE,README}.md`, `Projects/Websites/datarim.club/config.php` aligned (zero residual `2.13.0` outside the historical changelog entry).

### Removed

- `tests/tune-0210-archive-expectations-section.bats` — retired. T6-T10 ported into `tests/tune-0255-archive-business-structure.bats` (status-word / no-tables / banlist / forbid-enum guards). T1-T5 retired because the `## Выполнение ожиданий оператора` heading was removed from the template.

### Migration notes

- Existing `archive-*.md` documents under `documentation/archive/` are grandfathered — no rewrite is required, the new contract applies to archives written after 2.14.0.
- Consumers reading the archive shape should switch their parsers to expect the new top four sections; the legacy `## Outcome / ## Verification Summary / ## Final Acceptance Criteria` placement is no longer present in the canonical template.
- Operators who relied on the explicit `## Выполнение ожиданий оператора` heading will now find the same content folded into the «Как решили» list with the marker «(уточнение брифа)» appended to each expectation-derived item.

## [2.13.0] — 2026-05-21

**Per-task stage snapshots (TUNE-0254).** Every `/dr-*` command now persists its final operator-visible response (Summary + Gate Results + CTA) to `datarim/snapshots/{TASK-ID}.snapshot.md` with overwrite semantics, mkdir-based atomic lock, `chmod 600`, and an 8 KB hard cap with explicit truncation marker. Producer side wired through a single touchpoint — `skills/cta-format/SKILL.md § Snapshot Emission` — instead of per-command patches. Consumer side: `/dr-continue` Step 2.5 (`SNAPSHOT-FIRST READ`) and `/dr-orchestrate` Step 2 (`Snapshot-First Resume`) read the snapshot before any other context and emit a replay-prompt with the recommended CTA + bilingual (RU + EN) autonomy reminder + literal `done before:` block. At `/dr-archive` Step 0.95 the snapshot is moved (not deleted) to `documentation/archive/<subdir>/snapshots/{TASK-ID}-final-stage.md` via the existing `prefix_to_area()` resolver, so the final stage card remains grep-able in the archive.

### Added

- `scripts/lib/snapshot-writer.sh` — producer library with `write_stage_snapshot`. Concurrent-safe via `acquire_plugin_lock` mkdir-based atomic lock (env-var `DR_SNAPSHOT_LOCK_TIMEOUT`, default 60). Byte-accurate truncation via `wc -c` + `head -c`; UTF-8 codepoint safety preserved by piping the truncated chunk through `iconv -c` to drop any trailing partial multibyte sequence (final size may shrink by ≤3 bytes — well within the 8192 cap). TASK-ID regex anchor `^[A-Z][A-Z0-9-]+-[0-9]{4,5}$` for path-traversal defence.
- `dev-tools/check-stage-snapshot-on-exit.sh` — validator with three modes (`--task`, `--validate-frontmatter`, `--self-test`); exit codes 0/1/2/3. Rejects symlinks at the snapshot path (exit 2 «malformed») symmetric with writer-side T-7 pre-unlink — closes shared-workspace attack surface where a co-agent could substitute a symlink to inline arbitrary file contents into the replay-prompt.
- `skills/stage-snapshot-writer/SKILL.md` — producer contract (invoked from `cta-format.md § Snapshot Emission`).
- `skills/dr-continue-snapshot-replay/SKILL.md` — consumer contract with three worked examples covering CTA selection (L3+ few checks → `/dr-verify`; L3+ saturated → `/dr-do`; L1/L2 do_done → `/dr-archive`).
- `docs/how-to/stage-snapshots.md` — operator how-to (first Diátaxis how-to category file in `docs/`).
- 12 new bats suites (51 cases): `stage-snapshot-{writer-overwrite, frontmatter-schema, size-cap, flock-race, shellcheck, cta-format-integration, cleanup-on-archive, utf8-truncation, symlink-rejection}`, `dr-{continue,orchestrate}-snapshot-replay`, `dr-archive-snapshot-move`. Combined with the 39 regression cases in `tests/cta-format.bats`, the snapshot-touched sweep totals 90/90 green.

### Changed

- `skills/cta-format/SKILL.md` — new terminal sub-section `§ Snapshot Emission` (single producer touchpoint for all 15 `/dr-*` commands). All 39 existing `cta-format.bats` cases unchanged (additive contract).
- `commands/dr-continue.md` — new Step 2.5 `SNAPSHOT-FIRST READ` that stops the downstream Read pipeline when a valid snapshot is present and silently falls through to legacy behaviour otherwise (no warning lines).
- `plugins/dr-orchestrate/commands/dr-orchestrate.md` — `Snapshot-First Resume` block ahead of `semantic_parser.sh`; `recommended_next` passed to `subagent_resolver.sh` as `--hint` (hint, not constraint). Цикл renumbered 1 → 6.
- `commands/dr-archive.md` — new Step 0.95 `STAGE-SNAPSHOT MOVE-TO-ARCHIVE` (move-not-delete via `prefix_to_area`).
- `skills/init-task-persistence/SKILL.md` — `stage-snapshot` added to the per-task artefact roster (sibling to init-task + expectations-checklist).
- `.gitignore` — `datarim/snapshots/` added (mirrors `datarim/qa/` pattern).
- `docs/getting-started.md` — new `§ Context Management (v2.13.0+)` block; `docs/skills.md` skill count 45 → 47; `docs/commands.md` `/dr-continue` row mentions Step 2.5.
- `VERSION` 2.12.0 → 2.13.0; touchpoints across `CLAUDE.md`, `README.md`, `Projects/Datarim/{CLAUDE,README}.md`, `Projects/Websites/datarim.club/config.php` aligned (zero residual `2.12.0` outside the historical `docs/evolution-log.md` entry).

### Class B (public surface — `datarim.club`)

- `pages/changelog.php` v2.13.0 entry (feat × 4 + notes).
- `data/skills/stage-snapshot-writer.php`, `data/skills/dr-continue-snapshot-replay.php` (EN + RU short + body).
- `content/en.php`, `content/ru.php` — skill counts and UI strings updated.
- Deploy via `cd Projects/Websites && ./deploy.sh datarim.club` remains an operator step (hard-gated cross-org rsync).

## [2.11.1] — 2026-05-16

**Advisory V-AC pre-flight against ecosystem mandates.** `/dr-prd` Step 5 (pre-save validation gates) gains a third bullet that runs `dev-tools/check-v-ac-mandate-preflight.sh` against the draft PRD. The script extracts V-AC / Verification / Success Criteria lines and greps each against `dev-tools/public-surface-forbidden.regex` (the same contract surface consumed by `public-surface-lint.sh`). On match — advisory `WARNING:` line on stdout; the gate is non-blocking (always exits 0). Surfaces a V-AC ↔ Public Surface Hygiene conflict at PRD-time, not later in the pipeline.

### Added

- `dev-tools/check-v-ac-mandate-preflight.sh` — pure-bash advisory linter. Args: `--prd FILE` (required), `--regex FILE` (default sibling contract surface), `--report`, `--help`. Exit codes: 0 = scan complete, 2 = usage error. No mutation, no network, no `eval`.
- `commands/dr-prd.md` Step 5 — third pre-save bullet "V-AC ecosystem-mandate alignment" wired into the existing two-bullet gate sequence.

### Tests

- `tests/tune-0228-prd-v-ac-mandate-preflight.bats` — eight scenarios: forbidden literal in V-AC (exit 0 + WARNING), forbidden literal in `reflection-*` form, safe V-AC content (silent), PRD without Success Criteria section (silent no-op), missing PRD path (exit 2), missing regex path (exit 2), forbidden literal outside V-AC scope (silent), consumer-extended regex via `--regex` override (WARNING — proves contract surface reuse).

## [2.11.0] — 2026-05-16

**Agent autonomy restored on `/dr-init` and `/dr-archive`.** Symmetric revert of the operator-only contract introduced in 2.10.0: the `disable-model-invocation: true` frontmatter flag, the 🔒 lock-emoji in H1 and table rows, the Operator-only marker blockquote, the planner/compliance STOP-rule, the `cta-format.md § Operator-only commands` section, and the Mermaid `classDef operatorOnly` styling have all been removed on both commands per the FB-rules (Autonomous Agent Operating Rules) mandate. Structural guards — the `pre-archive-check.sh` schema gate + staged-diff audit at Step 0.1, the `datarim-doctor.sh --quiet` probe at `/dr-init` Step 2.4, the blob-swap recipe, the prefix → archive-subdir routing, and the Operator Handoff section template — remain enforced in code and are verified by a new regression bats.

### Changed

- `commands/dr-archive.md`, `commands/dr-init.md`: frontmatter flag removed; H1 dropped the 🔒 prefix and the «(Operator-only)» suffix; the Operator-only marker blockquote was rewritten as a neutral «Contract» blockquote that names the in-code guards.
- `commands/dr-help.md`: the 🔒 badge and «operator-only (agents cannot invoke)» annotation removed from both pipeline-table rows.
- `commands/dr-compliance.md`: Next-Steps CTA now points to plain `/dr-archive {TASK-ID}` without the operator-only sentence.
- `agents/planner.md`, `agents/compliance.md`: the «Operator-only gates (STOP rule)» paragraphs were removed without replacement; agents now treat both lifecycle commands as regular slash commands invokable via the Skill tool.
- `skills/cta-format/SKILL.md`: the «Operator-only commands» section and the 🔒 badge convention were removed.
- `skills/visual-maps/pipeline-routing.md`: the Mermaid `classDef operatorOnly`, the `class Init,Archive… operatorOnly` binding, and the node-colour legend paragraph were removed.
- `docs/pipeline.md`: Stage 1 and Stage 8 headers dropped the 🔒 prefix and the «(operator-only)» suffix; the Operator-only blockquotes were removed.

### Tests

- `tests/operator-only-commands.bats` renamed to `tests/no-operator-only-on-init-archive.bats`; all 13 assertions inverted from «marker present» to «marker absent» so the same surfaces stay tracked and a red test fires if the operator-only contract drifts back in.
- New `tests/init-archive-structural-guards.bats` (9 invariants) — asserts that `pre-archive-check.sh`, `datarim-doctor.sh`, PRE-ARCHIVE CLEAN-GIT CHECK header, blob-swap recipe, Archive Area Mapping, Operator Handoff section, STRUCTURAL COMPLIANCE CHECK and WORKSPACE CROSS-TASK HYGIENE CHECK references remain in place after the relaxation.

## [2.9.0] — 2026-05-14

**Init-task Q&A auto-append.** Extends the v2.8.0 init-task persistence contract: every operator clarification round captured by a pipeline command now lands in `tasks/{TASK-ID}-init-task.md § Append-log` as a structured Q&A block. When the operator does not answer, the agent decides autonomously (FB-1..FB-5 of the Autonomous Agent Operating Rules) and records the rationale alongside the decision; `/dr-qa` Layer 3b verifies every agent-decision against the implementation and blocks the overall verdict on any unclosed cross-wish conflict.

### Added — Q&A round-trip contract (init-task auto-append)

- Extended skill `init-task-persistence` with a new `## Q&A round-trip contract` section (block format, mandatory subheadings, `Decided by: operator|agent` semantics, ≥50-char rationale on agent decisions, conflict-routing rules, legacy fallback).
- New utility `dev-tools/append-init-task-qa.sh` — atomic Q&A block append with mkdir-based per-task lock (macOS-portable), temp-file + `mv` write, realpath boundary check, 100 KB per-file size cap, and Security Mandate § S1 file-only free-form input contract.
- Extended validator `dev-tools/check-init-task-presence.sh` with `validate_qa_blocks` — finds `### <ISO> — Q&A by /dr-<stage> (round N)` blocks, asserts five mandatory subheadings, allowed `Decided by` enum, and ≥50-char `Decision rationale` body when `Decided by: agent`.
- Six pipeline commands wired with an `APPEND Q&A IF ANY` step (`/dr-prd`, `/dr-plan`, `/dr-design`, `/dr-do`, `/dr-qa`, `/dr-compliance`); `/dr-init` and `/dr-archive` stay read-only by contract.
- `/dr-qa` Layer 3b gains a `Q&A round-trip verification` sub-section with two checks: agent-decision implementation grep + Conflict closure verification; an unclosed Conflict raises Layer 3b verdict BLOCKED and routes the task to `/dr-do --focus-items <wish_id>`.
- Regression coverage: 18 bats cases in `tests/tune-0216-qa-roundtrip.bats` (six phases — skill / validator / utility / commands / Layer 3b / legacy fallback).

## [2.8.0] — 2026-05-14

**Operator-memory pipeline upgrade.** Seven related improvements ship together under the umbrella of «remember what the operator asked for, across the full pipeline»: verbatim init-task persistence, operator wishlist with verification gate, browser-based frontend QA, plain-language operator recap on three commands, archive section that mirrors the wishlist outcome, refreshed visual maps, and a coherent docs/site fanout. Backwards-compatible for legacy tasks via a 30-day rolling soft window; the new gates default to `info`-severity advisories that never block legacy pipelines.

### Added — Init-task persistence (F1)

Every `/dr-init` now writes a per-task `init-task.md` with a closed-schema frontmatter and a verbatim `## Operator brief` section. Every later pipeline command MUST read this file and append-log block before its first action; divergences between the operator's stated intent and the planned/implemented work are recorded in the task-description's Implementation Notes.

- New skill `init-task-persistence` (12-field frontmatter, append-log semantics, operator-only writes).
- New validator `dev-tools/check-init-task-presence.sh` (30-day rolling soft window, info < 30 d, warn ≥ 30 d, never blocker for legacy tasks).
- Nine pipeline commands read init-task at first step.
- Regression coverage: 13 bats cases.

### Added — Expectations checklist + verification gate (F2 + F3)

`/dr-prd` (L3-L4) and `/dr-plan` (L2 without PRD) write an operator-readable wishlist in plain Russian; `/dr-qa` Layer 3b and `/dr-compliance` Step 5b verify the checklist; missed items without operator override route the task back to `/dr-do --focus-items <wish_ids>` via the FAIL-Routing CTA.

- New skill `expectations-checklist` (Option B schema: flat markdown, kebab-slug wish_id with cyrillic, История статусов running log, Текущий статус enum, override line ≥10 chars).
- New validator `dev-tools/check-expectations-checklist.sh` with `--task` / `--verify` / `--all` modes; cyrillic wish_ids round-trip through shell arguments safely.
- New Layer 3b in `/dr-qa` between Layer 3 (plan) and Layer 4 (code) — FAIL makes the overall verdict BLOCKED regardless of other layers.
- Regression coverage: 16 + 8 bats cases.

### Added — Browser-based frontend QA (F4)

When a task changes any frontend markup, `/dr-qa` Layer 4f resolves an available browser tool, acquires a per-task lock, opens the local dev surface, and writes screenshot + trace + summary into `datarim/qa/playwright-{TASK-ID}/run-<ISO-ts>/`. Skipped silently for non-frontend tasks. Three headed modes: default headless, lenient `--headed` (no display ⇒ finding + fall through), strict `--headed-strict` (no display ⇒ exit 2).

- New skill `playwright-qa` (frontend touch detection, resolution chain CLI → MCP → env-browser, headed semantics, artefact layout).
- New tool `dev-tools/detect-playwright-tooling.sh` with `--require` / `--json` / `--headed` / `--headed-strict`, `DATARIM_PLAYWRIGHT` env override, path-traversal guard, mkdir-fallback lock.
- Regression coverage: 15 bats cases.

### Added — Plain-language reports across `/dr-qa`, `/dr-compliance`, `/dr-archive` (F5, absorbs TUNE-0195)

All three operator-facing commands end with a four-sub-section recap («Что было сделано», «Что получилось», «Что не получилось / осталось открытым», «Что дальше») between the technical block and the CTA block. Banlist (50 anglicism tokens) + whitelist (30 universal terms — `JSON`, `OAuth`, `HTTP`, `CLI`, `RFC`, `CI/CD`, …) + per-paragraph `<!-- gate:literal -->` escape hatch (≤ 2 fenced paragraphs per summary). Severity ladder: 1st offence ⇒ info, 3rd ⇒ warn, 5th ⇒ block. Archive documents written before this contract are grandfathered and never re-validated.

- New skill `human-summary` (four sub-headings, 150–400 word budget, per-caller mutability, banlist + whitelist + escape hatch, severity ladder, RU and EN examples).
- New sibling files `skills/human-summary/banlist.txt` and `whitelist.txt`.
- New Step 8 in `/dr-qa`, `/dr-compliance`, `/dr-archive` — uniform contract; archive variant is chat-only (archive document is the permanent record).
- Regression coverage: 24 bats cases.

### Added — Archive expectations section (F6)

Every `archive-{ID}.md` carries a new `## Выполнение ожиданий оператора` section between Final Acceptance Criteria and Known Outstanding State. Each operator wish is rendered as a single-level bullet with the plain-language status word (`выполнено` / `частично` / `не выполнено` / `неприменимо` — never the raw schema enum) and one or two sentences of comment sourced from the most recent История статусов reason. No tables; banlist applies; missing expectations file ⇒ explicit «Чек-лист ожиданий не заводился» line preserves the canonical archive shape.

- `templates/archive-template.md` carries the section placeholder.
- `commands/dr-archive.md` Step 2 enumerates the mandatory section, status-word translation, no-tables + no-anglicisms rules.
- Regression coverage: 10 bats cases.

### Changed — Visual maps refreshed with new artefact and skill nodes

The fragment-index visual maps gain three new artefact nodes (`init-task`, `expectations`, `playwright-run`) in a new «Artifact Flow Across the Pipeline» diagram, four new skill nodes (`init-task-persistence`, `expectations-checklist`, `playwright-qa`, `human-summary`) in the Agent ↔ Skill dependency graph, and Layer 3b + Layer 4f branches in the `/dr-qa` stage flow.

- `skills/visual-maps/SKILL.md` fragment descriptions updated.
- `skills/visual-maps/pipeline-routing.md` carries a new 10-node Artifact Flow Mermaid block (under the 25-node cap).
- `skills/visual-maps/stage-process-flows.md` updates `/dr-prd`, `/dr-plan`, `/dr-qa` flows.
- `skills/visual-maps/utility-and-dependencies.md` wires four new skill nodes to relevant agents.
- Regression coverage: 18 bats cases.

### Changed — Skill count

Framework now ships **45 skills** (was 41 — +4 from this release: `init-task-persistence`, `expectations-checklist`, `playwright-qa`, `human-summary`). All consumer surfaces (`CLAUDE.md`, `README.md`, `docs/skills.md`, public site) brought to the same count.

## [2.7.0] — 2026-05-13

**Two operator-facing surface improvements ship together.** `/dr-init` gains a topic-overlap advisory against the pending backlog; `/dr-compliance` and `/dr-archive` emit a plain-language operator recap after their technical block. Both are non-blocking surface additions — pipeline ordering, complexity routing, and existing exit-code contracts remain unchanged.

### Added — `/dr-init` Step 2.5b · Topic Overlap Advisory

Detects when a fresh task description overlaps in topic with **pending backlog items** (orthogonal to Step 2.5, which catches foreign task IDs in pending diffs). Recurrence motivating the gate: two backlog IDs spawned for one deliverable when an earlier pending item escaped notice during a fresh `/dr-init`. Advisory only — non-blocking, `exit 0` by contract — so operators see a soft warning and choose `duplicate` / `refine-scope` / `orthogonal` before committing.

- **New detector `dev-tools/check-topic-overlap.py`** — Python 3 stdlib only, no pip dependencies. RU + EN tokenisation, hand-curated stopword corpora under `dev-tools/data/stopwords-{en,ru}.txt` (≥200 entries each, includes Datarim domain noise), crude suffix stemmer, top-N significant stems against pending backlog titles. Output formats: `text` (operator-readable, default) and `json` (structured matches with `task_id`, `title`, `matched`, `overlap_count`). `--include-status` (default `pending`) lets pilots scan `in_progress` items too for self-overlap demos.
- **`commands/dr-init.md`** — Step 2.5b inserted after the existing workspace-hygiene check. Skips silently when `python3` is absent, `backlog.md` empty of `pending` items, or detector missing (older install). Non-tty / CI runs capture stdout into the step report and never prompt.
- **Regression coverage:** `tests/dr-init-topic-overlap.bats` (PRD cases a/b/c — overlap surfaced, orthogonal not flagged, RU+EN mixed), `tests/dr-init-topic-overlap-fp-budget.bats` (FP rate <10% on 30-item orthogonal corpus + TP rate ≥4/5 on known-overlap probes), `tests/dr-init-topic-overlap-latency.bats` (≤300 ms on a 500-item synthetic backlog, measured via `time.perf_counter` for portability across macOS / Linux).
- **Notes:** Class B operating-model change — surface lives in `dr-init` only. No new runtime dependency: `python3` is already present on every Datarim consumer that exercises any existing python-fenced skill, and Step 2.5b skips silently when absent.

### Added — Human-readable operator recap after `/dr-compliance` and `/dr-archive`

A new skill defines a 4-sub-section recap (what was done / what worked / what didn't work or is still open / what's next) that both operator-facing commands now emit between their technical block (verdict / archive write) and the CTA block. The recap follows the operator's most recent message language (Russian default for Arcanada consumers, English otherwise), bans tables and jargon, and is capped at 150–400 words. The technical output is unchanged.

- **`skills/human-summary/SKILL.md`** — contract: 4 fixed sub-headings, length budget 150–400 words, anti-patterns (tables, English loanwords in Russian text, bare task IDs, multi-level nested lists, acronyms without expansion, emoji, mixed-language summaries), RU and EN mini-examples.
- **`commands/dr-compliance.md` Step 8 — HUMAN SUMMARY.** Runs on every verdict; on NON-COMPLIANT the «what didn't work» sub-section carries the failure detail in plain language and «what's next» mirrors the FAIL-Routing CTA without command syntax.
- **`commands/dr-archive.md` Step 8 — HUMAN SUMMARY.** Sourced from the just-written archive document plus the reflection file. Chat-only — archive and reflection are not mutated.
- **`tests/test-human-summary-contract.bats`** — 9 spec-regression tests guarding skill existence, four mandated sub-headings, RU+EN mini-examples, length budget declaration, and cross-references from both commands.

## [2.6.1] — 2026-05-12

**`/dr-doctor` recognises three additional legacy formats.** Bug fix completes the schema-migration surface that earlier passes left silently broken on real-world repos. Pass 1 regex extended to compound IDs + optional trailing colon; new Pass 7 strips one-line HTML-comment archive notes when the cited archive file exists; new Pass 0 rejects misplaced `## Backlog` sections inside `tasks.md`.

### Added

- **Pass 0 — `## Backlog` reject in `tasks.md`** (`scripts/datarim-doctor.sh`, `skills/datarim-doctor/SKILL.md`). Detects `^## Backlog$` header inside `tasks.md`; emits finding `'## Backlog' section forbidden in tasks.md — move bullets manually to backlog.md` and exits 1 in dry-run mode. `--fix` does NOT auto-migrate (cross-task hunk corruption risk); operator manually relocates bullets.
- **Pass 7 — HTML-comment archive notes verified-strip** (`scripts/datarim-doctor.sh`, `skills/datarim-doctor/SKILL.md`). Recognises `<!-- {ID} {archived|cancelled|superseded|closed|dropped} {YYYY-MM-DD} → documentation/archive/{area}/archive-{ID}.md (...) -->`. Strips line iff the cited archive file exists; otherwise preserves with WARN. Path-traversal guard via `validate_relpath`; filename-match guard requires basename = `archive-{ID}.md` to prevent cross-ID strip. Idempotent.

### Changed

- **Pass 1 regex** — compound IDs (`PREFIX-NNNN-FOLLOWUP-slug`) and optional trailing colon now accepted. Updated touchpoints: `extract_ids`, `extract_block` awk, `extract_title`, pre-fix `PARSED_COUNT`, `migrate_file` guard, Pass 4 awk. Backwards-compatible with canonical `### PREFIX-NNNN:` shape.
- **`extract_title`** — synthesises title from compound suffix when block header has no trailing text. Strips literal `FOLLOWUP-` token, replaces hyphens with spaces, sentence-cases first character; appends « follow-up » suffix when the literal `FOLLOWUP` segment appeared in the ID.
- **`ONELINER_RE`** — accepts compound IDs in both the bullet ID position and the description-file pointer (`tasks/{ID}-task-description.md`). Restores write/read symmetry — Pass 1 migration output now passes the schema gate.
- **`EMITTED_COUNT` post-write invariant regex** — accepts compound IDs. Without this, the data-loss safety contract restored from backup on every compound-ID migration.

### Tests

- 4 new bats cases covering compound-ID block migration, headerless-fallback firing under prior manual-migration marker carry-over, Pass 7 verified-strip + idempotence, Pass 0 reject. Existing cases unchanged. Total 52/52 green. `shellcheck -S warning` zero.

## [2.3.0] — 2026-05-11

**First non-core plugin — `dr-orchestrate` Phase 1 (Lean tmux Runner).** TUNE-0164 ships the Datarim plugin reference implementation on top of TUNE-0101 plugin system: tmux-driven self-running pipeline runner with security floor (whitelist + 0x1b escape block + 500 ms / 60 s cooldown + 5-violations/hr → 1 h pane block, fail-closed), YAML secrets backend (mode-0600 enforced), JSONL audit with hash-only matched text. Phase 1 covers V-AC 1–15 (lean rule-based runner). Phase 2 (TUNE-0165) adds subagent inference + Telegram bridge; Phase 3 (TUNE-0166) adds auto-learning + 24 h re-validation.

### Added

- **TUNE-0164 — `plugins/dr-orchestrate/`** _(NEW plugin, 13 files)_ — first non-core plugin shipping with the framework.
  - `plugin.yaml` — schema_version 1 manifest (id `dr-orchestrate`, version `0.1.0`, category `commands`).
  - `scripts/plugin.sh` — hook dispatcher (`dispatch on_cycle [--dry-run]`, `dispatch on_tune_complete`, `get_autonomy → 1`).
  - `scripts/cmd_run.sh` — `dr-orchestrate run` entry. bash-4+ + tmux-1.7+ preflight; single iteration; default audit at `~/.local/share/datarim-orchestrate/audit-YYYY-MM-DD.jsonl`.
  - `scripts/tmux_manager.sh` — session/pane CRUD (`session_init`, `pane_split`, `pane_kill`, `pane_send`, `pane_capture`, `tmux_version_check`).
  - `scripts/security.sh` — fail-closed security floor: whitelist `[a-zA-Z0-9 _./:=@-]`, byte-0x1b escape block, two-layer cooldown (`micro` 500 ms, `decision` 60 s), violation ledger, 1 h pane block on the 5th violation/hr.
  - `scripts/secrets_backend.sh` — YAML get with 0600 mode enforcement; Vault stub (Phase 2).
  - `scripts/audit_sink.sh` — `emit` JSONL append, `make_event` canonical schema (`timestamp, matched_text_hash, command, exit_code, duration_ms, pane_id`); OpsBot stub (Phase 2).
  - `scripts/semantic_parser.sh` — Phase 1 stub returning rule-based confidence for `/dr-{init,prd,plan,do,qa,archive}`.
  - `commands/dr-orchestrate.md` — command surface markdown.
  - `tests/*.bats` — 6 bats files covering V-AC 1–15.
  - `README.md` — plugin-level usage doc.
  - `user-config.template.yaml` — operator config template (gitignored when copied to `user-config.yaml`).
- **TUNE-0164 — `Projects/Websites/datarim.club/data/commands/dr-orchestrate.php`** _(NEW)_ — site command page (EN+RU, lifecycle, security summary).

### Changed

- **TUNE-0164 — `CLAUDE.md` § Commands** — added `/dr-orchestrate run` row (Plugin stage); commands count footer now `22 commands core + 1 plugin`.
- **TUNE-0164 — `README.md` § Plugin system** — added “Reference plugin: dr-orchestrate (v2.3.0+, TUNE-0164)” bullet.
- **TUNE-0164 — `docs/plugin-author-guide.md`** — appended “Reference Plugin: dr-orchestrate” section pointing at the new plugin as the canonical example.
- **TUNE-0164 — `.gitignore`** — added `plugins/dr-orchestrate/user-config.yaml` (operator-supplied secret).
- **TUNE-0164 — `VERSION`** 2.2.0 → 2.3.0 (minor — first non-core plugin).

### Notes

- Phase 1 ships `key_injection: false` by default; the operator must opt in via `user-config.yaml` to enable any `tmux send-keys`.
- Audit sink raw text is never persisted — `matched_text_hash` (sha256) is the only representation of pane content (V-AC-12).
- bats tests source the helper scripts and run on bash 3.2 (mac system); `cmd_run.sh` enforces a bash-4+ floor at runtime.

## [2.2.0] — 2026-05-10

**Documentation Taxonomy Mandate — Diátaxis adoption ecosystem-wide.** TUNE-0161 ships `skills/diataxis-docs/SKILL.md` as single source of truth for the four-category contract (tutorials / how-to / reference / explanation). `/dr-init` scaffold default flips to 4-category split with auto-mapped legacy stubs. `/dr-optimize` Step 6 detects drift via filesystem-presence + ≥3 docs threshold. Hard CI gate deferred to backlog after ≥3 live consumers.

### Added

- **TUNE-0161 — `skills/diataxis-docs/SKILL.md`** _(NEW)_ — Diátaxis taxonomy mandate: 4 closed categories (tutorials / how-to / reference / explanation), mapping table for legacy types (architecture / testing / deployment / gotchas / faq / glossary / troubleshooting / examples), exemption list (research-only / archive / vault / inbox / scratch), 6 anti-patterns. Stack-agnostic (no SSG/CMS lock-in).
- **TUNE-0161 — `templates/docs-diataxis/{tutorials,how-to,reference,explanation}/README.md`** _(NEW, 4 stub files)_ — per-category onboarding stubs ("when to write here" / "when NOT to write here" / naming convention) for `/dr-init` scaffold.
- **TUNE-0161 — `/dr-optimize` Step 6 — Diátaxis docs drift detector** _(commands/dr-optimize.md)_ — filesystem-presence + threshold ≥3 docs check (Bash; Step 6a), exemption-aware. On drift proposes `INFRA-* — Diátaxis docs reorg` in backlog. Soft warning only; hard CI gate deferred.
- **TUNE-0161 — `code/datarim/CLAUDE.md` § Documentation Taxonomy Mandate** — framework-level mandate section (between Security Mandate and Defensive Invariants), pointing to skill as single source of truth.

### Changed

- **TUNE-0161 — `skills/project-init/SKILL.md` Step 4** — scaffold default replaces flat `docs/{architecture,testing,deployment,gotchas}.md` with `docs/{tutorials,how-to,reference,explanation}/` 4-category split. Legacy stubs auto-mapped per skill mapping table: testing/deployment/gotchas → `how-to/`, architecture → `reference/`. Backwards-compat smooth (idempotency rule preserves existing files).
- **TUNE-0161 — `templates/project-docs-stubs.md`** — File-headers updated to Diátaxis paths (`docs/how-to/testing.md` etc.); architecture stub moved under `docs/reference/`. Mapping decision documented in template header.
- **TUNE-0161 — VERSION** 2.1.0 → 2.2.0 (minor — new feature + new contract artifact).

### Notes

- **TUNE-0161 — Public surface scan (Class B):** workspace `~/arcanada/CLAUDE.md` § Documentation Taxonomy Mandate added; `datarim.club` site (skill page + getting-started + changelog + content counts + config version) updated in same release.
- **TUNE-0161 — First consumer reframe:** TUNE-0117 (Diátaxis reorg для `datarim.club`) cross-linked as first consumer of the framework mandate.
- **TUNE-0161 — Hard CI gate** intentionally deferred to a separate backlog item (`INFRA-* — Diátaxis CI gate enforcement`), trigger: ≥3 live consumers post-mandate. Same detector flips from soft warning to `exit 1`.

## [2.1.0] — 2026-05-10

**Self-Verification v2 — tri-layer architecture + zero-flag UX.** TUNE-0144 (PRD-TUNE-0137 v2 Phase 2) ships the tri-layer pipeline; TUNE-0155 closes the zero-flag UX gap with a 6-step provider auto-resolution chain. Plus a batch of Class A reflection applies from AUTH-0061 / AUTH-0072 / ARCA-0007 / INFRA-0078 / TUNE-0114 follow-ups.

### Added

- **`/dr-verify` tri-layer architecture** _(TUNE-0144)_ — Layer 1 deterministic floor (`dev-tools/dr-verify-floor.sh`, pure shell, zero LLM cost) + Layer 2 cross-model peer-review (DeepSeek default via `coworker`, ~14× cheaper than Sonnet, clean external context — no self-agreement bias) + Layer 3 native runtime dispatch (Claude 3-agent canonical; Codex single-prompt demoted to `[experimental]` fallback retained for parity). Findings carry an explicit `source_layer` tag (`floor` / `peer_review` / `dispatch`) and dedupe across layers prefers earlier-source findings.
- **Provider auto-resolution chain** _(TUNE-0155)_ — `dev-tools/resolve-peer-provider.sh` 6-step chain (CLI → per-project `./datarim/config.yaml` → per-user XDG `~/.config/datarim/config.yaml` → coworker `--profile code` default → cross-Claude-family subagent fallback → same-model isolated last resort). Closes the zero-flag UX gap: `/dr-verify {TASK-ID}` runs end-to-end without an explicit `--peer-provider` flag.
- **Cross-Claude-family fallback** _(TUNE-0155)_ — `agents/peer-reviewer.md` (NEW Sonnet-tier subagent) dispatched at chain step #5 when no external provider is configured. Covered by Claude subscription, no per-user external API key required. Three-tier `peer_review_mode` taxonomy: `cross_vendor` / `cross_claude_family` / `same_model_isolated`.
- **`templates/datarim-config.yaml`** _(TUNE-0155, NEW)_ — per-project datarim-config schema (peer-review provider, cost cap, AAL targets, runtime preferences). Supports per-project (committed) vs per-user XDG (uncommitted) precedence; whitelist `deepseek | moonshot | openrouter | sonnet | haiku | opus | none` blocks malicious-PR typosquat injection.
- **`templates/archive-template.md`** _(TUNE-0144, NEW canonical)_ — adds `verification_outcome` block schema (`caught_by_verify`, `missed_by_verify`, `false_positive`, `n_a`, `dogfood_window`) — single source of truth for prospective dogfood measurement. `/dr-archive` Step 2 instructs operator to fill the block.
- **Token-cost tooling** _(TUNE-0144 + TUNE-0155)_ — `dev-tools/measure-invocation-token-cost.sh` (per-task aggregation from `~/.local/state/coworker/log/<YYYY-MM-DD>.jsonl`, OpenTelemetry-style dotted keys, provider breakdown) + `dev-tools/measure-prospective-rate.sh` (archive frontmatter aggregator with per-mode rate keys: `cross_vendor_rate`, `cross_claude_family_rate`, `same_model_isolated_rate`; emits `decision_hint` at threshold review).
- **JSONL emission discipline (Layer 2 reviewer prompts)** _(TUNE-0155)_ — `skills/self-verification/SKILL.md` § Layer 2 mandates suppression of PASS-as-finding entries: findings array carries only defects or incorrect-premise items. Compress confirmations into a final-line summary.
- **`/dr-plan` Step 6.5 — PRD AC verification command smoke-check** _(TUNE-0155)_ — every PRD AC `**Verification:**` line is smoke-checked at plan time against the implemented CLI surface (or pre-implementation skeleton). Phantom flags, positional-args invocations against named-flag contracts, and misnamed env vars caught here, not at `/dr-verify` post-`/dr-do`.
- **`/dr-plan` Step 6.5 — AC ↔ V-AC semantic match check** _(TUNE-0155)_ — Validation Checklist rows must verify what the AC actually asserts, not just verbatim mirror the AC number.
- **`/dr-plan` Phase 4 — architectural-superseding probe** _(INFRA-0078)_ — mandatory first sub-step before component breakdown: read archives referenced via `Spawned from` / `Source:` and answer whether the architectural problem is already solved by a sibling task. A 30-second grep at planning time prevents dedicated-host plans for problems already absorbed elsewhere.
- **`skills/evolution/SKILL.md` § Pattern: Split-Architecture Metrics for Absorption Tasks** _(TUNE-0114 follow-up)_ — aggregate token budgets fail when absorption adds on-demand files; replaced with idle hot-path + per-existing-file + on-demand-exempt buckets.
- **`skills/ai-quality/SKILL.md` § Pipeline-Position-Aware AC Formulation** _(AUTH-0072)_ — when AC asserts HTTP status, trace request through full middleware/filter chain; if status is downstream of any validator, phrase as semantic gate, not literal status.
- **`skills/testing/SKILL.md` § Reporting Test Counts in Audit Output** _(AUTH-0061)_ — QA/Compliance MUST derive per-spec test counts via mechanical extractor (framework-neutral contract; per-language regex examples behind `gate:example-only`).
- **`skills/compliance/SKILL.md` Step 7 — stale-base merge-result gate** _(AUTH-0061)_ — before flagging a regression from PR diff vs `origin/<base>`, check whether the diff is a side effect of base advancing past the branch's merge-base; simulate 3-way merge via `git merge-tree` before reporting.
- **`agents/developer.md` — resilience-pattern defaults + design-conformance audit** _(ARCA-0007)_ — circuit-breaker `errorFilter` defaults: 4xx excluded except 408/429 (downstream pressure signals); breaker.close → self-heal observability event with explicit listener-binding enumeration in plan. L3–L4 tasks: post-final-TDD design-conformance audit listing every event/lifecycle binding against the referenced ADR.
- **`templates/prd-template.md` § Success Criteria — falsifiability requirement** _(TUNE-0114 follow-up)_ — every quantitative AC cites verification command + exit-code contract inline. No "presumed met" verdicts.
- **`CLAUDE.md` § Self-Evolution — Validation Discipline** _(TUNE-0114 follow-up)_ — new schema validators ship as standalone `dev-tools/check-*.sh` / `measure-*.sh` scripts, NOT as new branches in `datarim-doctor.sh` (orthogonal-concerns rule).

### Changed

- **`/dr-verify` provider behaviour** _(TUNE-0155)_ — previous «default `deepseek`» literal demoted to chain step #4 (coworker `--profile code` recommended_provider). The CLI flag `--peer-provider` becomes chain step #1 (override). Existing invocations with explicit flag remain compatible; new invocations without the flag now resolve via chain rather than failing.
- **`skills/self-verification/SKILL.md` Findings Schema** _(TUNE-0155)_ — extended with `peer_review_mode` (3-tier enum) and `peer_review_provider_source_layer` (chain-step audit tag). Audit log preserves which external model produced which finding under which dispatch class.
- **Brand-hygiene cleanup** _(TUNE-0150)_ — active runtime cross-references to the external `superpowers:*` skill namespace replaced with local Datarim skill names in `skills/systematic-debugging/SKILL.md` (3 refs) and `skills/finishing-a-development-branch/SKILL.md` (2 refs); `skills/self-verification/SKILL.md` cleaned via TUNE-0155 overwrite (zero `superpowers:` refs remain). External worktree-manager path-interop strings (`~/.config/superpowers/worktrees/`) removed from the cleanup-eligibility list — Datarim runtime owns only `.worktrees/` and `worktrees/`. Lineage from the v2.0.0 absorption is preserved unchanged in CHANGELOG / PRDs / `docs/getting-started.md` (MIT attribution).

### Notes

- Class B-lite additive (no breaking changes). TUNE-0144 inherits scope from PRD-TUNE-0137 v1 → v2 revision; TUNE-0155 extends without contract change. Findings-only mode preserved at all layers — no auto-fix added.
- Cross-Claude-family dispatch (chain step #5) is **first measured tier** — empirical bias delta vs same-model self-critique remains under observation in the active dogfood window.
- Old `dev-tools/measure-verify-cost.sh` remains deprecated side-by-side from v2.0.0 (broken parser shape against current coworker log format); replacement is `dev-tools/measure-invocation-token-cost.sh`.
- Codex CLI degraded mode: when `CODEX_RUNTIME=1` is set, chain step #5 is skipped and step #6 (same-model isolated) is taken; orchestrator MUST propagate the WARN to audit log so operator sees the degraded path.
- Public-surface 4-way sync covered: `data/commands/dr-verify.php` (EN+RU), `docs/commands.md` row, framework `CLAUDE.md` § /dr-verify rewrite, `README.md` mention.
- **Counts-drift correction footnote (TUNE-0163, 2026-05-10)** — `README.md` § Directory Structure previously read `templates/ # Task and document templates (23 templates)`. The `23` figure was incorrect at origin (templates count was 19 at the time of the v2.1.0 sweep — actual `find templates -maxdepth 1 -name '*.md' | wc -l` = 19; templates were never 23). Corrected to `(19 templates)` by TUNE-0163. Original incorrect claim preserved here for audit trail. Same task corrects `(39 skills)` → `(40 skills)` in framework `CLAUDE.md:127` and `pages/about.php:15` on `datarim.club`.

## [2.0.0] — 2026-05-09

**Datarim Evolution V2 — multi-runtime framework (Claude + Codex).** TUNE-0114 umbrella ship.

### Added
- Multi-runtime install — `install.sh` now accepts `--with-claude`, `--with-codex`, `--project DIR`, `--yes`, `--dry-run`, `--force` (no flags = print help; legacy `--copy` still implies Claude with WARN).
- `AGENTS.md` — symlink → `CLAUDE.md` so Codex CLI and other agent runtimes that read `AGENTS.md` by convention work out of the box.
- 14 superpowers skills absorbed: 4 verbatim port (`finishing-a-development-branch`, `receiving-code-review`, `systematic-debugging`, `verification-before-completion`), 8 intent-layer rewrites (`brainstorming`, `dispatching-parallel-agents`, `executing-plans`, `requesting-code-review`, `subagent-driven-development`, `using-git-worktrees`, `writing-plans`, `writing-skills`), 2 merges (`test-driven-development` → `testing.md` § Discipline; `using-superpowers` → `datarim-system.md` § Skill Discovery).
- Per-skill `runtime: [claude, codex]` + `current_aal` / `target_aal` frontmatter on all 38 top-level skills (per AAL Mandate; classification per PRD-TUNE-0114 §7).
- `dev-tools/measure-skill-token-cost.sh` — token-budget regression gate (AC-4 idle hot-path ≤+16% + per-existing-file ≤+30%).
- `dev-tools/check-skill-frontmatter.sh` — AC-8 standalone validator for `runtime:` + AAL keys + AGENTS.md symlink.
- `CHANGELOG.md` — Keep-a-Changelog format introduced.
- `.datarim/baseline-v1.23.0.tokens` — frozen baseline for token-budget verification.

### Changed
- **Honest positioning** — Datarim is now described as **multi-runtime framework (Claude + Codex)**, not "vendor-neutral". Cursor / Goose / Aider — future milestones, not current scope.
- `install.sh` — flag-based architecture; collision handling via atomic `mv -T` backup; `--project DIR` copy mode rejects system paths (`/etc`, `/usr`, `/bin`, `/sbin`, `/System`); `~/.${runtime}/.install.lock` lockfile blocks concurrent runs.
- `skills/datarim-system/SKILL.md` § Skill Discovery — meta-navigation rewrite (merged from `using-superpowers`).
- `skills/testing/SKILL.md` § Discipline — TDD discipline appended (merged from `test-driven-development`); supporting fragment `skills/testing/tdd-discipline.md`.

### Notes
- **Codex disclaimer:** Codex experience may differ — no `Task` / `TodoWrite` primitives. Intent-layer rewrites use functional prose so the absorbed skills work runtime-agnostically.
- **No breaking changes for existing Claude installs.** Refresh via `./install.sh --with-claude` — symlink layout preserved.
- Sub-tasks unblocked: TUNE-0115 (Adversarial Review skill split), TUNE-0117 (Diátaxis reorg), TUNE-0118 (`/dr-status` pull-mode), TUNE-0119 (Party Mode → Consilium-lite).
- Follow-ups spawned: TUNE-0125 (project-local evolution learning routing), TUNE-0116 (Module Manifest — separate task).

## [1.24.0] — 2026-05-07

### Added
- _(TUNE-0109)_ Secure-by-default Network Exposure Gate (tiered model, reusable CI workflow)

## [1.24.0] — 2026-05-07

### Added
- _(TUNE-0109)_ Secure-by-default Network Exposure Gate (tiered model, reusable CI workflow)

## [1.23.0] — 2026-05-04

Baseline reference for TUNE-0114 token-cost regression measurements.
