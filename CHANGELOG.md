# Changelog

All notable changes to the Datarim framework are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

- **`skills/human-summary.md`** — contract: 4 fixed sub-headings, length budget 150–400 words, anti-patterns (tables, English loanwords in Russian text, bare task IDs, multi-level nested lists, acronyms without expansion, emoji, mixed-language summaries), RU and EN mini-examples.
- **`commands/dr-compliance.md` Step 8 — HUMAN SUMMARY.** Runs on every verdict; on NON-COMPLIANT the «what didn't work» sub-section carries the failure detail in plain language and «what's next» mirrors the FAIL-Routing CTA without command syntax.
- **`commands/dr-archive.md` Step 8 — HUMAN SUMMARY.** Sourced from the just-written archive document plus the reflection file. Chat-only — archive and reflection are not mutated.
- **`tests/test-human-summary-contract.bats`** — 9 spec-regression tests guarding skill existence, four mandated sub-headings, RU+EN mini-examples, length budget declaration, and cross-references from both commands.

## [2.6.1] — 2026-05-12

**`/dr-doctor` recognises three additional legacy formats.** Bug fix completes the schema-migration surface that earlier passes left silently broken on real-world repos. Pass 1 regex extended to compound IDs + optional trailing colon; new Pass 7 strips one-line HTML-comment archive notes when the cited archive file exists; new Pass 0 rejects misplaced `## Backlog` sections inside `tasks.md`.

### Added

- **Pass 0 — `## Backlog` reject in `tasks.md`** (`scripts/datarim-doctor.sh`, `skills/datarim-doctor.md`). Detects `^## Backlog$` header inside `tasks.md`; emits finding `'## Backlog' section forbidden in tasks.md — move bullets manually to backlog.md` and exits 1 in dry-run mode. `--fix` does NOT auto-migrate (cross-task hunk corruption risk); operator manually relocates bullets.
- **Pass 7 — HTML-comment archive notes verified-strip** (`scripts/datarim-doctor.sh`, `skills/datarim-doctor.md`). Recognises `<!-- {ID} {archived|cancelled|superseded|closed|dropped} {YYYY-MM-DD} → documentation/archive/{area}/archive-{ID}.md (...) -->`. Strips line iff the cited archive file exists; otherwise preserves with WARN. Path-traversal guard via `validate_relpath`; filename-match guard requires basename = `archive-{ID}.md` to prevent cross-ID strip. Idempotent.

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

**Documentation Taxonomy Mandate — Diátaxis adoption ecosystem-wide.** TUNE-0161 ships `skills/diataxis-docs.md` as single source of truth for the four-category contract (tutorials / how-to / reference / explanation). `/dr-init` scaffold default flips to 4-category split with auto-mapped legacy stubs. `/dr-optimize` Step 6 detects drift via filesystem-presence + ≥3 docs threshold. Hard CI gate deferred to backlog after ≥3 live consumers.

### Added

- **TUNE-0161 — `skills/diataxis-docs.md`** _(NEW)_ — Diátaxis taxonomy mandate: 4 closed categories (tutorials / how-to / reference / explanation), mapping table for legacy types (architecture / testing / deployment / gotchas / faq / glossary / troubleshooting / examples), exemption list (research-only / archive / vault / inbox / scratch), 6 anti-patterns. Stack-agnostic (no SSG/CMS lock-in).
- **TUNE-0161 — `templates/docs-diataxis/{tutorials,how-to,reference,explanation}/README.md`** _(NEW, 4 stub files)_ — per-category onboarding stubs ("when to write here" / "when NOT to write here" / naming convention) for `/dr-init` scaffold.
- **TUNE-0161 — `/dr-optimize` Step 6 — Diátaxis docs drift detector** _(commands/dr-optimize.md)_ — filesystem-presence + threshold ≥3 docs check (Bash; Step 6a), exemption-aware. On drift proposes `INFRA-* — Diátaxis docs reorg` in backlog. Soft warning only; hard CI gate deferred.
- **TUNE-0161 — `code/datarim/CLAUDE.md` § Documentation Taxonomy Mandate** — framework-level mandate section (between Security Mandate and Defensive Invariants), pointing to skill as single source of truth.

### Changed

- **TUNE-0161 — `skills/project-init.md` Step 4** — scaffold default replaces flat `docs/{architecture,testing,deployment,gotchas}.md` with `docs/{tutorials,how-to,reference,explanation}/` 4-category split. Legacy stubs auto-mapped per skill mapping table: testing/deployment/gotchas → `how-to/`, architecture → `reference/`. Backwards-compat smooth (idempotency rule preserves existing files).
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
