# Changelog

All notable changes to the Datarim framework are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.1.0] — 2026-05-10

**Self-Verification v2 — tri-layer architecture + zero-flag UX.** TUNE-0144 (PRD-TUNE-0137 v2 Phase 2) ships the tri-layer pipeline; TUNE-0155 closes the zero-flag UX gap with a 6-step provider auto-resolution chain. Plus a batch of Class A reflection applies from AUTH-0061 / AUTH-0072 / ARCA-0007 / INFRA-0078 / TUNE-0114 follow-ups.

### Added

- **`/dr-verify` tri-layer architecture** _(TUNE-0144)_ — Layer 1 deterministic floor (`dev-tools/dr-verify-floor.sh`, pure shell, zero LLM cost) + Layer 2 cross-model peer-review (DeepSeek default via `coworker`, ~14× cheaper than Sonnet, clean external context — no self-agreement bias) + Layer 3 native runtime dispatch (Claude 3-agent canonical; Codex single-prompt demoted to `[experimental]` fallback retained for parity). Findings carry an explicit `source_layer` tag (`floor` / `peer_review` / `dispatch`) and dedupe across layers prefers earlier-source findings.
- **Provider auto-resolution chain** _(TUNE-0155)_ — `dev-tools/resolve-peer-provider.sh` 6-step chain (CLI → per-project `./datarim/config.yaml` → per-user XDG `~/.config/datarim/config.yaml` → coworker `--profile code` default → cross-Claude-family subagent fallback → same-model isolated last resort). Closes the zero-flag UX gap: `/dr-verify {TASK-ID}` runs end-to-end without an explicit `--peer-provider` flag.
- **Cross-Claude-family fallback** _(TUNE-0155)_ — `agents/peer-reviewer.md` (NEW Sonnet-tier subagent) dispatched at chain step #5 when no external provider is configured. Covered by Claude subscription, no per-user external API key required. Three-tier `peer_review_mode` taxonomy: `cross_vendor` / `cross_claude_family` / `same_model_isolated`.
- **`templates/datarim-config.yaml`** _(TUNE-0155, NEW)_ — per-project datarim-config schema (peer-review provider, cost cap, AAL targets, runtime preferences). Supports per-project (committed) vs per-user XDG (uncommitted) precedence; whitelist `deepseek | moonshot | openrouter | sonnet | haiku | opus | none` blocks malicious-PR typosquat injection.
- **`templates/archive-template.md`** _(TUNE-0144, NEW canonical)_ — adds `verification_outcome` block schema (`caught_by_verify`, `missed_by_verify`, `false_positive`, `n_a`, `dogfood_window`) — single source of truth for prospective dogfood measurement. `/dr-archive` Step 2 instructs operator to fill the block.
- **Token-cost tooling** _(TUNE-0144 + TUNE-0155)_ — `dev-tools/measure-invocation-token-cost.sh` (per-task aggregation from `~/.local/state/coworker/log/<YYYY-MM-DD>.jsonl`, OpenTelemetry-style dotted keys, provider breakdown) + `dev-tools/measure-prospective-rate.sh` (archive frontmatter aggregator with per-mode rate keys: `cross_vendor_rate`, `cross_claude_family_rate`, `same_model_isolated_rate`; emits `decision_hint` at threshold review).
- **JSONL emission discipline (Layer 2 reviewer prompts)** _(TUNE-0155)_ — `skills/self-verification.md` § Layer 2 mandates suppression of PASS-as-finding entries: findings array carries only defects or incorrect-premise items. Compress confirmations into a final-line summary.
- **`/dr-plan` Step 6.5 — PRD AC verification command smoke-check** _(TUNE-0155)_ — every PRD AC `**Verification:**` line is smoke-checked at plan time against the implemented CLI surface (or pre-implementation skeleton). Phantom flags, positional-args invocations against named-flag contracts, and misnamed env vars caught here, not at `/dr-verify` post-`/dr-do`.
- **`/dr-plan` Step 6.5 — AC ↔ V-AC semantic match check** _(TUNE-0155)_ — Validation Checklist rows must verify what the AC actually asserts, not just verbatim mirror the AC number.
- **`/dr-plan` Phase 4 — architectural-superseding probe** _(INFRA-0078)_ — mandatory first sub-step before component breakdown: read archives referenced via `Spawned from` / `Source:` and answer whether the architectural problem is already solved by a sibling task. A 30-second grep at planning time prevents dedicated-host plans for problems already absorbed elsewhere.
- **`skills/evolution.md` § Pattern: Split-Architecture Metrics for Absorption Tasks** _(TUNE-0114 follow-up)_ — aggregate token budgets fail when absorption adds on-demand files; replaced with idle hot-path + per-existing-file + on-demand-exempt buckets.
- **`skills/ai-quality.md` § Pipeline-Position-Aware AC Formulation** _(AUTH-0072)_ — when AC asserts HTTP status, trace request through full middleware/filter chain; if status is downstream of any validator, phrase as semantic gate, not literal status.
- **`skills/testing.md` § Reporting Test Counts in Audit Output** _(AUTH-0061)_ — QA/Compliance MUST derive per-spec test counts via mechanical extractor (framework-neutral contract; per-language regex examples behind `gate:example-only`).
- **`skills/compliance.md` Step 7 — stale-base merge-result gate** _(AUTH-0061)_ — before flagging a regression from PR diff vs `origin/<base>`, check whether the diff is a side effect of base advancing past the branch's merge-base; simulate 3-way merge via `git merge-tree` before reporting.
- **`agents/developer.md` — resilience-pattern defaults + design-conformance audit** _(ARCA-0007)_ — circuit-breaker `errorFilter` defaults: 4xx excluded except 408/429 (downstream pressure signals); breaker.close → self-heal observability event with explicit listener-binding enumeration in plan. L3–L4 tasks: post-final-TDD design-conformance audit listing every event/lifecycle binding against the referenced ADR.
- **`templates/prd-template.md` § Success Criteria — falsifiability requirement** _(TUNE-0114 follow-up)_ — every quantitative AC cites verification command + exit-code contract inline. No "presumed met" verdicts.
- **`CLAUDE.md` § Self-Evolution — Validation Discipline** _(TUNE-0114 follow-up)_ — new schema validators ship as standalone `dev-tools/check-*.sh` / `measure-*.sh` scripts, NOT as new branches in `datarim-doctor.sh` (orthogonal-concerns rule).

### Changed

- **`/dr-verify` provider behaviour** _(TUNE-0155)_ — previous «default `deepseek`» literal demoted to chain step #4 (coworker `--profile code` recommended_provider). The CLI flag `--peer-provider` becomes chain step #1 (override). Existing invocations with explicit flag remain compatible; new invocations without the flag now resolve via chain rather than failing.
- **`skills/self-verification.md` Findings Schema** _(TUNE-0155)_ — extended with `peer_review_mode` (3-tier enum) and `peer_review_provider_source_layer` (chain-step audit tag). Audit log preserves which external model produced which finding under which dispatch class.
- **Brand-hygiene cleanup** _(TUNE-0150)_ — active runtime cross-references to the external `superpowers:*` skill namespace replaced with local Datarim skill names in `skills/systematic-debugging.md` (3 refs) and `skills/finishing-a-development-branch.md` (2 refs); `skills/self-verification.md` cleaned via TUNE-0155 overwrite (zero `superpowers:` refs remain). External worktree-manager path-interop strings (`~/.config/superpowers/worktrees/`) removed from the cleanup-eligibility list — Datarim runtime owns only `.worktrees/` and `worktrees/`. Lineage from the v2.0.0 absorption is preserved unchanged in CHANGELOG / PRDs / `docs/getting-started.md` (MIT attribution).

### Notes

- Class B-lite additive (no breaking changes). TUNE-0144 inherits scope from PRD-TUNE-0137 v1 → v2 revision; TUNE-0155 extends without contract change. Findings-only mode preserved at all layers — no auto-fix added.
- Cross-Claude-family dispatch (chain step #5) is **first measured tier** — empirical bias delta vs same-model self-critique remains under observation in the active dogfood window.
- Old `dev-tools/measure-verify-cost.sh` remains deprecated side-by-side from v2.0.0 (broken parser shape against current coworker log format); replacement is `dev-tools/measure-invocation-token-cost.sh`.
- Codex CLI degraded mode: when `CODEX_RUNTIME=1` is set, chain step #5 is skipped and step #6 (same-model isolated) is taken; orchestrator MUST propagate the WARN to audit log so operator sees the degraded path.
- Public-surface 4-way sync covered: `data/commands/dr-verify.php` (EN+RU), `docs/commands.md` row, framework `CLAUDE.md` § /dr-verify rewrite, `README.md` mention.

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
- `skills/datarim-system.md` § Skill Discovery — meta-navigation rewrite (merged from `using-superpowers`).
- `skills/testing.md` § Discipline — TDD discipline appended (merged from `test-driven-development`); supporting fragment `skills/testing/tdd-discipline.md`.

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
