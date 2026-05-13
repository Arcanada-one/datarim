# Evolution Log

Append-only log of framework changes accepted from `/dr-archive` Step 0.5 reflection or curated runtime → repo updates.

---

## 2026-05-13 — CONN-0096 — Public Surface Hygiene Mandate cross-link + lint contract surface

### Class A Applied

- **`CLAUDE.md` § Public Surface Hygiene Mandate (cross-link) (NEW section).** CONN-0096 Proposal 1. Inserted between Documentation Taxonomy Mandate and Defensive Invariants. Mirrors the Autonomous Agent Operating Rules cross-link pattern — canonical mandate text lives in the consumer's ecosystem `CLAUDE.md`; framework ships the contract surface only. References `~/arcanada/CLAUDE.md` § Public Surface Hygiene Mandate as the Arcanada-ecosystem canonical source.
  - **File:** `CLAUDE.md` (~+18 prose lines inserted before § Defensive Invariants).
  - **Class:** A.
  - **Source:** CONN-0096 reflection Proposal 1.
  - **Stack-agnostic gate:** PASS (mode: `--diff-only`, no stack terms).
  - **Summary:** consumers shipping public packages MUST mirror canonical mandate in own ecosystem CLAUDE.md; framework ships lint script + regex file as contract surface, not the rules text.

- **`dev-tools/public-surface-lint.sh` + `dev-tools/public-surface-forbidden.regex` + `dev-tools/tests/public-surface-lint.bats` (NEW files).** CONN-0096 Proposal 2. Pure-shell linter greps supplied paths for forbidden references (PRD-/creative-/plans-/insights- patterns, internal-datarim-repo paths, milestone-code references) loaded from a sibling `.regex` file. Single `--check` mode: exit 0 = clean, exit 1 = found, exit 2 = usage error. Skips `dist/` / `build/` / `node_modules/` / `.venv/` / `.git/` / `__pycache__/` / `.pytest_cache/` by default. Per `dev-tools/` orthogonal-tool rule — content validation lives outside `datarim-doctor.sh`. Bats spec covers 14 cases (clean, all 4 forbidden-prefix variants, internal-link variant, milestone-code variant, skip-dist variant, report mode positive + negative, missing/empty regex error paths, unknown-argument error path).
  - **Files:** `dev-tools/public-surface-lint.sh` (~135 LoC including spec comments), `dev-tools/public-surface-forbidden.regex` (~25 LoC including comment header), `dev-tools/tests/public-surface-lint.bats` (~110 LoC, 14 test cases).
  - **Class:** A.
  - **Source:** CONN-0096 reflection Proposal 2.
  - **Stack-agnostic gate:** PASS (pure bash + grep, no stack terms in script body or docs).
  - **Bats verification:** 14/14 pass. Pre-existing framework bats failures (T11, T12, D5, 336, 384) are baseline regressions on origin/main, not caused by these additions (verified via `git stash` + `bats tests/` → identical failure set).
  - **Summary:** contract-surface lint that consumers wire into their CI / pre-publish hook; consumers extend the regex set with their own task-prefix patterns at install time.

### Class A Applied (consumer-side, not framework runtime)

- **Auto-memory `feedback_token_health_probe_before_publish.md`.** CONN-0096 Proposal 3. New ecosystem-side memory: every CI workflow depending on a long-lived token (npm/PyPI/Docker/CF) MUST health-probe the token at job start, not at the publish step. Distinct exit code on expiry distinguishes "rotate token" from "investigate publish failure". Pattern mirrors `feedback_openrouter_key_revoke_probe` for OpenRouter — generalised across token providers.
  - **File:** `~/.claude/projects/-Users-ug-arcanada/memory/feedback_token_health_probe_before_publish.md` (ecosystem-side, not framework runtime).
  - **MEMORY.md index updated** with one-line pointer.
  - **Class:** A.
  - **Source:** CONN-0096 reflection Proposal 3.
  - **Stack-agnostic gate:** N/A (ecosystem-side memory; framework gate does not apply).
## 2026-05-13 — INFRA-0192 — Live Smoke-Test Gates: Current-State Auth Probe subsection (INFRA-0191 follow-up F-1)

### Class A Applied

- **`skills/testing/live-smoke-gates.md` — `## Current-State Auth Probe` subsection (NEW, 22 lines).** Pre-flight requirement for every gate below; prescribes hitting an auth-scoped capability-cheap endpoint with the same credential before the capability test, a distinct sentinel/exit code on auth failure, and recording the probe result alongside the smoke result in the QA report.
  - **File:** `code/datarim/skills/testing/live-smoke-gates.md` (subsection inserted between the intro paragraph and `## Gate 1`).
  - **Class:** A (closes the Class A Deferred entry from the 2026-05-13 INFRA-0191 section below).
  - **Source:** INFRA-0191 reflection Proposal A1 + backlog INFRA-0192.
  - **Stack-agnostic gate:** PASS (`scripts/stack-agnostic-gate.sh --diff-only skills/testing.md` and `--diff-only skills/testing/live-smoke-gates.md` both clean).
  - **Regression spec:** `code/datarim/tests/skill-testing-current-state-auth-probe.bats` (5 assertions — file presence, header presence, ordering after `# Live Smoke-Test Gates`, stack-neutral wording, ≤30-line body).
  - **Reword applied:** "migration roadmap toward a centralised identity provider" replaces the original draft phrasing that referenced an ecosystem-specific migration list.

---

## 2026-05-13 — INFRA-0191 — Cron-agent multi-provider memory rule (1 of 2 Class A proposals applied; 1 deferred + 1 Class B held)

### Class A Applied

- **Memory rule `feedback_cron_agent_multi_provider.md` (NEW).** INFRA-0191 Proposal A2. Documents PRIMARY (subscription/free-tier subprocess) → FALLBACK (Model Connector universal `/execute`) pattern with fail-soft sentinels for cron-style AI agents. Applies to Email Agent / Inbox Organizer / Twitter Collector / Screen Reader / Agent Dreamer. Sentinel strings (`<svc>-disabled`, `<svc>-http-XXX`, `<svc>-skipped`) used вместо exceptions so cron cycles degrade to `no-ai` notification instead of crashing.
  - **File:** `~/.claude/projects/-Users-ug-arcanada/memory/feedback_cron_agent_multi_provider.md` (NEW) + `MEMORY.md` index entry.
  - **Class:** A.
  - **Source:** INFRA-0191 reflection Proposal A2 + archive (commit `5485569` workspace).
  - **Stack-agnostic gate:** N/A — local user memory file (project-scoped, not framework runtime).
  - **Summary:** Cron agents with external LLM API deps adopt multi-provider chain with fail-soft sentinels at each layer; restores availability при quota exhaust без новых secrets.

### Class A Deferred (Pending Stack-Agnostic Rewording)

- **`skills/testing.md` § Live Smoke-Test Gate — Current-State Auth Probe** (Proposal A1). Текущая draft формулировка cites «Auth Arcana migration list (Phase 5+)», что fails `scripts/stack-agnostic-gate.sh`. Reword stack-neutral («migration roadmap toward centralised IdP») перед apply. Deferred to follow-up task F-1 (backlog spawn).

### Class B Held (PRD Required)

- **Project repo sync policy (Proposal B1).** INFRA-0189 + INFRA-0191 landed только в workspace `~/arcanada/.git`, не в `Arcanada-one/email-agent`. Per Operational Resilience Mandate Principle 1 — PRD-INFRA-XXXX needs to define canonical repo + sync direction + cadence. Deferred to follow-up F-4.

---

## 2026-05-11 — TUNE-0164 — Apply 4 Class A proposals to runtime (Phase 1 dr-orchestrate reflection)

### Class A Applied

- **`skills/datarim-system.md` § Large-Plan Read Strategy (L3+ tasks) (NEW section).** TUNE-0164 Proposal 1. Codifies the «coworker structured-summary on plans ≥ 600 lines» default for L3+ tasks: one delegated call returns per-step / per-V-AC / per-file specification that anchors implementation order, V-AC mapping, MOD touchpoints; QA and compliance reuse the same summary. Stack-neutral wording: «external-context delegation channel» / «runtime's external-LLM contract» — no vendor lock. References CLAUDE.md § Coworker Delegation for the concrete channel.
  - **File:** `skills/datarim-system.md` (~+30 prose lines inserted after § Quick Path Resolution Rule).
  - **Class:** A.
  - **Source:** TUNE-0164 reflection Proposal 1.
  - **Stack-agnostic gate:** PASS (mode: `--diff-only`).
  - **Summary:** L3+ tasks with PRD+plan+INSIGHTS ≥ 600 lines delegate the bulk read to an external-context channel; main context consumes the structured summary, not the raw artefacts.

- **`skills/ai-quality/bash-pitfalls.md` § «`date +%s%N` is GNU-only» + «`awk sub()` does NOT support capture groups» (TWO NEW sections).** TUNE-0164 Proposals 2 + 3. First section: portable millisecond clock recipe (Bash 5 `$EPOCHREALTIME` → `perl Time::HiRes` fallback); flags `date +%s%N` as silently broken on macOS / BSD. Second section: awk `sub()` / `gsub()` accept ERE pattern but treat `\1..\9` as literal text, no capture groups; canonical alternative is `match()` + `substr()` or sed/perl. Both pitfalls were hit during TUNE-0164 `/dr-do` and would have shipped silently broken on mac.
  - **File:** `skills/ai-quality/bash-pitfalls.md` (~+90 prose lines inserted before § Why this fragment exists).
  - **Class:** A.
  - **Source:** TUNE-0164 reflection Proposals 2 + 3.
  - **Stack-agnostic gate:** PASS (mode: `--diff-only`).
  - **Summary:** portable `now_ms` recipe (Bash 5 EPOCHREALTIME → perl); awk `sub()` capture-group trap with `match()` + `substr()` alternative.

### Class A Applied (consumer-side, not framework runtime)

- **`~/.claude/projects/-Users-ug-arcanada/memory/feedback_foreign_path_args_disambiguation.md` (NEW feedback memory).** TUNE-0164 Proposal 4. Auto-memory entry: when `/dr-*` invocation arguments include a filesystem path outside `~/arcanada/` or the active framework root, treat as a candidate parallel ask and confirm scope before touching the foreign repo. Indexed in `MEMORY.md`. Stack-neutral by virtue of living in personal auto-memory (consumer-side), not in framework runtime. Not in `code/datarim/{skills,agents,commands,templates}/`.

### Class A Applied (backlog spawn, no runtime change)

- **`datarim/backlog.md` — INFRA-* — TUNE-0101 plugin-system gitignore drift.** TUNE-0164 Proposal 5. Backlog entry only; no framework runtime change. Description: `dr-plugin enable/list/doctor` creates `enabled-plugins.md` and `plugin-storage/` at the framework repo root on first invocation; neither is gitignored. Surfaced during TUNE-0164 plugin-system smoke; cleaned post-smoke. Follow-up requires one-line `.gitignore` patch on the framework repo (and optionally a `dr-plugin clean` subcommand). Spawned in `/dr-archive` Step 4.

### Decisions Locked

- **D-1 (Proposal 4 routing):** Foreign-path argument disambiguation lives as a personal auto-memory entry (`memory/feedback_foreign_path_args_disambiguation.md`), NOT as a framework skill or CLAUDE.md amendment. Rationale: the rule is about how an agent interprets an operator's slash-command invocation — operator-specific workflow guidance, not framework contract. Auto-memory is the right surface; multiple operators may interpret foreign-path args differently.
- **D-2 (Proposals 2 + 3 colocated):** Both new pitfalls land in the same skill file (`skills/ai-quality/bash-pitfalls.md`) because they share the same audience (bash script authors / shell-pipeline reviewers) and the same recovery shape (canonical-recipe alternative). Splitting would duplicate the «Why this matters in practice» framing.

### Verification

- Stack-agnostic gate: `bash scripts/stack-agnostic-gate.sh --diff-only skills/datarim-system.md` → PASS clean. `bash scripts/stack-agnostic-gate.sh --diff-only skills/ai-quality/bash-pitfalls.md` → PASS clean.
- `bats tests/` after applies: 402 active passes, 5 pre-existing failures (D5 check-drift, 277 marketing description length, T3a dr-reflect whitelist, T11/T12 task-id-gate skills/commands scope). Pre-edit baseline identical 5/5; **zero new regressions attributable to TUNE-0164 Class A applies.**
- Provenance: this evolution-log entry + `datarim/reflection/reflection-TUNE-0164.md` + git log (commit `evolution(TUNE-0164): apply 4 Class A proposals to runtime`).

---

## 2026-05-09 — AUTH-0072 — Pipeline-position-aware AC formulation в `skills/ai-quality.md` (Class A)

### Class A Applied

- **Target:** `skills/ai-quality.md` — new section «Pipeline-Position-Aware AC Formulation» inserted before § Fragment Routing (~24 lines).
- **What changed:** added a rule that ACs asserting HTTP status code MUST trace request through full middleware/filter chain; if asserted source is downstream of any validator, phrase as **semantic gate** (`not <failure_class>`) instead of literal status. Includes failure-mode example, 3-step rule, semantic-gate template, applicability scope, anti-pattern.
- **Why:** AUTH-0072 cycle-1 finding #1 — PRD AC-11 declared «→ 401» without tracing pipeline; reality `Zod` validator runs *before* auth and short-circuits to `400`. Cost: PRD/plan/QA all required amendment under self-review (~30 min). Pattern is recurring across HTTP-routed code.
- **Verification:**
  - Stack-agnostic gate: PASS clean (stack-specific framework names wrapped in `<!-- gate:example-only -->` markers).
  - Bats `tests/`: 4 pre-existing baseline failures (D5 check-drift, T277 description-length, T325 dr-reflect whitelist, T11/T12 task-id-gate from `security-baseline.md` + untracked `self-verification.md`) — UNRELATED to this proposal. `task-id-gate` on `ai-quality.md` itself: PASS clean. No new failures introduced.

### Class B (HELD — pending PRD)

- **Proposal 2 — `/dr-archive` unpushed-commits = 0 gate.** Per project repo touched: `git rev-list --count origin/<default-branch>..HEAD` MUST = 0 OR explicit accept-loss in archive doc. Source: AUTH-0065 «code-complete» archive shipped with commit `81fc3ccab` only on local main → +1 day cycle (AUTH-0072). Modifies archive command contract → requires PRD draft before apply (suggested TUNE prefix).
- **Proposal 3 — `/dr-do` staging-not-stale pre-check.** Before any AC requiring staging E2E: `docker compose ps` + health-curl on staging host. Halt if dead/stale. Source: AUTH-0072 AC-10/11 partially blocked by INFRA-0111 compose collision. Modifies dr-do contract → requires PRD draft before apply.

---

## 2026-05-09 — INFRA-0078 — Architectural-superseding probe в `/dr-plan` Phase 4 (Class A)

### Class A Applied

- **`commands/dr-plan.md` § Detailed Design (Phase 4)** — добавлен mandatory first sub-step «Architectural-superseding probe». Перед component breakdown планер должен прочитать архивы, на которые ссылается `Spawned from` / `Source:` в задаче, и явно ответить: решена ли архитектурная проблема уже соседней задачей? Если да — рекомендовать cancellation / scope-reduction / re-framing как redundancy. Документировать ответ inline в Overview/Decisions секции плана.

### Why

INFRA-0078 был полностью спланирован как «выделенный RPi/NUC subnet router host» (Phase 4-6 + Appendix A Security написаны), прежде чем в фазе implementation выяснилось что INFRA-0073 уже сделал NAS прямым tailnet peer'ом — subnet router из primary path стал redundancy-only. Один grep по `Spawned from` ссылке (archive-INFRA-0072 → archive-INFRA-0073) на этапе /dr-plan вытащил бы этот факт за 30 секунд. Cost = тривиальный; saving = 1-2h plan churn + €100 averted hardware procurement + 3-7 day procurement loop avoided. Stack-agnostic gate PASS (clean diff).

### Held Class B (deferred)

- **Mandatory strategist gate для redundancy-only tasks** — proposal сделать L2 strategist gate non-skippable когда задача содержит keywords `fallback` / `redundancy` / `backup-of-backup` или `Spawned from` archive с completed primary path. Class B (operating-model change) — отложен до накопления N≥3 incidents (сейчас N=1). PRD draft потребуется для apply.

---

## 2026-05-04 — INFRA-0015 — research-workflow.md § Pre-Flight Artifact Discovery (Class A)

### Class A Applied

- **`skills/research-workflow.md` § Pre-Flight Artifact Discovery (NEW)** — Step 0 of `/dr-do` for any task referencing named artifacts (file paths, deployed services, infra resources, schemas). Procedure: enumerate → verify live → 3 outcomes (Match / Already done / Drift) → pivot via `INSIGHTS-{TASK-ID}.md` § Gap Discoveries when needed; cross-approach pivots re-read PRD § Solution Exploration. When-to-skip: plan <24h old + no parallel sessions + no prior shipped tasks in the area.

### Why

Plan called for sidecar migration; pre-flight discovered an already-shipped SDK-direct service (~1290 LoC). Phase 1 effort dropped from 1-2d to ~2h by following plan's already-rejected alternative with documented rationale. Stack-agnostic gate PASS, bats 160/160 PASS.

---

## 2026-05-03 — TUNE-0084 — pre-archive-check.sh classify by uncommitted diff + 3× Class A applies

### Summary

Refactored `pre-archive-check.sh` shared-mode classification: column 3 (`task-ids-csv`) now sources from `+/-` diff lines only (not `cat $file` body), so index files (`tasks.md`, `activeContext.md`, `backlog.md`) stop reporting their entire active-task roster as if introduced by the current edit. BLOCKED message rewritten to list only categories actually observed during iteration (was: consolidated `own / mixed / unattributed` lie). Defensive guard `[ "$block" -ne 1 ] → exit 2` codifies the wording↔exit-code invariant.

### What changed

- **MOD `code/datarim/scripts/pre-archive-check.sh`** (+69 / −24) — diff-only `found_ids` sourcing with untracked-file body fallback; separate `body_ids` signal for mine-by-elimination branch (TUNE-0060 contract preserved); `hit_own` / `hit_mixed` / `hit_unattributed` flags + hit-categorical BLOCKED message; precondition guard before BLOCKED block.
- **MOD `code/datarim/tests/pre-archive-check.bats`** (+111) — 6 regression fixtures (T42-T47): column-3 cleanliness on index files (T42), foreign-only column-3 (T43), mixed preserved (T44), exit-0 wording invariant (T45), BLOCKED hit-categorical wording (T46), untracked-file body fallback (T47). Full suite 47/47 green; shellcheck `-S warning` clean.

### Class A evolution (3 proposals, all applied this turn)

1. **NEW `code/datarim/skills/utilities/git-diff-parsing.md`** + **MOD `skills/utilities.md`** — canonical filter chain (`grep -E '^[+-]' | grep -vE '^(\+\+\+|---)'`) for parsing `git diff` output; covers markdown-bullet edge case, untracked-file fallback, hunk-context noise. Pattern surfaced 3 times in framework history (TUNE-0060 / 0068 / 0084) before being formalised.
2. **MOD `code/datarim/CLAUDE.md`** — new § Defensive Invariants section after § Security Mandate. Documents precondition-guard pattern for state↔wording invariants in shell scripts (e.g. `BLOCKED ↔ exit 1`). Founding incident: TUNE-0084 pre-fix BLOCKED + exit 0 simultaneously misled operators.
3. **MOD `code/datarim/skills/ai-quality.md`** — added separate-signals sub-rule under § DECOMPOSITION. When one variable answers two semantically distinct questions (e.g. display roster + body presence proxy), refactoring one role silently breaks the other. Founding incident: TUNE-0084 regression T26 — `found_ids` carried two roles, narrowing it to one broke mine-by-elimination.

### Bats verification after Class A apply

- **MOD `code/datarim/tests/utilities-decomposition.bats`** — T3 fragment count `13 → 14` to track the new `git-diff-parsing.md` fragment. (Same pattern as the prior `keyword-linter.md` incident referenced in `reflecting.md`.) Suite green for utilities-decomposition + pre-archive-check; remaining 2 failures (T26 check-drift INSTALL_SCOPES, T156 datarim-doctor.md description >155 chars) are pre-existing and unrelated to TUNE-0084.

### Lesson

Two-source diff-text composition (body ∪ raw diff) is one source too many. Body carries committed roster; raw diff carries hunk-context (which IS body adjacent to a hunk). Both pollute display while only the +/- lines are the actual edit. Single canonical source = `^[+-]` filtered diff. Untracked files (no HEAD blob) are the only legitimate body-fallback path.

---

## 2026-05-03 — TUNE-0083 — Runtime datarim-doctor.md sync + Runtime/Canonical Identity rubric

### Summary

Closed symmetric site/runtime drift on `datarim-doctor` skill: runtime `code/datarim/skills/datarim-doctor.md` (= `~/.claude/skills/datarim-doctor.md` via symlink-default install) was rewritten to v1.21.3 5-pass migration + Data-Loss Safety Contract, matching the site PHP page already updated in TUNE-0082. Class A #1 from reflection added a § Runtime / Canonical Identity rubric to `skills/datarim-system.md` documenting symlink-default inode identity and removing the copy-mode "sync runtime" reflex from AI-agent operational descriptions. Class A #2 (refine `pre-archive-check.sh` "mixed" classification heuristic) deferred to backlog as TUNE-0084 (P3 · L2).

### Why patch-level (no version bump this round)

Pure documentation parity fix (skill text → contract reality already shipped in v1.21.0/v1.21.3). No `scripts/datarim-doctor.sh` change, no contract change. The runtime skill was simply stale.

### What changed

- **MOD `code/datarim/skills/datarim-doctor.md`** (+69 / -41) — 5-pass algorithm (Pass 4 = backlog-archive migration; Pass 5 = post-fix re-scan), § Data-Loss Safety Contract (4 rails), `activeContext.md` Active-Tasks-only mirror, abolished `«Последние завершённые»` rolling section, CLI surface (`--no-prompt`, `--conflict-policy`, scope `backlog-archive`, env `DATARIM_DOCTOR_BACKUP_DIR`).
- **MOD `code/datarim/skills/datarim-system.md`** (+12) — new § Runtime / Canonical Identity rubric (above § Loading Order). Documents inode identity verification via `stat -f %i` (macOS) / `stat -c %i` (GNU); copy-mode detection via divergent inodes.

### Lesson

Copy-mode reflex from pre-v1.17 era persists in AI-agent operational descriptions even when the underlying install topology is symlink. Surfacing the rubric in the always-loaded `datarim-system.md` skill is the cheapest place to short-circuit the reflex.

---

## 2026-05-02 — TUNE-0080 — Pre-archive version-consistency check (v1.21.2)

### Summary

Class A — internal tooling. Implements the Class A A-1 proposal from TUNE-0079 reflection. New `scripts/version-consistency-check.sh` gate runs as `commands/dr-archive.md` Step 0.2 between clean-git check and reflect. When `VERSION` changed in HEAD->working-tree, the script greps `CLAUDE.md` and `README.md` for the old version string and blocks archive (exit 1) if any consumer is still stale. `--allow-version-lag` override available.

### Why patch (not minor)

Closes recurring drift class identified across multiple prior archives (CLAUDE.md was at 1.20.0 and README.md at 1.19.1 while VERSION was 1.21.0 — caught manually during TUNE-0079 archive). Pure tooling addition, no contract change. Bash 3.2 portable, shellcheck clean, 10 bats cases green.

### What changed

- **NEW `scripts/version-consistency-check.sh`** (~110 LOC). Reads `git show HEAD:VERSION` vs working `VERSION`. If changed, `grep -Frln "$old"` against `CLAUDE.md` + `README.md`. Initial-commit and `VERSION`-unchanged → exit 0 fast paths.
- **NEW `tests/version-consistency-check.bats`** — 10 cases: T1 unchanged / T2 clean bump / T3 lagging CLAUDE.md / T4 lagging README.md / T5 docs/ excluded by design / T6 `--allow-version-lag` override / T7 not-a-git-repo / T8 initial bootstrap / T9 whitespace tolerance / T10 no args.
- **MOD `commands/dr-archive.md`** — Step 0.2 documents the gate, scope rationale, override flag.
- **MOD `code/datarim/{VERSION, CLAUDE.md, README.md}`** — patch bump 1.21.1 → 1.21.2.

### Scope decision: `docs/` EXCLUDED

Initial design included `docs/` recursive in the scan scope. First live-smoke run on the framework repo (immediately after first bats green-bar) tripped on `docs/evolution-log.md` referencing v1.21.1 — the prior release entry. By design: evolution-log / release-notes / changelog are append-only historical ledgers that reference past versions, not current-state surfaces.

Including `docs/` would fire on every subsequent archive (every prior release entry would match the bumped-from string). Narrowed scope to `CLAUDE.md` (Version line) + `README.md` (badge) — exactly the recurring drift class from TUNE-0079 reflection.

### Lesson — dogfooding > synthetic fixtures

TDD red→green discipline caught the implementation but not the scope error. All 10 synthetic bats cases passed with `docs/` in scope (synthetic repos started clean, so the rule «docs cite old → fail» seemed correct in isolation). The live repo encodes years of release history that fixtures cannot reproduce.

**New rule:** when a gate is built against a recurring incident class, smoke-test on the live repo before declaring done. Synthetic fixtures verify mechanics; live state validates scope.

---

## 2026-04-30 — TUNE-0079 — History-agnostic cleanup complete + CI strict mode (v1.21.1)

### Summary

Class A — internal tooling. Follow-up to TUNE-0078. Cleaned all pre-existing task-ID references from runtime scopes (`skills/`, `commands/`) per the heuristic in TUNE-0078 plan § 4.3: pure provenance parentheticals deleted, load-bearing rationale anonymized, counter-example incidents kept with neutral phrasing. Final tally: 64 hits in `commands/` (9 files) + ~316 hits in `skills/` (38 files) eliminated across 4 sessions of per-file `Edit` (bulk regex confirmed unsafe — fence-aware editing required). CI `task-id-gate` job switched from `--diff-only` transitional mode to strict full-tree. Bats suite extended T11–T14: regression invariant — each runtime scope stays gate-clean. VERSION → 1.21.1.

### What changed

- **MOD `skills/`** — 27 files, ~316 hits cleaned. All gate-clean.
- **MOD `commands/`** — 9 files, 64 hits cleaned (sessions 1–2). All gate-clean.
- **MOD 2× `tests/*.bats`** — 2 tests that asserted task-ID presence updated to history-agnostic assertions (version tag + contract clause).
- **MOD `tests/task-id-gate.bats`** — added T11–T14 regression invariants. 14/14 green.
- **MOD `.github/workflows/security.yml`** — `task-id-gate` job: full-tree mode. Removed `fetch-depth: 50`. Removed transitional comment.
- **MOD `code/datarim/{CLAUDE.md,VERSION,README.md}`** — version 1.21.1.

### Why patch (not minor)

Pure cleanup, no contract change. Gate behavior identical for new code; only the transitional `--diff-only` shim removed.

### Lesson

Bulk regex (Python `re.sub` over markdown) is NOT fence-aware. Session 3 attempted bulk patterns to accelerate cleanup; one match landed inside a code-fence Examples block and corrupted teaching content. Reverted manually. Per-file `Edit` with explicit fence inspection was the only safe path. ~30 sessions of per-file work amortized over the framework's lifetime; bulk-tool acceleration is forbidden for `skills/`/`commands/`/`agents/`/`templates/` markdown going forward — write a fence-aware AST walker first if acceleration is needed.

---

## 2026-04-30 — TUNE-0078 — Rules history-agnostic gate (v1.21.0)

### Summary

Class A — internal tooling. New `scripts/task-id-gate.sh` mirrors the stack-agnostic-gate sibling but enforces a single regex `\b[A-Z]{2,10}-[0-9]{4}\b` over runtime markdown (skills/agents/commands/templates). New contract document `skills/evolution/history-agnostic-gate.md`. New bats suite `tests/task-id-gate.bats` (10 cases including `--diff-only` parity). Critical Rules in `code/datarim/CLAUDE.md` extended with rule 8 («Rules are stack- AND history-agnostic»). CI integration as 14th job in `.github/workflows/security.yml`, running in `--diff-only` mode against `merge-base HEAD origin/main` so only fresh leakage in the change-set fails CI — pre-existing baseline references (~339 hits in 57 files) tracked as follow-up cleanup pass TUNE-0079. VERSION → 1.21.0.

### Source rationale

Datarim runtime rules are read by AI agents that have no access to the historical context behind each task-ID reference. A rule that says «Per TUNE-0033 …» forces the agent to either treat the citation as opaque noise or attempt to locate the cited task in archive — wasted tokens for a reference the rule itself does not depend on. Worse, embedded task-IDs leak into AI outputs addressed to end users. The sibling stack-agnostic-gate established the enforcement pattern (detection → escape-hatch → CI integration); the history-agnostic case is structurally identical.

### What changed

- **NEW `scripts/task-id-gate.sh`** — bash 3.2 portable, single-regex denylist, `--whitelist` and `--diff-only` flags, exit codes 0/1/2 per contract. Self-exemption for the gate's own contract document.
- **NEW `skills/evolution/history-agnostic-gate.md`** — runtime contract document (Trigger, Scope, Denylist, Whitelist, Escape Hatch, markers-must-be-on-separate-lines pitfall, Invocation, Exit codes, Why this exists, Out of scope).
- **NEW `tests/task-id-gate.bats`** + `tests/fixtures/task-id-gate/` (5 fixtures) — 10 test cases, all green locally.
- **MOD `.github/workflows/security.yml`** — 14th job `task-id-gate`. Hard-fail on any new leakage in changed files; bats suite runs in same job. `fetch-depth: 50` for diff-base resolution.
- **MOD `code/datarim/CLAUDE.md`** — Critical Rules § rule 8.
- **MOD `code/datarim/VERSION`** — 1.20.0 → 1.21.0.
- **Cleanup pass partial:** `agents/developer.md` (2 hits) and `templates/` (21 hits across 9 files) cleaned — load-bearing rationale rephrased to neutral lessons; legitimate template placeholder (e.g. `INFRA-0099` in `backlog-template.md`) wrapped in `<!-- gate:history-allowed -->` escape fence. `skills/` (252 hits across 38 files) and `commands/` (64 hits across 9 files) deferred to TUNE-0079.

### Migration

Symlink-mode users: gate + skill + bats auto-available via the `scripts/` and `tests/` install scopes. Copy-mode users: `./update.sh` pulls the new files. No operator action required for the runtime — CI gate is the enforcement point.

### Why `--diff-only` instead of strict mode at v1.21.0

The full cleanup pass (~339 hits, ~57 files) is mechanically tractable but requires per-line judgement (delete pure provenance vs. rephrase load-bearing rationale vs. migrate counter-example incident to evolution-log topic heading). Shipping the gate with `--diff-only` lets the enforcement land immediately while the cleanup proceeds incrementally — the sibling stack-agnostic-gate handled identical baseline carry-forward via the same flag. Switch to full-tree mode after TUNE-0079 lands.

### Follow-up

- **TUNE-0079** (P2, L2, pending) — Complete the cleanup pass over `skills/` and `commands/` per the cleanup heuristic in `datarim/plans/TUNE-0078-plan.md` § 4.3. Switch CI gate to full-tree mode at the same time. Estimated ~3-4h focused work.

---

## 2026-04-30 — TUNE-0077 — Datarim Doctor data-loss safety gate + scripts/tests install scopes (v1.20.0)

### Summary

Class A — internal tooling. `scripts/datarim-doctor.sh` gains a defence-in-depth safety contract for `--fix` mode: pre-write tarball backup (mode 0600), post-write `emitted_count >= parsed_count` invariant with auto-restore on violation, backup path surfaced in success summary. `install.sh` `INSTALL_SCOPES` extended with `scripts` and `tests` — both directories now whole-dir-symlinked into `~/.claude/` under default symlink mode (uniform with existing `agents`/`skills`/`commands`/`templates` pattern). Eliminates drift between canonical Datarim repo and `~/.claude/` runtime: `~/.claude/scripts/datarim-doctor.sh` is the canonical file by inode — divergence impossible. VERSION → 1.20.0.

### Source incident

External Datarim copy on `aether/local-env` (2026-04-30 16:31 UTC): a 730-LoC rogue `datarim-doctor.sh` v2 (developed in another project's worktree, never merged to canonical Arcanada Datarim repo) was placed directly into `~/.claude/scripts/datarim-doctor.sh`. Its `--fix` invocation destroyed 30 task entries from `tasks.md`/`backlog.md` indexes, collided 5 followup-ID description files, and reported «All fixes applied successfully». Recovery from external `/tmp/datarim-backup-*.tgz` tarball.

Two structural defects enabled the incident:

1. **Drift-by-design.** `~/.claude/scripts/` was outside `INSTALL_SCOPES`. Canonical script (368 LoC) and runtime copy (730 LoC) had no install-time link — drift undetectable until live `--fix`.
2. **No data-loss gate.** Doctor `--fix` had no pre-write backup, no post-write invariant. A faulty Pass 2 silently replaced indexes with empty content.

### What changed

- **MOD `scripts/datarim-doctor.sh`:**
  - NEW pre-fix tarball backup at `${DATARIM_DOCTOR_BACKUP_DIR:-/tmp}/datarim-backup-{TS}.tgz`, mode 0600 via `umask 077`.
  - NEW `PARSED_COUNT` capture (pre-fix `### TASK-ID:` block count across `tasks.md`+`backlog.md`).
  - NEW post-fix `EMITTED_COUNT` re-scan + invariant `emitted >= parsed` — violation triggers `restore_backup_and_die()` (rm-rf + tar -xzf, exit 2).
  - Success summary logs `Backup: $BACKUP_TARBALL` and counters.
- **MOD `install.sh`:**
  - `INSTALL_SCOPES` extended `(agents skills commands templates)` → `(agents skills commands templates scripts tests)`.
  - `LOCAL_SCOPES` unchanged (scripts/tests are framework-internal, not user-extensible — local overlay applies only to user-facing scopes).
  - Existing `link_scope_tree` handles new scopes uniformly — no special-case code path needed.
  - Header comment updated: scripts/tests are «installed scopes» as of v1.20.0.
- **MOD `tests/datarim-doctor.bats`:** +6 regression tests T16–T21 covering backup creation, mode 0600, post-fix invariant on synthetic 3-block fixture, printf hardening (no `printf "$` patterns), body-with-leading-dash safety, summary-prints-backup-path.
- **MOD `VERSION`:** `1.19.1` → `1.20.0` (minor — additive install scope).
- **MOD `CLAUDE.md`:** version banner bump.

### Key design decisions

1. **Defence in depth (3 layers).** Pre-write tarball + post-write invariant + auto-restore. No single bug can cause data loss; even a faulty Pass 2 emit gets caught.
2. **Whole-directory symlink (uniform with skills/agents/commands/templates).** Initial implementation tried file-level `RUNTIME_SCRIPTS` allow-list — rejected at QA review as deviation from established pattern. With dir-symlink, `~/.claude/scripts/` and `~/.claude/tests/` ARE the canonical directories by inode — drift impossible by construction. Bonus: `lib/canonicalise.sh` and bats fixtures resolve naturally via standard SCRIPT_DIR / BATS_TEST_DIRNAME — no symlink-following helpers needed.
3. **Quarantine over edit.** Rogue `~/.claude/scripts/datarim-doctor.sh` (730 LoC) was deleted, not patched. Backup at `/tmp/rogue-doctor-v2-backup.sh` for forensics. Canonical 368 LoC stays the single source of truth — porting v2 features back is a separate decision deferred to TUNE-0072+ backlog.
4. **`scripts/tests` not in LOCAL_SCOPES.** User overlay (`~/.claude/local/`) makes sense for skills/agents/commands/templates (user-extensible). Scripts and tests are framework-internal — adding `local/scripts/` would only add an attack surface for shadowing critical safety logic with unreviewed user code.

### Validation

- `bats tests/datarim-doctor.bats` — 21/21 pass (15 pre-existing + 6 new).
- `shellcheck -S warning scripts/datarim-doctor.sh install.sh` — clean.
- Live smoke: `~/.claude/scripts/datarim-doctor.sh --root=/Users/ug/arcanada/datarim` → exit 0 «OK: datarim/ structure compliant».
- `readlink -f ~/.claude/scripts/datarim-doctor.sh` → `Projects/Datarim/code/datarim/scripts/datarim-doctor.sh` ✓.
- `./install.sh` idempotent: rogue real-file moved to `~/.claude/backups/runtime-rogue-{TS}/`, replaced by symlink.

### Follow-ups

- **TUNE-0072** (backlog) — `--quiet` exit-code parity. Independent issue.
- Consider adding `tests/install.bats` scenarios for RUNTIME_SCRIPTS (rogue replacement, idempotent re-link). Informal follow-up.
- Consider `skills/datarim-doctor.md` § Safety Contract subsection documenting the invariant for downstream callers. Informal follow-up.

---

## 2026-04-30 — TUNE-0069 — `commands/dr-plan.md` CI delta-vs-baseline framing for V-checklist

### Summary

Class A — internal tooling. `commands/dr-plan.md` Step 11.5 codifies CI delta-vs-baseline framing for V-checklist generation: when target branch's last CI run is itself failing (WIP branches, work-branches with partial fixes, dep-bump branches against red baseline), V-CI MUST be drafted as «no NEW failures vs baseline» rather than strict «all green». Strict-green gate appropriate only when baseline run is itself green. Validation Checklist updated with corresponding entry. Closes TUNE-0067 reflection Proposal 2 (N=2 spawn-trigger met via TUNE-0055 + TUNE-0067).

### What changed

- **MOD `commands/dr-plan.md`** — NEW Step 11.5 «CI Verification Gate — Delta-vs-Baseline Framing» (~30 lines), inserted between Live Audit Checkpoint (11) and Class B Public Surface Scan (12). Includes baseline-probe rationale, delta-gate semantics, stack-agnostic recipe wrapped in `<!-- gate:example-only -->` (GitHub Actions / GitLab CI variants), inline-cite requirement for baseline run id and failed-job list, TUNE-0055 + TUNE-0067 source-incident citation.
- **MOD `commands/dr-plan.md` Transition Checkpoint** — added baseline-probe checklist entry above Live Audit row.

### Key design decisions

1. **Step 11.5 (not 12) to avoid renumbering.** Existing Step 6.5 precedent for sub-numbered steps; downstream Steps 12 (Class B Public Surface Scan) and 13 (Output Summary) keep their numbers — no cross-document refactor needed.
2. **`gh` CLI recipe wrapped in example-only fence.** Stack-agnostic invariant requires `gh`/`glab` examples to be illustrative, not prescriptive; pattern (baseline probe + delta compare) is the contract, specific tool is operator's choice.
3. **Inline baseline-citation requirement.** Plan MUST cite baseline run id and failed-job list so `/dr-qa` and `/dr-archive` can verify the delta gate without re-querying `gh` (also makes the gate stable against post-hoc CI runs that close or reopen flaky failures).
4. **Class A (not B).** No operator-facing contract change; framework runtime invariant («mechanical changes can't regress unrelated red jobs») stays the same — Step 11.5 just makes the V-checklist author-aware of it. No VERSION bump, no datarim.club deploy.

### Recurrence-prevention pattern

«Memory Rule → Executable Gate at Apply Step» — 9th iteration:
TUNE-0044 → TUNE-0056 → TUNE-0058 → TUNE-0059 → TUNE-0060 → TUNE-0061 → TUNE-0054 → TUNE-0068 → **TUNE-0069**.

Source incidents (N=2): TUNE-0055 (`actions/checkout` v4→v5, baseline 4 red jobs, V-4 reformulation post-hoc) + TUNE-0067 (`actions/setup-python` v5→v6, baseline 5 red jobs, V-4 reformulation post-hoc). Both archives explicitly held this proposal with N=2 spawn-trigger met; TUNE-0069 is the deferred application.

---

## 2026-04-29 — TUNE-0054 — Markdown reference integrity linter (`scripts/check-doc-refs.sh`) + `.docrefignore` baseline

### Summary

Class A — internal tooling. New invocation-only linter `scripts/check-doc-refs.sh` recursively scans `code/datarim/{CLAUDE.md,skills,agents,commands,templates,docs}/**/*.md` for broken markdown links `[text](path.md)` and bare-path mentions `(skills|agents|commands|templates|docs)/.../*.md`. Each reference resolves relative to dirname (link form) or ROOT (bare form), is canonicalised lexically, then existence-checked. Whitelist precedence: inline `<!-- doc-ref:allow path=... -->` on the same line > `.docrefignore` glob > orphan reported. Closes the recurrence loop surfaced in TUNE-0050 reflection (N=2 phantom paths shipped through `/dr-archive` undetected).

### What changed

- **NEW `scripts/check-doc-refs.sh`** (~170 LoC bash, mirrors `pre-archive-check.sh` style). Strict-mode (`set -u`), AWK pre-processor strips fenced code blocks (``` toggle) AND inline backtick spans before extraction. Lexical path canonicalisation (`canonicalise_path()`) collapses `./` and `../` without I/O so parent directories need not exist — required for path-traversal detection. External links (`http://`, `https://`, `mailto:`, `ftp://`, `#anchor-only`) skipped.
- **NEW `tests/check-doc-refs.bats`** — 10 fixtures: T1 clean tree / T2 planted orphan link / T3 `.docrefignore` glob / T4 inline allow marker / T5 bare-path orphan / T6 nested relative resolves / T7 path-traversal exit 2 / T8 externals skipped / T9 fenced blocks ignored / T10 missing root exit 2. All PASS.
- **NEW `.docrefignore`** at repo root — accepted-debt baseline (gitignore-style globs). Initial snapshot: 1 entry (`templates/security-workflow.yml` referenced by `skills/security-baseline.md:401` — TUNE-0045 P2 phantom; cleanup deferred to follow-up TUNE-0064).
- **NEW `documentation/INSIGHTS-TUNE-0054.md`** — orphan inventory + 4 open-question resolutions + 3 follow-ups proposed (TUNE-0063/0064/0065).
- **MOD `commands/dr-archive.md` Step 0.5(e)** — appended advisory line pointing to `scripts/check-doc-refs.sh --root code/datarim/` (non-blocking, parallel to `stack-agnostic-gate.sh --diff-only`).
- **MOD `.github/workflows/security.yml`** — `doc-refs` job parallel to existing 12 (bats fixture suite + linter against repo HEAD; expects exit 0 with baseline applied).

### Key design decisions

1. **Backtick code-span stripping for bare-path extraction.** Mid-implementation self-dogfood reported 13 orphans; 12 of them were code-span mentions like `` `datarim/docs/activity-log.md` `` in narrative text. Fix: AWK pre-processor strips backticks before BOTH markdown-link AND bare-path extraction.
2. **Lexical (no-I/O) path canonicalisation.** `cd $(dirname x) && pwd -P` fails when traversal exits the filesystem tree, falling back to literal string which then false-matches `ROOT_ABS/*` glob. Pure-bash `canonicalise_path()` resolves purely-string, traversal guard reliable.
3. **`LC_ALL=C` for AWK.** macOS BSD awk emits multibyte warnings on Cyrillic content; byte-mode silences without affecting results (ASCII patterns only).
4. **Class A (not B).** No operator-facing contract change; advisory only. Promotion path = TUNE-0065 follow-up if N=2 advisory-bypass incidents.

### Recurrence-prevention pattern

«Memory Rule → Executable Gate at Apply Step» — 7th iteration:
TUNE-0044 → TUNE-0056 → TUNE-0058 → TUNE-0059 → TUNE-0060 → TUNE-0061 → **TUNE-0054**.

---

## 2026-04-29 — TUNE-0061 — `pre-archive-check.sh` env-var whitelist extension (`DATARIM_PRE_ARCHIVE_WHITELIST`)

### Summary

`scripts/pre-archive-check.sh` shared mode now honours an opt-in env-var `DATARIM_PRE_ARCHIVE_WHITELIST` (colon-separated basenames, PATH-style) that extends the hardcoded TUNE-0059 whitelist with project-specific version-bump basenames at consumer level, without modifying the framework. Closes the gap surfaced in TUNE-0060 self-dogfood: `Projects/Websites/datarim.club/config.php` is a legitimate Datarim public-surface version-bump file but its basename is project-specific and does not belong in the canonical hardcoded list shipped to all consumers.

### What changed

- **`scripts/pre-archive-check.sh`** (+15 LoC): after the `WHITELIST_BASENAMES` defaults block, parse `${DATARIM_PRE_ARCHIVE_WHITELIST:-}` via `IFS=':' read -ra` (skip blanks, reject path components — basename match only), append entries to `WHITELIST_BASENAMES`. `is_whitelisted_path()` unchanged; `--no-whitelist` continues to short-circuit the entire whitelist check (overrides both hardcoded list AND env-var entries).
- **`tests/pre-archive-check.bats`** (+30 LoC): T29 (env-var single basename `config.php` → whitelisted, exit 0), T30 (colon-separated `foo:bar:config.php` → all entries whitelisted, AC-3), T31 (`--no-whitelist` overrides env-var → unattributed, exit 1). bats 28 → 31 PASS.
- **`commands/dr-archive.md`** Step 0.1.2 footnote on the `whitelisted` row documents the env-var extension and its precedence vs `--no-whitelist`.

### Why

TUNE-0060 archive (the previous iteration) self-dogfooded the new `mine-by-elimination` klass and surfaced one residual gap: `Projects/Websites/datarim.club/config.php` was correctly identified as a legitimate version-bump file by Pavel during the archive but the gate classified it `unattributed` (basename outside hardcoded list). The choice was either pollute the canonical list with `config.php` (breaks framework neutrality — `config.php` is generic enough that a non-Datarim consumer might NOT want it whitelisted) or add an opt-in extension mechanism. Spawn-trigger N=2 reached: TUNE-0059 (hardcoded VERSION/CHANGELOG/etc.) was the first instance; TUNE-0060 self-dogfood surfaced the second. Pattern «Memory Rule → Executable Gate at Apply Step» — sixth iteration (TUNE-0044/0056/0058/0059/0060/0061).

### Class

Class A (additive runtime behaviour, env-var opt-in, no contract break). VERSION 1.18.3 → 1.18.4 (patch additive). Public Surface deployed: `Projects/Websites/datarim.club/config.php` 1.18.3 → 1.18.4 + `pages/changelog.php` v1.18.4 release entry. Backwards-compat preserved by design: env-var unset → behaviour identical to TUNE-0060 (T1-T28 fixtures all PASS). `--no-whitelist` continues to override (T31 verifies). Path-traversal guard rejects `/`-containing entries with exit 2.

### Self-dogfood

`DATARIM_PRE_ARCHIVE_WHITELIST=config.php ./scripts/pre-archive-check.sh --task-id TUNE-0061 --shared ~/arcanada` from framework repo classifies the workspace's modified `Projects/Websites/datarim.club/config.php` as `whitelisted` (was `unattributed` in the TUNE-0060 archive run). Bats fixtures T29/T30/T31 cover the same recipe in isolation.

---

## 2026-04-29 — TUNE-0060 — `pre-archive-check.sh` `mine-by-elimination` klass

### Summary

`scripts/pre-archive-check.sh` shared mode got a 6-th hunk classification, `mine-by-elimination`. When `--task-id <ID>` is set, the file is modified (has actual diff lines), AND those diff lines (additions/removals) contain ZERO task IDs while the committed body carries foreign historical IDs, the gate attributes the edit to the current task and exits 0. Closes the false-`foreign` misclassification of doc edits like `CLAUDE.md`, `README.md`, and architectural docs where the body references many historical tasks but the current edit (e.g., a version-line bump) introduces none.

### What changed

- **`scripts/pre-archive-check.sh`** (+19 LoC): per-file capture of `diff_changes` and `diff_changes_cached` separately from full `diff_text`; `diff_line_ids` extraction from added/removed lines only (`grep -E '^[+-][^+-]'`); new branch in classification cascade between the `mixed` arm and the `foreign` arm that fires when `--task-id` set + diff is non-empty + `diff_line_ids` empty. Untracked files (no diff at all) skip the branch and fall through to `foreign` per safety guard.
- **`tests/pre-archive-check.bats`** (+30 LoC): T26 (body has foreign IDs + diff lines clean → mine-by-elimination + exit 0), T27 (diff lines contain TASK_ID → mixed, NOT mine-by-elimination), T28 (diff lines contain only foreign IDs → foreign, NOT mine-by-elimination). bats 25 → 28 PASS.
- **`commands/dr-archive.md`** Step 0.1.2: 6-th classification row (`mine-by-elimination`) added to the contract paragraph with the safety-guard note for untracked files.

### Why

TUNE-0059 archive surfaced the residual false-positive after the whitelist landed. `code/datarim/CLAUDE.md` and `code/datarim/README.md` (committed body has many historical task IDs from prior reflections + features) version-bumped 1.18.0 → 1.18.2 in TUNE-0059 archive — the diff lines were just `-1.18.0` / `+1.18.2`, no IDs introduced by the current session. The `whitelisted` klass did not cover them (basename ≠ version-bump file), and `found_ids` from the body had IDs but none matched `--task-id TUNE-0059`, so the gate said `foreign`. The operator manually staged via `git add` to work around — the same toll TUNE-0058 closed for baseline matches in `stack-agnostic-gate.sh`. Spawn-trigger N=2 reached by Pavel approval (TUNE-0059 self = N=1, CLAUDE.md/README.md observed misclassification = second class instance, escalated by operator).

### Class

Class B (operating-model contract change — extends what counts as `attributed`). VERSION 1.18.2 → 1.18.3 (patch additive). Public Surface deployed: `Projects/Websites/datarim.club/config.php` 1.18.2 → 1.18.3 + `pages/changelog.php` v1.18.3 release entry. Backwards-compat preserved: T1-T25 fixtures all PASS; safety guard ensures untracked files are NOT misclassified.

### Verification

- `bats tests/pre-archive-check.bats` → 28/28 PASS.
- `bats tests/pre-archive-check.bats tests/stack-agnostic-gate.bats` → 38/38 PASS (full repo regression).
- `shellcheck -S warning scripts/pre-archive-check.sh` → clean.
- Pattern «Memory Rule → Executable Gate at Apply Step» — fifth iteration (TUNE-0044/0056/0058/0059/**0060**).

---

## 2026-04-29 — TUNE-0059 — `pre-archive-check.sh` whitelist for version-bump basenames

### Summary

`scripts/pre-archive-check.sh` shared mode got a 5-th hunk classification, `whitelisted`. When `--task-id <ID>` is set and a modified file's basename matches a hardcoded list of version-bump files (`VERSION`, `CHANGELOG.md`, `package.json`, `Cargo.toml`, `pyproject.toml`, `.gitignore`), the gate accepts it without a task-ID inside the diff. The operator-supplied `--task-id` is the attribution. Pass `--no-whitelist` to restore strict default-deny.

### What changed

- **`scripts/pre-archive-check.sh`** (+33/-2 LoC): `WHITELIST_BASENAMES` array (6 entries) with founding-incident comment; `is_whitelisted_path()` helper (basename exact-match, no regex on user input); `NO_WHITELIST=0` global; `--no-whitelist` flag in arg parser; classification branch wraps the empty-`found_ids` else-branch with whitelist check; usage text extended with whitelist paragraph.
- **`tests/pre-archive-check.bats`** (+30 LoC): T23 (whitelisted basename + `--task-id` → exit 0, klass=whitelisted), T24 (`--no-whitelist` escape restores `unattributed` → exit 1), T25 (non-whitelisted basename without task-ID → default-deny preserved → exit 1). bats 22 → 25 PASS.
- **`commands/dr-archive.md`** Step 0.1.2: 5-th classification row (`whitelisted`) added to the contract paragraph with the basename list and `--no-whitelist` escape note.

### Why

TUNE-0056 self-dogfood surfaced the false positive: `VERSION` (single line `1.18.1`) physically cannot carry a task ID and was classified as `unattributed`, blocking a legitimate release commit. Pavel's `/dr-archive {TASK-ID}` IS the disposition, but the gate had no machine-readable way to see it. Spawn-trigger N=2 was reached when the same toll resurfaced in the TUNE-0059 self-dogfood (catch-up VERSION drift from TUNE-0056). Whitelist closes the gap without weakening default-deny: it activates only with `--task-id` (operator disposition) and prints the bypass on stdout for visibility.

### Class

Class B (operating-model contract change — extends what counts as `attributed`). VERSION 1.18.1 → 1.18.2 (patch additive). Public Surface deployed: `Projects/Websites/datarim.club/config.php` 1.18.1 → 1.18.2 + `pages/changelog.php` v1.18.2 release entry. Backwards-compat preserved: T1-T22 fixtures all PASS, default-deny still default for all non-whitelisted unattributed hunks.

### Verification

- `bats tests/pre-archive-check.bats` → 25/25 PASS.
- `shellcheck -S warning scripts/pre-archive-check.sh` → clean.
- Self-dogfood: `./scripts/pre-archive-check.sh --task-id TUNE-0059 .` from framework repo → `VERSION` line shows `whitelisted` in stdout.

---

## 2026-04-29 — TUNE-0058 — `stack-agnostic-gate.sh --diff-only [<base>]` flag

### Summary

`scripts/stack-agnostic-gate.sh` got a new `--diff-only [<base>]` mode that scans only lines added by `git diff <base> -- <file>` (default base `HEAD`) instead of the full file. Pre-existing baseline matches in shared-history files (`docs/evolution-log.md`, README, changelog and similar) are ignored, removing the operator-toll of running `git diff '^+'` manually at every archive to prove the current task did not introduce a fresh stack-specific term. Default full-file scan unchanged.

### What changed

- **`scripts/stack-agnostic-gate.sh`** (+30/-7 LoC): `--diff-only` flag parsing with optional positional base ref (lookahead disambiguation: consumed only if next arg does not exist as a filesystem path); new `produce_scan_stream` helper that emits either the full file or the added-lines stream from `git diff`; `strip_example_blocks` refactored to read from stdin (decoupled from file argument) so both modes share a single downstream pipeline; single-file invocation on untracked or non-git target → exit 2 with explanatory message; directory-scan mode silently skips untracked files; `--help` line-range bumped (`2,30p` → `2,40p`) to cover the new Inputs paragraph.
- **`tests/stack-agnostic-gate.bats`** (+85 LoC): 4 new fixture-based tests T7-T10 with `setup_diff_repo` / `teardown_diff_repo` helpers that build a throwaway `mktemp -d` git repo with a baseline file containing pre-existing stack-specific terms. T7 (no edits → diff-only PASS), T8 (added stack-specific line → diff-only FAIL), T9 (mixed baseline + clean additions → diff-only PASS), T10 (non-git path → exit 2). bats 6 → 10 PASS.
- **`commands/dr-archive.md`** Step 0.5(e): one extra sentence recommending `--diff-only` invocation for shared-history files when applying Class A through the stack-agnostic gate, with the rationale and source citation.

### Why

Recurring rough edge surfaced at TUNE-0044 + TUNE-0056 self-dogfood: `docs/evolution-log.md` already carried 3 pre-existing baseline matches from older entries; the gate failed every archive that touched the file even when the current task added zero stack terms. Operator had to verify by hand via `git diff '^+'` to prove no fresh leak — same recipe each time, no automation. `--diff-only` codifies that recipe inside the gate itself; consumers ask once and the gate scopes itself to the current task's contribution.

### Class

Class A (additive, internal behaviour, no public surface). No VERSION bump expected. No datarim.club deploy. Backwards-compat preserved: default full-file scan untouched, T1-T6 legacy fixtures all PASS, whitelist + example-only fence semantics unchanged.

### Verification

- `bats tests/stack-agnostic-gate.bats tests/pre-archive-check.bats` → 32/32 PASS.
- `shellcheck -S warning scripts/stack-agnostic-gate.sh` → clean.
- Self-dogfood: `./scripts/stack-agnostic-gate.sh docs/evolution-log.md` → `FAIL: 3 matches`; `./scripts/stack-agnostic-gate.sh --diff-only docs/evolution-log.md` → `PASS: clean`.
- Stack-agnostic gate self-passes on the modified script (bash + grep, zero stack terms by construction).

### Held proposals (none applied this archive)

- **Proposal 1 (Class A, hold).** `--help` sentinel terminator pattern (e.g. `# --- end help ---`) to replace `sed -n '<start>,<end>p'` magic numbers in shipped scripts. Spawn-trigger N=2: TUNE-0058 + any future flag addition that requires another bump.
- **Proposal 2 (Class B, hold).** `--diff-classify` mode for `pre-archive-check.sh` that classifies hunks by task IDs found inside the current diff text rather than commit history. Reduces over-broad "mixed" classification on shared-history files (`commands/dr-archive.md`, gate script, bats files) where commit history accumulates many task IDs but the current diff is single-task. Spawn-trigger N=2: TUNE-0056 + TUNE-0058.

### Source incidents

- TUNE-0044 archive (2026-04-29) — first observed `docs/evolution-log.md` baseline match leaking through.
- TUNE-0056 archive (2026-04-29) — same operator-toll repeated; held as Class A Proposal 1.

---

## 2026-04-29 — TUNE-0056 — Class B apply (conditional-shared classification via marker file, v1.18.1)

### Summary

Self-dogfood of TUNE-0044 archive showed framework repo `Arcanada-one/datarim` itself carried foreign DEV-1210/DEV-1212 hunks from parallel agent sessions but was single-agent-classified — `pre-archive-check.sh` without explicit `--shared` flag treated framework repo as project-strict. Closing the gap with a portable marker file `.datarim-shared` at repo root. Presence + `--task-id` flag → auto-route to shared-mode classification, no explicit `--shared` argument needed.

### What changed

- **`scripts/pre-archive-check.sh`** — added 8-line auto-detect block after flag parsing: when `--task-id` is given without `--shared` and the next positional repo has a `.datarim-shared` marker file, route to shared mode automatically. Outer condition simplified from `[ -n "$TASK_ID" ] || [ -n "$SHARED_REPO" ]` to `[ -n "$SHARED_REPO" ]` so `--task-id` alone (without marker on positional) falls through to legacy strict mode.
- **`tests/pre-archive-check.bats`** — +3 fixtures covering conditional-shared (marker + foreign hunks → exit 0; marker absent + dirty → legacy STOP; marker + own hunks → exit 1 own classification). bats 19 → 22 PASS.
- **`commands/dr-archive.md`** Step 0.1.1 — classification table extended with `Conditional-shared` row (marker + `--task-id` auto-detect). Step 0.1.2 invocation form expanded with auto-detect example. Step 0.1.5 narrative clarified (project = no marker).
- **`.datarim-shared`** — new marker file at framework repo root with explanatory comment.
- **`VERSION`** — `1.18.0` → `1.18.1` (additive, backwards-compatible).

### Why

- TUNE-0044 founding rule (multi-agent shared semantics) required explicit `--shared <path>` flag for every invocation. Self-dogfood revealed this loses where it's most needed: framework repo itself, where AI agents most often forget the flag because repo classification looks like a project (has its own `.git`, builds, ships releases).
- Marker file is opt-in, machine-readable, portable across forks/mirrors (origin URL match was rejected — fragile). Backwards-compat preserved: project repos without marker keep TUNE-0003 strict legacy behaviour.

### Class

- **Class B** (operating-model extension) — adds new classification path; `commands/dr-archive.md` contract widens. Held as TUNE-0056 candidate at TUNE-0044 archive (Proposal 1, evolution-proposals held). Now applied with full Public Surface scan: changelog v1.18.1 entry, Step 0.1.1 table updated, evolution-log entry (this).

### Verification

- 22/22 bats PASS (`tests/pre-archive-check.bats`).
- shellcheck `-S warning` clean on `scripts/pre-archive-check.sh`.
- stack-agnostic-gate PASS on touched files.
- Self-dogfood: this archive cycle uses `pre-archive-check.sh --task-id TUNE-0056 .` from `code/datarim/` — auto-detect marker, foreign hunks isolated, archive proceeds without `--shared` flag.

### Founding incident

- TUNE-0044 self-dogfood (2026-04-29): framework repo had DEV-1210/DEV-1212 foreign hunks in working tree during archive, single-agent-classified by default, manual `--shared` flag was the only escape hatch.

---

## 2026-04-29 — TUNE-0044 — Class B apply (operating-model contract change, v1.18.0)

### Summary

`/dr-archive` Step 0.1 promoted from binary clean/dirty semantics to **task-ID-aware** classification for shared workspace repositories. Founding incidents: VERD-0026 (2026-04-27), DISK-0002, LTM-0017 — three archives blocked or delayed by foreign-task hunks from parallel agent sessions in `~/arcanada/.git`. Project-level rule landed in `~/arcanada/CLAUDE.md` § Multi-Agent Workspace Discipline; TUNE-0044 promotes it to framework runtime so all consumers inherit the semantics.

### What changed

- **`commands/dr-archive.md`** Step 0.1 rewritten with sub-steps 0.1.1–0.1.5: repo classification (workspace vs project), shared-mode check via extended `pre-archive-check.sh`, patch-staging recipe (interactive `git add -p` + non-interactive blob-swap fallback), retry-tolerant pre-commit re-verify, preserved TUNE-0032/0033 staged-diff audit, legacy single-agent project check.
- **`scripts/pre-archive-check.sh`** extended with `--task-id <ID> --shared <repo>` flags. Classifies each modified file's hunks as `own` / `foreign` / `mixed` / `unattributed`. Exit 0 on clean / foreign-only; exit 1 on own / mixed / unattributed; exit 2 on usage error. Strict regex validation `^[A-Z]+-[0-9]{4}$`. Legacy mode unchanged (TUNE-0003 contract preserved).
- **`tests/pre-archive-check.bats`** extended with 7 new test cases (foreign-only, own, mixed, unattributed, invalid task-id, missing --shared, legacy regression). 12 → 19 tests, all PASS.
- **`CLAUDE.md`** § Workspace Discipline (multi-agent) added between Critical Rules and Security Mandate, summarising Step 0.1 contract for AI agents loading the framework template.
- **`~/arcanada/CLAUDE.md`** rule 8 extended with reverse cross-cite to `commands/dr-archive.md` Step 0.1.3 (canonical recipe location).

### Why

Datarim's framework runtime had a single-agent assumption: any uncommitted change in workspace repos blocks `/dr-archive`. In multi-agent environments (Arcanada workspace runs 5–10 parallel sessions touching the same `datarim/{tasks,backlog,progress,activeContext}.md`), this triggered false-positive STOPs at every archive. The recipe to handle it lived only in project-level `~/arcanada/CLAUDE.md` rule 8 (DISK-0002 origin). Class B promotion: foreign hunks become a non-blocker; own forgotten hunks remain a blocker; default-deny on unattributed hunks preserves the safety contract.

### Class A/B classification

**Class B** — operating-model contract change to a public command (`/dr-archive`). PRD `prd/PRD-TUNE-0044-multi-agent-workspace-archive-semantics.md` approved 2026-04-29 (Pavel). Backward-compatible: legacy single-agent mode unchanged; new shared mode is opt-in via `--task-id`/`--shared`.

### Verification

- bats `tests/pre-archive-check.bats` — 19/19 PASS (12 legacy + 7 new).
- Stack-agnostic gate — PASS clean on `scripts/pre-archive-check.sh`, `tests/pre-archive-check.bats`, `commands/dr-archive.md`.
- VERSION bumped 1.18.0-rc3 → 1.18.0; CLAUDE.md / README.md badges synced across `code/datarim/` and `Projects/Datarim/`.

### Approved

Human (Pavel), 2026-04-29 (PRD approved earlier same day).

---

## 2026-04-28 — LTM-0017 — Class A apply (3 proposals, post-archive)

### Summary

LTM-0017 archived as Path 2 (escalate to A2 topic-clustering) — entity-resolver canonicalisation cannot lift recall@5 from 0.556 floor case on `ltm-bench-datarim-kb`. Reflection surfaced 3 Class A proposals; Pavel approved all three for application post-archive.

### Class A applies

#### Proposal 1: commands/dr-plan.md — Symbol Existence Check

- **File:** `commands/dr-plan.md` § Step 6.5 "Symbol Existence Check" (new step inserted between Technology Validation and Installer Audit).
- **Class:** A (content addition to existing command spec; no contract change).
- **What:** New mandatory `/dr-plan` step requiring grep-confirmation of every named code surface (method, function, file, flag, env var, CLI command, config key, HTTP route) before plan approval. Plan must cite file:line for each named target. Phantom targets (named in plan, absent from code) explicitly flagged as planning defects requiring redirect or justification.
- **Why:** LTM-0017 plan named `pipeline.py::_resolve_entity` as resolver-fix surface; method did not exist (entity grouping was raw SQL inside `repository.fetch_chunks_for_reflect`). Required in-flight redirect, ~10 min /dr-do investigation. A 30-second grep at /dr-plan would have caught it.
- **Stack-agnostic gate:** PASS clean (`scripts/stack-agnostic-gate.sh commands/dr-plan.md`).
- **Bats verification:** 160/160 PASS post-apply.
- **Approved:** human (Pavel), 2026-04-28.

#### Proposal 2: skills/ai-quality/incident-patterns.md — Floor-Case Diagnostics Dual-Axis

- **File:** `skills/ai-quality/incident-patterns.md` § "Floor-Case Diagnostics — Dual-Axis Audit" (new section appended after "Vendor-Blame Discipline").
- **Class:** A (content addition to incident-patterns fragment).
- **What:** Documents the dual-axis pattern for "metric stuck at baseline" diagnostics. Mandates probing BOTH the *transformation axis* (does new logic do what we designed) AND the *population axis* (is the data visible to the new logic at all). Single-axis audits produce incomplete root-cause analyses. Includes 5 rules and an exemplar.
- **Why:** LTM-0017 plan framed diagnostic exclusively around canonicalisation (transformation axis). Audit returned 0.00% transformation delta — true no-op. Population probe surfaced 134/188 (71%) entities with `source_chunk_id IS NULL` — invisible to JOIN regardless of canonicalisation. A dual-axis plan would have surfaced both gaps in the same audit.
- **Stack-agnostic gate:** PASS clean.
- **Bats verification:** 160/160 PASS post-apply.
- **Approved:** human (Pavel), 2026-04-28.

#### Proposal 3: ~/arcanada/CLAUDE.md — Pre-commit re-verification (workspace, not framework)

- **File:** `~/arcanada/CLAUDE.md` § Multi-Agent Workspace Discipline rule 8 (sub-step "Pre-commit re-verification (retry-tolerant blob-swap)").
- **Class:** A — workspace-level rule extension; not subject to stack-agnostic gate or bats (workspace CLAUDE.md is project-specific, not framework runtime).
- **What:** Pre-commit verification: between `git update-index` and `git commit`, run `git diff --staged --numstat` + capture HEAD SHA. If file-set / line-counts diverge from expected blob-swap delta, or HEAD shifted, redo blob-swap from new HEAD before commit.
- **Why:** During LTM-0017 archive, parallel session's TRANS-0027 commit landed between my `update-index` and `commit`, causing my staged blob to lose the LTM-0017 entry. ~10 min recovery vs ~30s preemptive check.
- **Approved:** human (Pavel), 2026-04-28.

### Class B (none)

No Class B proposals from LTM-0017 reflection.

### Follow-Up Tasks Added to Backlog (already by /dr-do Step 12)

- **LTM-0018** — A2 topic-clustering grouping primitive design (P2, L3). Unblocks LTM-0009.
- **LTM-0019** — Entity `source_chunk_id` backfill investigation (P3, L2).

---

## 2026-04-28 — SEC-0001 — Class A apply (1 bundled proposal, archive Step 0.5)

### Summary

SEC-0001 closed Security Mandate Finding 5: leaked OAuth Client ID in public framework repo (11-day exposure window). 5-phase response per Mandate S3.5 (sanitize HEAD → rotate client → audit → history scrub → ecosystem sweep + CI gate). Step 8 history scrub revealed two recipe gaps the framework should now codify: (a) `git filter-repo --replace-text` is content-only — the same redacted token survived in my own commit message until a second run added `--replace-message`; (b) `git push --force --tags` after history rewrite overwrites every tag — including any tag intentionally placed at pre-rewrite HEAD as a backup, silently neutralising the backup channel. Local mirror saved the day. Both lessons folded into a new § "Git history scrub recipe" in `skills/security.md`.

### Class A applies

#### Proposal 1+2 (bundled): security.md — Git history scrub recipe

- **File:** `skills/security.md` § "Git history scrub recipe (post-leak rotation)" (new section, inserted between "Cross-Stack Relative-Path Includes" and "Reusable Templates")
- **Class:** A (content addition to existing skill; no contract change).
- **What:** Added § "Git history scrub recipe" covering: (1) `git filter-repo --replace-text FILE --replace-message FILE` mandatory two-flag invocation form, (2) mandatory pre-push local grep gate (`git log --all -p | grep -cE '<patterns>'` MUST = 0; non-zero = re-edit + re-clone + re-run), (3) backup-placement rule (never use a tag in the same repo as backup channel — force-push tags after filter-repo rewrites every tag; use local mirror clone or external object storage or separate repo), (4) `--force-with-lease` over `--force` for collaborative repos, (5) post-scrub clone-sync notification protocol.
- **Why:** SEC-0001 Step 8 first run leaked GA4 property ID through commit message (caught by mandatory grep gate before push); release-tag-as-backup got rewritten by `--force --tags` and became useless. Permanent rules close both gaps for the next quarterly rotation cycle.
- **Stack-agnostic gate:** PASS clean (`scripts/stack-agnostic-gate.sh skills/security.md`). Generic placeholders used (`<pattern>`, `<incident-id>`, `<branch>`, `<remote>`); no Arcanada-specific identifiers leaked into the recipe.
- **Bats verification:** 160/160 PASS post-apply.
- **Approved:** human (Pavel), 2026-04-28.

### Class B (HELD)

- **B1: Workspace-discipline cross-cite for SEC-* tasks** (project-level CLAUDE.md edit, not framework). Append concrete blob-swap example from SEC-0001 (4 files, 154+/1−, ~13 parallel sessions' foreign hunks preserved). **Defer reason:** project-level documentation amplification rather than runtime contract; could be re-classified as A on review. Holding until next workspace-discipline-related incident or until re-evaluated 2026-05-28.

### Class A held (proposal not yet applied)

- **Proposal 5: gitleaks vault-config template** (`templates/gitleaks-vault-config.toml`) — pre-tuned `.gitleaks.toml` with allowlists for `wiki/_raw_/`, `.obsidian/plugins/`, compiled JS bundles (67/70 false positives in SEC-0001 sweep of `Arcanada-one/arcanada-ecosystem` came from these sources). **Defer reason:** SEC-0002 (ecosystem CI rollout) is the natural consumer; better to design the template against real findings during SEC-0002 /dr-plan than to ship a speculative template now. Linked to SEC-0002 backlog entry.

### Follow-Up Tasks Added to Backlog

- **SEC-0005** (added in SEC-0001 /dr-do per Step 10 sweep findings, not in this archive's reflection): rotate 3 HIGH secrets in `Arcanada-one/arcanada-ecosystem` private repo + scrub history. P1, L2, ~2-3 ч.

---

## 2026-04-27 — TUNE-0034 — Class A apply (1, archive Step 0.5, v1.17.3)

### Summary

TUNE-0034 closing round (residual 2 reds → 0) surfaced the «backlog inventory drift» pattern: backlog body listed «10 failing tests» with named root causes per number, but pre-flight `bats tests/` at /dr-do start showed only 2 actual reds (8 had been silently closed by intervening tasks: TUNE-0029, TUNE-0040, TUNE-0043, and an earlier TUNE-0034 v1.17.1 round). Estimate (30-60 min) was 5× the actual (10 min). Class A apply codifies the re-verification recipe that prevents phantom-debug work on the next cleanup cycle.

### Class A applies

#### Proposal 1: backlog-and-routing.md — Re-verify quantitative backlog inventories at init/do start

- **File:** `skills/datarim-system/backlog-and-routing.md` § Plan Drift Discipline (new sub-section)
- **Class:** A (content addition to existing skill; complements the adjacent «Avoid absolute test-count numbers in AC formulation» § from TUNE-0043).
- **What:** Added sub-section «Re-verify quantitative backlog inventories at init/do start» with a 5-step recipe (re-execute the source diagnostic, compare live to inventory, amend / escalate / proceed). Sources cited: TUNE-0034 v1.17.1 + v1.17.3 cycle showing 10 → 2 inventory drift.
- **Why:** Closes the inventory-side mirror of the AC-side drift rule already in this file. Same source-of-truth logic, applied at the inventory level instead of the AC level. Pattern parallels TUNE-0028 (stale skill count) and TUNE-0043 (absolute test-count drift).
- **Stack-agnostic gate:** initial draft FAILed (1 hit: `npm audit` in example list, line 88); reworded to «the project's package-manager-native audit command» using the canonical microcopy from TUNE-0043 Proposal 2 (security.md). Re-run: PASS clean ×4 scopes.
- **Bats verification:** 160/160 PASS post-apply.
- **Approved:** human (Pavel), 2026-04-27.

### Class B (HELD)

- **B1: Archive-cycle scan of adjacent backlog items.** When `/dr-archive` Step 0.5 reflection notes that the just-completed task incidentally fixed reds/hits owned by another open backlog item, propose backlog-body amendments to that adjacent item. **Defer reason:** changes archive-cycle contract; requires PRD update or amendment to `commands/dr-archive.md` spec. Re-evaluate by 2026-05-27 if Proposal 1 (init/do side fix) turns out insufficient.

### Follow-Up Tasks Added to Backlog

None. TUNE-0035 (Site update cross-product checklist verify) is already in backlog with status `pending` since 2026-04-25 and may benefit from the same re-verification recipe at /dr-init time.

---

## 2026-04-27 — CONN-0047 — Class A apply (1, archive Step 0.5)

### Summary

Groq connector deploy revealed silent env-var staleness mode: `.env` updated on disk, but `docker compose up -d --build` did not recreate the container because the image hash matched. Container kept the pre-edit env snapshot; smoke against the application would have failed `auth_error` despite a "successful" deploy. Closed by `docker compose up -d --force-recreate`. Generic pattern, applies across the ecosystem (Transcribator, Verdicus, Auth Arcana, Munera, Ops Bot).

### Class A applies

#### Proposal 1: live-smoke-gates.md — Gate 5 «Container Env-Var Freshness After Deploy»

- **File:** `skills/testing/live-smoke-gates.md` (new section appended; intro line «Three related gates» → «Five related gates»)
- **Class:** A (new gate, content-only addition; existing 4 gates untouched)
- **What:** New Gate 5 mandates `docker exec <container> sh -c 'env | grep <NEW_VAR>'` (or k8s/systemd equivalent) after any deploy that adds, removes, or changes env vars. File-level `grep .env` is necessary but not sufficient — only process inspection proves the running container picked up the change. Verdict matrix: file present + process env shows new value → proceed; file present + process env empty → force `--force-recreate`, re-verify; file absent → fix deploy first. Reference incident: CONN-0047.
- **Why:** CONN-0047 deploy auto-fired CI on push of `feat(CONN-0047)`; CI ran `docker compose up -d --build` and reported success. `.env` had `GROQ_API_KEY=gsk_*`, but `docker exec ... env | grep GROQ` returned empty. Smoke против `/connectors/groq/execute` failed bы как `auth_error`. Closed by manual `--force-recreate`. Generic Compose semantics: `env_file` читается at container *create*, not container *start*; recreate only когда image identity меняется. Lesson generalises to every deploy в экосистеме с secrets/keys/flags в `.env`.
- **Stack-agnostic gate:** PASS (Docker Compose / kubectl / systemd terminology kept generic; «or k8s/systemd equivalent» / «or equivalent» phrasing throughout).
- **Bats:** 160/160 PASS post-apply.
- **Approved:** human (Pavel) auto-approval per autonomous-ops memory, applied during /dr-archive CONN-0047 Step 0.5.

### Class B (HELD)

#### Proposal 4: CI deploy `--force-recreate` on env change

- **Class:** B — infrastructure deploy contract change
- **Target:** `Projects/Model Connector/code/.github/workflows/ci.yml` (deploy job)
- **Held because:** changes deploy semantics beyond a single connector; needs ADR / short design doc для Model Connector (no PRD exists yet).
- **Action:** Deferred to follow-up task (recommendation: новый `INFRA-0030` или `CONN-0049` когда Pavel ready to formalise).

### Class A (REJECTED runtime placement)

#### Proposal 2: api-connector-mirror-pattern.md template

- **What:** Reusable «OpenAI-compat API connector» template for future connectors (Grok / Together / Fireworks / etc.).
- **Rejected for:** runtime framework (`$HOME/.claude/templates/`).
- **Reason:** Template is NestJS + vitest specific (stack-bound) — runtime framework is stack-neutral. Stack-agnostic gate would FAIL.
- **Recommended placement:** `Projects/Model Connector/templates/api-connector-template/` (project-level). Out of scope for этого archive — track как informal reminder для CONN-0048 implementation.

### Class A (REJECTED — out of scope)

#### Proposal 3: Project Model Connector CLAUDE.md addendum

- **What:** «Adding a new API connector — checklist» 7-step paragraph в `Projects/Model Connector/CLAUDE.md`.
- **Rejected for:** этого archive's apply window.
- **Reason:** Onboarding-only doc, low impact, can be added inline by next CONN task developer when actually needed. Avoids CLAUDE.md churn без trigger.

---

## 2026-04-27 — LTM-0013 — Class A apply (1, archive Step 0.5)

### Summary

Reflect-job entity-grouping pilot caught a corpus floor case (188 entities, 187 single-chunk → only 1 group qualifies for ≥2-chunk threshold), producing 4 meta-facts. Resulting recall@5=0.556 = baseline = AC-2 numerical miss. Plan §3.4 had explicit DIAGNOSE branch-trigger, so the miss became an expected handled outcome rather than blocked archive. **Lesson:** for features whose acceptance metric depends on group-aggregated data, a coverage probe BEFORE the N=1 smoke would have flagged the floor case in advance and validated that the plan included a branch-trigger.

### Class A applies

#### Proposal 1: live-smoke-gates.md — Coverage probe sub-section

- **File:** `skills/testing/live-smoke-gates.md` Gate 4
- **Class:** A (refinement of existing mandatory gate; new sub-section)
- **What:** Added «Coverage probe (group-aggregation features)» sub-section после «What a passing gate looks like». Mandates pre-pilot probe для features dependent на group-aggregated data: count groups satisfying ≥N-member threshold; flag plan'ы без branch-trigger при near-floor count (1-2 groups). Reference incident: LTM-0013.
- **Why:** LTM-0013 reflect pilot — corpus floor case (1 entity-group qualifying). AC-2 numerically missed. Plan §3.4 had DIAGNOSE branch-trigger, so miss handled gracefully — but probe earlier would have surfaced floor case before pilot started + validated trigger existence proactively. Pattern generalises to topic-clustering / batched aggregation / multi-row reflection features.
- **Stack-agnostic gate:** PASS (skills scope clean).
- **Approved:** human (Pavel), 2026-04-27.

### Class B (HELD)

- **B1:** Per-request `score_factor` override в Scrutator `RecallRequest`. **Defer reason:** project-specific API contract change, not framework-level. Tracked в LTM project follow-up.
- **B2:** Pre-pilot operator checklist (migration apply / container deploy / `.env` setup). **Defer reason:** project-specific (Scrutator on arcana-db). Belongs в `Projects/Scrutator/code/CLAUDE.md`.

### Follow-Up Tasks Added to Backlog

- **LTM-future-DIAGNOSE** (P2, L2) — already added 2026-04-27 per plan §3.4 trigger (entity-resolver coverage gap audit + reflect rerun + sweep rerun).
- **LTM-future-OPS-1, OPS-2, SCRUTATOR-housekeeping-1** — proposed в reflection «Next Steps»; awaiting user confirmation before adding.

---

## 2026-04-27 — TUNE-0043 — Class A applies (3, archive Step 0.5)

### Summary

TUNE-0043 `/dr-archive` Step 0.5 reflection produced three Class A proposals — all pre-flagged through QA + compliance + Step 7 (version bump). All three PASS the `stack-agnostic-gate.sh` and were applied to runtime. Bats `tests/` 158/160 PASS after applies (2 pre-existing reds unchanged: #115 testing.md description >155 = TUNE-0042; #128 T3a separate concern). 0 regressions.

### Changes

| # | Category | Target | Change |
|---|----------|--------|--------|
| 1 | skill-update | `skills/evolution/stack-agnostic-gate.md` (new § «Markers must be on separate lines (pitfall)») | Block-style markers ONLY: awk strip uses `next` after opening match, so closing marker on the same input line is never processed → `skip=1` persists for the rest of the file. Examples of correct (separate lines) and wrong (same line) usage. Source incident: TUNE-0043 — initial wrap attempts on inline mentions used the same-line form; gate kept FAILing despite the wrap looking correct in the diff. |
| 2 | skill-update | `skills/security.md` (new § «Stack-neutral phrasing for dependency-audit references») | Locks the canonical phrasing «package-manager-native audit command at the declared severity threshold» that emerged 4× as TUNE-0043 reword across `security.md`, `project-init.md`, `researcher.md`, `dr-qa.md`. Concrete commands belong in project-level `CLAUDE.md`. Examples list wrapped in `<!-- gate:example-only -->` markers. Prevents the same reword cycle in future Class A applies. |
| 3 | skill-update | `skills/datarim-system/backlog-and-routing.md` § Plan Drift Discipline (new sub-§ «Avoid absolute test-count numbers in AC formulation») | Test-baseline ACs that pin an absolute number (e.g. «≥159/160 PASS») drift between plan and `/dr-do` whenever an unrelated concurrent task changes the suite. Recommends semantic phrasing: «0 new failures vs HEAD baseline» or «test count ≥ HEAD baseline (verify with `git stash && bats tests/`)». Source: TUNE-0043 AC-5 («≥159/160» in plan, actual 158/160 at QA — semantic intent met but absolute number was stale). |

### Verification

- **Stack-agnostic gate:** PASS clean on all three edited files (`scripts/stack-agnostic-gate.sh ~/.claude/skills/{security.md,evolution/stack-agnostic-gate.md,datarim-system/backlog-and-routing.md}`).
- **Bats baseline:** 158/160 PASS post-apply. The 2 reds are pre-existing (verified pre-edit in compliance-report-TUNE-0043.md): #115 `optimize-merge.bats` testing.md description >155 chars (TUNE-0042); #128 T3a (separate concern).
- **Recurrence loop closure:** all three applies are downstream of the loop VERD-0010 → VERD-0021 → TUNE-0039 → TUNE-0040 → TUNE-0043. Each application reinforces the gate's own contract (Proposal 1), the canonical microcopy that prevents future leaks (Proposal 2), or the planning discipline that surfaces drift earlier (Proposal 3).

---

## 2026-04-27 — v1.17.2 — TUNE-0043 — Complete stack-agnostic sweep

### Summary

TUNE-0040 closure left a known-deferred state: gate v2 bash 3.2 fd-leak fix unmasked 32 hits across 11 files which had been silently failing the gate before the fix (single-grep ERE alternation rewrite). TUNE-0043 closes the remaining surface: 4 reword + 4 wrap (block-style markers) + 2 whitelist + 1 hybrid. Gate now PASSes clean (exit 0) on all four scopes (`skills/`, `agents/`, `commands/`, `templates/`).

### Changes

| # | Category | Target | Change |
|---|----------|--------|--------|
| 1 | gate-extension | `scripts/stack-agnostic-gate.sh` `WHITELIST` array + `skills/evolution/stack-agnostic-gate.md` § Whitelist | Added 2 entries: `skills/testing/live-smoke-gates.md` (DEV-1156/1169 incident postmortems with stack-specific DI/lifespan semantics — parallel `deployment-patterns.md` precedent) and `skills/utilities/ga4-admin.md` (Python-specific GA4 Admin API recipe — parallel `tech-stack.md` precedent). Both rationales meet 4 whitelist criteria from gate-spec § «When to add a file to the Whitelist». |
| 2 | reword | `skills/security.md:19` | `npm audit` → `package-manager-native audit command at the declared severity threshold` |
| 3 | reword | `skills/project-init.md:152` | `pnpm install, uv sync` → `via the project's package manager` |
| 4 | reword | `agents/researcher.md:14` | `npm audit` → `package-manager-native audit` |
| 5 | reword | `commands/dr-qa.md:118` | `npm audit, pip audit, cargo audit` → `the project's package-manager-native audit command at the declared severity threshold` |
| 6 | wrap | `skills/discovery.md:127-131` | Q&A example block (Jest detection demo) wrapped in `<!-- gate:example-only -->` markers (block-style, separate lines) |
| 7 | wrap | `skills/testing.md:10-14` | `## Frameworks` section body wrapped (taxonomy enumeration) |
| 8 | reword | `skills/testing/bats-and-spec-lint.md:8,14,47` | Removed «Vitest/Jest» comparisons entirely, generalized to «code-test runners» / «JS/TS test runner» (3 hits eliminated cleanly without escape hatch — proved cleaner than wrapping) |
| 9 | wrap | `agents/tester.md:18-32` Test Runner Detection table + reword line 61 (Web UI list) | Table wrapped (illustrative manifest→runner mapping); line 61 reworded to drop framework list |
| 10 | hybrid | `templates/security-deps-upgrade-plan.md` | Lines 40-41: `pnpm install/audit` examples → generic placeholder hints. Lines 50-58: Compatibility Matrix wrapped (NestJS×3 in `(e.g. ...)` examples → generic «backend-framework v11» placeholders inside example block). Line 64: «axios → fetch» → «legacy HTTP client → native fetch». |

### Verification

- **Stack-agnostic gate:** all 4 scopes (`skills/`, `agents/`, `commands/`, `templates/`) → exit 0 PASS clean. Inventory was 32 hits / 11 files (fixture: `datarim/tasks/TUNE-0043-fixtures.md`); post-edit: 0 hits / 0 files.
- **Bats baseline:** 95/100 PASS. The 5 reds are pre-existing (verified via `git stash` + run): #60/63/64 — `optimize-merge.bats` cwd-dependent path issue (unrelated to TUNE-0043), #65 — `infra-automation.md` description 186 chars (separate sweep), #78 — `class-ab-gate.md` not in T3 reflect-removal-sweep whitelist (separate concern). No new failures introduced.
- **Inline-marker pitfall surfaced:** initial attempt used inline `<!-- gate:example-only -->X<!-- /gate:example-only -->` on the same line as content. The gate's awk strip uses `next` after matching the opening marker, so the closing marker on the same line is never processed → `skip=1` persists indefinitely. Reverted to (a) block-style markers (each on its own line) where the wrapped content was a multi-line block, (b) plain reword where only inline mention existed. This pitfall is a Class A apply candidate (see below).

### Pattern-level Class A apply candidates (deferred to /dr-archive Step 0.5)

1. **Inline-marker pitfall** — `evolution/stack-agnostic-gate.md` (gate contract) should explicitly note: «markers MUST be on their own lines; inline `<!-- gate:example-only -->X<!-- /gate:example-only -->` does not work because awk's `next` skips closing-marker matching on the same input line.»
2. **«package-manager-native audit» phrasing** — emerged 4× as the canonical reword for `npm audit` / `cargo audit` / `pip audit`. Could become a documented microcopy pattern in `skills/security.md` (When citing dependency-audit commands in framework runtime, use the abstract phrasing — «the project's package-manager-native audit command at the declared severity threshold»; concrete commands belong in project `CLAUDE.md`).

---

## 2026-04-27 — LTM-0012 — Class A applies (2)

### Summary

LTM-0012 (`/dr-archive` Step 0.5) reflection produced two stack-agnostic Class A proposals — both PASS the `stack-agnostic-gate.sh` and were applied to runtime. Source pain: the LTM-0012 entity-resolution gap (recall@5 met, but extraction-rate 17 % vs target 80 % + manual `as_of` smoke fail) was discoverable in 5 minutes via an N=1 smoke before the 1209-second pilot, and pilot subset «50 → 41 chunks» drift was operationally correct but never reflected in the plan document.

### Changes

| # | Category | Target | Change |
|---|----------|--------|--------|
| 1 | skill-update | `skills/testing/live-smoke-gates.md` (+ entry pointer in `skills/testing.md`) | Added **Gate 4: N=1 Smoke Validation Before Bulk Ingest/Transform**. Generic principle: before any bulk run that depends on a parser/resolver/normalizer (re-ingest, batch migration, ETL, embedding refresh), run the full path on ONE known-representative item and assert intermediate state — FK target / canonical attribution / downstream filter behaviour, not just final output. Mocks don't satisfy because tie-breakers depend on real-data namespace state. Reference incident: LTM-0012 entity-resolution gap. |
| 2 | skill-update | `skills/datarim-system/backlog-and-routing.md` | Added **§ Plan Drift Discipline**. Rule: when a `/dr-do` step modifies an Acceptance Criterion in a measurable way (sample size, threshold, dataset, tool), patch the plan document inline before commit, not after QA flags drift. Recurrent class with TUNE-0034 (stale `@test` count) and TUNE-0028 (stale skill count). |

### Verification

- **Stack-agnostic gate:** PASS on both edited files (entries 1 and 2). Pre-existing FAIL on `skills/testing.md` (Jest/Mocha/Vitest in legacy "Frameworks" section, lines 12-13) confirmed to predate this edit; out of scope per `evolution/stack-agnostic-gate.md` § Out of Scope (forward-looking gate).
- **Bats:** 159/160 PASS. The single red is `optimize-merge.bats:115` (`testing.md` description 172 chars > 155 limit) — confirmed pre-existing via `git stash` + bats run (the failure reproduces without the edit). Not introduced by these applies.
- **Class A applies do not introduce new bats regressions.** The pre-existing description-length red is tracked separately for the next `/dr-optimize` description-length sweep.

---

## 2026-04-27 — v1.17.1 — TRANS-0017 — Heredoc-vs-stdin pitfall

### Summary

One Class A reflection proposal applied during `/dr-archive TRANS-0017` (Phase C CI/CD hardening for Transcribator). Source bug: initial `post-deploy-verify.sh` evaluator used `python3 - <<'PY' ... sys.stdin.read() PY` over a piped JSON payload — the heredoc body replaced stdin entirely, so the parser silently consumed its own template instead of the captured PROD snapshot. Tests passed for the wrong reason until cross-checked by hand. Generic bash + inline-interpreter pitfall, not stack-specific. Recovery recipe (env-var pass-through or here-string + `-c` script) included so future ops-script work doesn't repeat it.

### Changes

| # | Category | Target | Change |
|---|---|---|---|
| 1 | skill-update | `skills/ai-quality/bash-pitfalls.md` | Appended § «Pitfall: Heredoc IS stdin» with WRONG/RIGHT pattern, env-var pass-through recipe, here-string alternative, TRANS-0017 case study reference. |

Stack-agnostic gate verification (`bash scripts/stack-agnostic-gate.sh skills/ai-quality/bash-pitfalls.md`): **PASS clean**.
Bats baseline: 159/160 (1 pre-existing fail: testing.md description >155 chars, TUNE-0042 follow-up — no regression introduced).

### Class A: rejected proposals

- A2 (`docker image prune` `-af` vs `-f` scope) — too narrow for standalone Class A; underlying lesson already implicit in `ai-quality/deployment-patterns.md` (whitelisted, stack-aware) plus concrete fix in TRANS-0017 runbook. Documented in reflection only.

### Class B

None.

### Follow-up tasks

None new. Steps 10-11 (synthetic acceptance test + Pavel walkthrough Level-1 rollback) — PROD activity, не отдельная задача backlog'а; tracked в archive-TRANS-0017 § Outstanding.

### No version bump

Single-pitfall append; not warranting 1.17.1 → 1.17.2. Patch-mode site sync deferred — bash-pitfalls fragment is internal and not surfaced via `data/skills/*.php`.

---

## 2026-04-26 — v1.17.1 — TUNE-0034 — Bats baseline cleanup + reflection apply

### Summary

10 pre-existing bats failures (carry-over baseline through 2 archive cycles) classified into 6 stale + 4 fixable, resolved to 0 fail / 154 pass / 154 total — first clean baseline since v1.10.0. Two opportunistic verify-wiring tasks (TUNE-0035 cross-product checklist, TUNE-0036 staged-diff audit) batched and confirmed active in the same archive cycle. Three Class A reflection proposals approved and applied.

### Changes

**Bats cleanup (TUNE-0034 core):**
- `tests/optimize-audit.bats` — removed 3 stale assertions on the deleted `## Structured Audit Report` 6-section schema in `agents/optimizer.md`.
- `tests/optimize-merge.bats` — removed 3 stale assertions (`go-to-market.md` existence + frontmatter + snapshot "24 skills" count).
- `tests/reflect-removal-sweep.bats` — whitelist extended +2 (`skills/evolution/{class-ab-gate,examples-and-patterns}.md`).
- `skills/evolution.md` — added Historical-note paragraph (v1.10.0/TUNE-0013 forward-pointer + cross-ref to `skills/utilities/recovery.md`).
- `skills/file-sync-config.md` — frontmatter `description` 339 → 133 chars (155-char cap restored).
- `docs/evolution-log.md:223` — TUNE-0034 follow-up entry rephrased (drop retired-command literal substring; transient log not whitelisted).

**Class A reflection proposals (3 applied):**
| # | Category | Target | Change | Rationale |
|---|---|---|---|---|
| 1 | skill-update | `skills/testing.md` | Added § "Triaging Legacy Test Failures" — 3-bucket taxonomy (delete / patch / rephrase) with TUNE-0034 examples + decision aid | Reflection: fixture used 2-bucket taxonomy and missed the rephrase case at /dr-do |
| 2 | command-update | `commands/dr-init.md` | Added Step 2.5 "Workspace cross-task hygiene check" — non-blocking advisory grepping foreign task IDs in `datarim/*.md` | Reflection: TUNE-0036 staged-diff catches tangle at archive but only after carry-over costs a session; surface at /dr-init |
| 3 | claude-md-update | `code/datarim/CLAUDE.md:121` | `(23 skills, ...)` → `(24 skills, ...)` — match actual filesystem count | Reflection: test #119 (snapshot enforcer) was correctly removed but the drift remained; bumped doc to actual |

**Site (patch-mode):**
- `Projects/Websites/datarim.club/config.php` — version 1.17.0 → 1.17.1.
- `Projects/Websites/datarim.club/pages/changelog.php` — new v1.17.1 "Latest" entry; demoted v1.17.0 by removing its `'tag' => 'Latest'`.

**Workspace version anchors:**
- `code/datarim/{VERSION,CLAUDE.md,README.md}` — 1.17.0 → 1.17.1.
- `Projects/Datarim/{README,CLAUDE}.md` — current-version markers bumped (semantic `v1.17.0+` operating-model anchors retained).

### Verification

- `bats tests/` (1.13.0): 154/154 pass / 0 fail (was 150/10/160).
- Live: https://datarim.club/en/changelog HTTP 200, v1.17.1 visible (2 grep hits, "Latest" demoted).
- Cross-product diff (TUNE-0035 wiring) caught 2 pre-existing site drifts → filed as TUNE-0037 (file-sync-config.php missing) + TUNE-0038 (orphan telegram-publishing.php).

### Class B proposals

None — content-only cleanup, no operating-model change.

### Follow-Up Tasks Added to Backlog

- **TUNE-0037** — Add `data/skills/file-sync-config.php` site page (EN+RU short+body). L1, P3.
- **TUNE-0038** — Cleanup orphan `data/skills/telegram-publishing.php` (skill removed pre-2026, PHP not cleaned). L1, P3.
- **TUNE-0035 / TUNE-0036** — closed as **verified** (cross-product wiring caught 2 drifts; staged-diff audit + cross-task leakage detection present in `commands/dr-archive.md:26`).

---

## 2026-04-25 — v1.17.0 — TUNE-0033 — Symlink-default install + `local/` overlay

### Summary

Operating-model revision. Default `install.sh` mode is now **symlink** — `~/.claude/{agents,skills,commands,templates}` become symlinks to the cloned repo's matching directories. The runtime IS the repo: edits land in git tracking immediately, drift is impossible by definition, and the `curate-runtime.sh` / `check-drift.sh` workflow becomes a copy-mode-only legacy path. A new gitignored `~/.claude/local/` overlay holds personal additions and overrides.

### Changes

**Updated files:**
- `install.sh` — added `--copy` flag, `detect_install_mode`, `detect_existing_topology`, `link_scope_tree`, `setup_local_overlay`, `migration_prompt` (3 options c/k/a), `migrate_to_symlinks`. Symlink-aware `force_safety_guard` short-circuit. Main flow rewired around install-mode branch. Added `DATARIM_FORCE_UNAME` and `DATARIM_MIGRATION_CHOICE` test hooks.
- `update.sh` — added `detect_runtime_mode`. Symlink topology → exits 0 after `git pull`. Copy topology → calls `install.sh --copy --force --yes` (preserves user's mode).
- `scripts/curate-runtime.sh` — added DEPRECATED-in-v1.17 banner; removal scheduled for v1.18 (TUNE-0044).
- `scripts/check-drift.sh` — added DEPRECATED banner; symlink → repo now exits 0 (sync by definition); symlink → other path treated as drift.
- `validate.sh` — added Local Overlay Override Check that emits `WARN: override detected: local/<scope>/<file> shadows <scope>/<file>`.
- `skills/datarim-system.md` — added § Loading Order documenting the framework + overlay layering and conflict-resolution rule.
- `docs/getting-started.md` — § Installation rewritten for symlink-default + `--copy` fallback + Windows note + `local/` overlay + migration prompt; § Updating rewritten around runtime-mode branch.

**New tests** (16 added, all passing — final 150 pass + 10 pre-existing fail = 160 total):
- `tests/install.bats` — 8 tests covering AC-1 (symlink + local overlay), AC-2 (`--copy`), AC-3 (Windows fallback via `DATARIM_FORCE_UNAME`), AC-4 (migration c/k/a), AC-5 (`--force` no-op on symlinks).
- `tests/check-drift.bats` — 2 tests covering AC-9 (symlink → exit 0; copy + drift → exit 1).
- `tests/update.bats` (new) — 2 tests covering AC-6 (symlink skips install; copy passes `--copy` to install).
- `tests/validate-override.bats` (new) — 2 tests covering AC-7 (override WARN; clean case INFO).
- `tests/deprecation-banners.bats` (new) — 2 tests covering AC-8 (curate-runtime + check-drift banners reference TUNE-0033).
- `tests/helpers/install_fixture.bash` — added `setup_full_scripts`, `seed_existing_copy_install`, `seed_symlink_install`, `init_fake_git_with_origin`, `assert_symlink_to`.

### Class A/B Gate

This change is **Class B** (operating-model change, public framework contract). Approved: human (Pavel), 2026-04-25, via `/dr-prd TUNE-0033` PRD review and `/dr-design TUNE-0033` consilium-light validation.

### Rationale

TUNE-0032 QA notes N1 + N3 surfaced a contract contradiction: under symlink topology (which arcanada workspace already used internally), `check-drift.sh` exiting 1 was a "detection impossible" guard, not real drift, and `curate-runtime.sh`'s "runtime → repo" direction was semantically vacant (the inode is the same on both sides). Five derived problems documented in PRD § Problem Statement.

The pivot from the original "fork-first" framing to "symlink-default + `local/` overlay" was driven by research (`datarim/insights/INSIGHTS-TUNE-0033.md`): every studied precedent (oh-my-zsh `$ZSH_CUSTOM`, bash-it `custom/`, chezmoi, prezto) rejects fork as the primary path for end-user additions because of Markdown merge-conflict UX cost. Fork remains a contributor path, documented in one paragraph.

### Migration & Rollback

- v1.16 → v1.17 upgrades show an interactive prompt with three options ([c]onvert / [k]eep / [a]bort). `--yes` auto-converts. Original real-copy contents are preserved under `$CLAUDE_DIR/backups/migrate-<timestamp>/SUCCESS`.
- Single-revert rollback: `git revert <TUNE-0033-commit>` in `code/datarim/` restores the v1.16 contract; users on symlinks remove the symlinks, `git checkout v1.16.0`, then `./install.sh --force --yes`. The `local/` overlay is never touched by rollback. ≤15 minutes total.

### Deferred follow-ups (registered as backlog items)

- **TUNE-0044** — Final removal of `curate-runtime.sh` and `check-drift.sh` in v1.18 (deferred until at least one minor release of grace period).
- **TUNE-0045** — Critical-skill override blocklist: turn validate.sh WARN into an ERROR for shadows of `security.md`, `compliance.md`, `datarim-system.md` (security recommendation, ship-and-iterate).
- **TUNE-0046** — `cleanup_old_migrate_backups`: rotate `$CLAUDE_DIR/backups/migrate-*` keeping the 5 most recent (sre recommendation).

---

## 2026-04-25 — TUNE-0033 — Reflection Class A Proposals (5 applied)

Reflection (Step 0.5 of `/dr-archive TUNE-0033`) generated 5 Class A evolution proposals; all 5 approved and applied. Class B count: 0.

### Proposal 1 — Cross-product checklist mapping for operating-model changes (claude-md-update)

- **Target:** `Projects/Websites/CLAUDE.md` § "Cross-product checklist (generalised TUNE-0028 + TUNE-0032 rule)"
- **What:** Added 3 new rows to the Runtime → Site mapping table covering operating-model changes (operating-model → `pages/getting-started.php` mandatory; → `pages/home.php` conditional; → `content/{en,ru}.php` conditional). Added pre-deploy operating-model term grep gate.
- **Why:** TUNE-0033 — `pages/getting-started.php` was not updated in /dr-do, surfaced only at /dr-archive live verification (AC-19). Existing checklist covered per-artefact maps but not systemic surfaces like onboarding pages.
- **Evidence:** PRD-TUNE-0033 AC-19 listed live `/docs/getting-started \| grep symlink`, but plan §5 affected files did not include `pages/getting-started.php`.

### Proposal 2 — Class B Public Surface Scan checkpoint in /dr-plan (skill-update)

- **Target:** `commands/dr-plan.md` (new step 12 between Live Audit Checkpoint and Output Summary)
- **What:** Added mandatory "Class B Public Surface Scan" step requiring enumeration of ALL user-facing surfaces reflecting the new operating model (8 minimum surfaces listed). For each surface, plan §5 MUST include affected-files entry AND PRD MUST include corresponding acceptance criterion. Deferring = Class B contract violation.
- **Why:** Same root cause as Proposal 1 — Class B operating-model task surface scan was implicit, not codified, leading to deferred public surfaces.

### Proposal 3 — Improve deploy.sh dry-run UX

- **Target:** `Projects/Websites/deploy.sh`
- **What:** Added `[DRY RUN]` prefix to deploy line when `--dry-run` flag is set, plus distinct trailing message ("[DRY RUN] No files transferred. Run without --dry-run to execute.") instead of identical "Done: ... deployed" line. Real deploy still prints "Done: $DOMAIN deployed".
- **Why:** TUNE-0033 — initial dry-run output was practically indistinguishable from real deploy. Operator (me) almost misinterpreted result.

### Proposal 4 — Document `absorbed` task disposition pattern (skill-update)

- **Target:** `skills/datarim-system.md` (new § "Task Disposition Patterns" before Quick Routing Heuristic)
- **What:** Documented 4 dispositions — `completed`, `cancelled`, **`absorbed`** (new), `superseded`. Each with When / Action columns. `absorbed` covers the case where a task's deliverable is fully delivered inside another task's scope (TUNE-0031 update.sh inside TUNE-0033).
- **Why:** TUNE-0031 status was "superseded-pending" with no clean disposition vocabulary. `absorbed` accurately captures: deliverable shipped, but in a different task's archive. Preserves audit trail.

### Proposal 5 — Workspace cross-task leakage detection in /dr-archive Step 0.1 (skill-update)

- **Target:** `commands/dr-archive.md` Step 0.1
- **What:** Added proactive check: when running clean-git, examine modified `datarim/` workflow files for foreign task IDs. If foreign IDs (e.g. `TRANS-0015`, `VERD-0010`) appear in diff while archiving a different task → flag as out-of-scope.
- **Why:** TUNE-0033 — workspace `datarim/{tasks,backlog,progress,activeContext}.md` carried 100+ uncommitted lines from TRANS-0015 / VERD-0010 / LTM-0004 prior sessions. Staged-diff audit (TUNE-0032 lesson) caught the leak only at commit time. Proactive task-ID mapping at Step 0.1 prevents the round-trip.

### Class A/B Gate

All 5 proposals are **Class A** (content updates, no operating-model changes). Approved: human (Pavel), 2026-04-25, via `/dr-archive TUNE-0033` reflection review with `all` approval.

### Health Metrics Snapshot

- Skills: 23 (no new skill, 1 § added to `datarim-system.md`)
- Agents: 17 (no change)
- Commands: 19 (no change, 2 commands updated: `dr-plan.md`, `dr-archive.md`)
- Templates: 13 (no change)
- bats: 150 pass + 10 fail (carry-over from TUNE-0034 backlog)

All metrics within thresholds. `/dr-optimize` not required.

---

## 2026-04-25 — v1.16.0 — TUNE-0032 — Canonical CTA "Next Step" Block

### Summary

Unified the "Next Step" Call-to-Action (CTA) emitted by every `/dr-*` command and pipeline agent. Before TUNE-0032, each command had ad-hoc free-form `## Next Steps` prose with no task ID, no primary marker, and no multi-task awareness — users running >1 parallel task could not tell which command applied to which task.

### Changes

**New files:**
- `skills/cta-format.md` — canonical spec (single source of truth)
- `templates/cta-template.md` — reusable Markdown snippet
- `tests/cta-format.bats` — 39 spec-regression tests
- `tests/cta-format/fixtures/{single-task,multi-task,fail-routing}.md` — golden fixtures

**Updated files:**
- 17 commands in `commands/dr-*.md` — every command now ends with a unified `## Next Steps (CTA)` section referencing the canonical spec
- 5 agents in `agents/` — `planner`, `architect`, `developer`, `reviewer`, `compliance` load `cta-format.md` and emit canonical block
- `skills/datarim-system/backlog-and-routing.md` — Mode Transition table now references cta-format and documents Layer-to-command map for FAIL-Routing
- `skills/visual-maps/pipeline-routing.md` — added CTA decision points and FAIL-Routing diagram
- `skills/visual-maps/stage-process-flows.md` — added CTA emission map per stage
- `docs/commands.md` — documented the unified CTA contract
- `docs/skills.md` — added `cta-format` to skill catalog
- `VERSION`, `README.md`, `CLAUDE.md` — bumped to 1.16.0
- `Projects/Datarim/{README.md, CLAUDE.md}` — version bump
- `Projects/Websites/datarim.club/` — changelog, features, 17 command pages, new skill page, 5 agent pages

### Class A/B Gate

This change is **Class A** (touches public framework contract — output format every user sees). Approved: human (Pavel), 2026-04-25, via `/dr-prd TUNE-0032` PRD review.

### Rationale

User feedback: "После создания нескольких задач в бэклоге и при одновременной работе над несколькими проектами и задачами часто не понятно, какое действие нужно выполнять." (TUNE-0032 source).

Research (`datarim/insights/INSIGHTS-TUNE-0032.md`) established:
1. clig.dev + Atlassian Forge CLI principles canonize numbered + primary CTAs
2. Cognitive load research (Miller, Hick's Law, Chernev 2015) sets sweet spot at 3 options, max 5
3. Box-drawing characters (`─`) cause Windows mojibake (Claude Code issue #34247) — switched to safe Markdown `---` HR
4. Codebase audit showed 0/15 commands included task ID in CTA, 0/15 marked primary action

### Testability

39 bats tests guard against drift:
- Skill file existence + frontmatter
- Every command file references `cta-format.md`
- Every named agent loads the skill
- Routing skill points to cta-format
- Anti-pattern regression (no box-drawing in any command)
- Fixtures invariants (HR wrapping, exactly one primary marker)

### Operating Model Note

Runtime ↔ repo for `agents/`, `skills/`, `commands/`, `templates/` is via symlinks (`$HOME/.claude/skills` → `code/datarim/skills`). Edits in runtime land directly in repo — no `scripts/curate-runtime.sh` step needed for these scopes. `tests/` is repo-only (not symlinked).

### Backwards Compatibility

- Old free-form `## Next Steps` sections fully replaced. Archived reflection docs referencing old format remain immutable (no breaking change to history).
- Pipeline routing logic unchanged — only the output format was reformulated.
- Mode Transition automatic transitions preserved (verified via test in `tests/cta-format.bats` and integration check that all transitions are still listed in `backlog-and-routing.md`).

### Affected by Future Changes

Any future change to the CTA format MUST update `skills/cta-format.md`, regenerate fixtures in `tests/cta-format/fixtures/`, and update this evolution log.

---

## 2026-04-25 — TUNE-0032 — Reflection Class A Proposals (5 applied)

Approved Class A evolution proposals from `reflection/reflection-TUNE-0032.md`. All target framework process improvements identified during the TUNE-0032 cycle.

### Proposal 1+2: Discovery skill — Scope Live-Grep + AC-Feasibility Rules

- **File:** `skills/discovery.md`
- **Class:** A (content addition; no operating-model change)
- **What:** Two new sections inserted before "Codebase-First Rule":
  - **Scope Live-Grep Rule** — when a task touches multiple artefacts of the same kind (commands/agents/skills/templates), grep filesystem for actual count before fixing scope in PRD; do not rely on memory.
  - **AC-Feasibility Rule** — every measurable AC must be reachable under the current operating-model; dry-run each AC against live state before user-approval; reformulate as "X OR documented invariant" when not directly reachable.
- **Why:** TUNE-0032 PRD § Scope said "15 commands" (actual: 17). AC-8 (`check-drift exit 0`) was unreachable under symlink topology — surfaced only in QA. Both should have been caught at PRD draft time.
- **Approved:** human (Pavel), 2026-04-25.

### Proposal 3: Websites/CLAUDE.md — Cross-product site-update checklist

- **File:** `Projects/Websites/CLAUDE.md` § "Шаг 3: Обновить сайт datarim.club"
- **Class:** A (extends existing TUNE-0028 rule)
- **What:** Generalised the per-artefact site-update mapping into an explicit table covering `skills`, `commands`, `agents`, `templates`. Added templates as conditional ("обновить, если папка существует / если template имеет публичную ценность"). Added pre-deploy diff loop:
  ```sh
  for kind in skills commands agents; do
    diff <(ls $HOME/.claude/$kind/*.md | xargs -I{} basename {} .md | sort) \
         <(ls datarim.club/data/$kind/*.php | xargs -I{} basename {} .php | sort)
  done
  ```
- **Why:** TUNE-0028 explicitly required `data/commands/*.php` updates; skills/agents were implicit and templates were unmentioned. TUNE-0032 added `data/skills/cta-format.php` correctly only because the agent generalised by analogy — luck, not rule.
- **Approved:** human (Pavel), 2026-04-25.

### Proposal 4: ai-quality.md — Spec-First with Golden Fixtures pattern

- **File:** `skills/ai-quality.md`
- **Class:** A (content addition — new pattern section)
- **What:** New "Spec-First with Golden Fixtures (Format-Change Pattern)" section before "Fragment Routing". Codifies the 4-step sequence (spec-as-skill → fixtures → spec-regression tests → mechanical propagation) for L3+ tasks changing output format/structure across ≥5 files of the same kind.
- **Why:** TUNE-0032 used Approach C (this pattern); 39 bats tests now guard 17 commands + 5 agents from drift. Approach A (mechanical sweep) was rejected exactly because drift would re-emerge with each new consumer. Pattern deserves codification beyond TUNE-0032.
- **Approved:** human (Pavel), 2026-04-25.

### Proposal 5: dr-archive.md — Pre-commit staged-diff audit

- **File:** `commands/dr-archive.md` Step 0.1
- **Class:** A (refinement of existing mandatory step)
- **What:** Added explicit instruction: after `git add` and before `git commit`, run `git diff --staged --stat` and verify the file list matches commit-message scope; reject and restage if unrelated files appear.
- **Why:** TUNE-0032 archive: 2 INFRA-0026 files (`skills/file-sync-config.md`, `templates/cli-conflict-resolver-prompt.md`) leaked into TUNE-0032 commit `5ac8cd9` despite explicit `git add` path-list. Root cause not pinpointed; staged-diff audit makes leak visible before history is cast in stone.
- **Approved:** human (Pavel), 2026-04-25.

### Class B (HELD)

- **Operating-model revision** — symlink-default `install.sh` + `curate-runtime.sh` deprecation + fork-flow recommendation. Class B (operating-model contract change). Held pending PRD-TUNE-0033 (added to backlog 2026-04-25, P1, L3). Not applied here.

### Follow-Up Tasks Added to Backlog

- **TUNE-0033** — Fork-first install model + symlink default (L3, P1). Added during TUNE-0032 compliance step.
- **TUNE-0034** — Bats test suite cleanup: 10 pre-existing failures (optimizer.md restructure, removed go-to-market.md, reflect-removal sweep whitelist gaps, file-sync-config description >155 chars). L1, P2.
- **TUNE-0035** — Site update cross-product checklist generalisation (folded into Proposal 3 above; backlog entry kept as tracking checkpoint to verify wiring on next site update). L1, P3.
- **TUNE-0036** — `/dr-archive` Step 0.1 staged-diff audit (folded into Proposal 5 above; backlog entry kept as tracking checkpoint). L1, P3.

Items 2-4 are candidates for opportunistic batch (one L1 cleanup pass).

## 2026-05-04 — TUNE-0092 (CI bats wiring)

### Class A Applied

- **`commands/dr-plan.md` § Transition Checkpoint** — added baseline-citation rule: every test-count baseline in a plan ("X/Y tests pass") must cite the branch and HEAD SHA the count was measured on. Source: TUNE-0092 — initial plan captured 281/285 on a feature branch and framed it as the main baseline; the actual main baseline was 160/160 green. Stack-agnostic gate verified clean.

### Class B

None.

### Follow-Up Tasks

None (TUNE-0091's currently-failing tests will surface organically on its PR via the new bats CI gate — desired behaviour, not a follow-up).

## 2026-05-04 — TUNE-0082 (datarim.club skill-page drift sweep)

### Class A Applied

- **`skills/reflecting.md` § Instructions step 8 (FOLLOW-UP TASKS)** — added out-of-scope drift heuristic-scan: scan implementation notes and "What Didn't" section for phrases (`out-of-scope`, `still stale`, `also stale`, `runtime ... lagging`, `symmetric ... drift`, `separate task`, `deferred`, `noted for follow-up`); auto-suggest follow-up backlog entries rather than rely on operator memory. Source: TUNE-0082 spotted runtime `datarim-doctor.md` drift in /dr-do; only safety-net was operator memory at archive time. Stack-agnostic gate: PASS clean. Bats: 160/160 green.

- **(project-scope, not framework runtime)** `Projects/Websites/CLAUDE.md` § Datarim Update Workflow → Scoping warning block — added «Runtime-skill freshness check (TUNE-0082)» paragraph + pre-deploy versioned-marker diff snippet. Site-only sync leaves AI-agent consumers reading stale runtime contracts. Routing: project CLAUDE.md (PHP-specific), not `~/.claude/skills/` → stack-agnostic gate N/A.

### Class B

- **B-1 — Pre-deploy «scope guard» in `deploy.sh`** (carryover from TUNE-0081). Still pending PRD: needs design for «expected scope manifest» vs rsync transfer-list comparison + false-positive handling on mtime-only drift (TUNE-0082 hit md5-identical files surfacing in rsync delta).

### Follow-Up Tasks

- **TUNE-0094** spawned (P3 L1) — runtime `~/.claude/skills/datarim-doctor.md` (= `code/datarim/skills/datarim-doctor.md`) sync to v1.21.3 5-pass + Data-Loss Safety Contract. Symmetric to TUNE-0082's site fix.
---

## TUNE-0090 — Doc-surface drift sweep + framework/consumer boundary fix (v1.21.7)

**Date:** 2026-05-03
**Complexity:** L2
**Outcome:** Three drift findings fixed; new bats regression test added; framework/consumer boundary invariant established; one in-flight scope addition (`skills/security-baseline.md` doc-refs).

### Class A Applied

#### Proposal 1: file-relocation pre-flight grep checklist

- **File:** `skills/evolution/file-relocation-checklist.md` (NEW fragment under existing `skills/evolution/`)
- **Class:** A (skill-update — new fragment)
- **What:** Codifies the pre-flight `grep -rln "$OLD" code/datarim/` check before staging any `git mv` or cross-repo relocation. Ensures relocation + reference-fixup land in the same commit. Cross-repo variant + verification step included.
- **Why:** During `/dr-do`, after relocating `code/datarim/documentation/` (Steps 8-10), `check-doc-refs.sh` flagged 3 dangling refs in `skills/security-baseline.md`. Plan hadn't enumerated the skill as a touch-point. Pre-flight grep would have caught it before commit.
- **Stack-agnostic gate:** PASS (POSIX `grep`, no stack-specific tools).
- **Approved:** human (Pavel), 2026-05-03.

#### Proposal 2: tests/test-command-doc-coverage.bats

- **File:** `code/datarim/tests/test-command-doc-coverage.bats` (already added in `/dr-do` commit `109e75b`)
- **Class:** A (new bats regression test)
- **What:** 4 assertions guarding the gap TUNE-0090 just fixed: every `commands/dr-*.md` is mentioned in `docs/commands.md` AND `CLAUDE.md`; no obsolete `/dr-reflect` or `/dr-security` references; `code/datarim/documentation/` does not exist.
- **Why:** Without a continuous detector, the same drift can reopen silently (as it did for `/dr-doctor`).
- **Stack-agnostic gate:** PASS (bats whitelisted via `skills/testing/bats-and-spec-lint.md`).
- **Approved:** human (Pavel), 2026-05-03.

### Class A Applied (project-specific — outside framework gate scope)

#### Proposal 3: Projects/Datarim/CLAUDE.md § Public-surface ↔ runtime sync

- **File:** `Projects/Datarim/CLAUDE.md` (project-specific config)
- **Class:** A (claude-md-update)
- **What:** New subsection codifying the n-way sync rule when adding a new `commands/`/`skills/`/`agents/` artifact: must propagate to (a) site `data/{kind}/<name>.php`, (b) `code/datarim/docs/{commands,skills,agents}.md` row, (c) `code/datarim/CLAUDE.md` mention, (d) `code/datarim/README.md` mention. References the new bats test as the framework-doc detector.
- **Why:** TUNE-0090 itself was discovered because the site had `data/commands/dr-doctor.php` while framework docs lacked any mention of `/dr-doctor`. Asymmetry-as-drift needs explicit rule.
- **Stack-agnostic gate:** N/A (file is `Projects/Datarim/CLAUDE.md`, project-specific config — gate scope excludes).
- **Approved:** human (Pavel), 2026-05-03.

### Class B (HELD — defer to PRD-TUNE-0091)

- **Doc-fanout linter (general).** Auto-detect missing references on N consumer surfaces when an artifact is added in a commit. Broader than the dr-* bats test. Not auto-spawned; user to add as backlog item if desired.

### Follow-Up Tasks (not auto-spawned)

- **TUNE-0091** — Class B doc-fanout linter (PRD required). Awaiting user confirmation.
- **CI bats wiring for framework repo** — `test-command-doc-coverage.bats` (and the other 10) need CI execution to prevent silent regression. Own discovery scope (which CI? trigger? runner?). Note only.

### In-flight Scope Addition (folded into `/dr-do` framework commit)

- **`skills/security-baseline.md` doc-refs.** 3 references to relocated `documentation/archive/security/findings-2026-04-28.md` updated to workspace path. Required to keep `check-doc-refs.sh` green after relocation. Direct consequence of Step 9 — not a scope expansion. Lesson → Class A 1 (above).

## TUNE-0101 reflection (2026-05-06)

### Class A — Spawned to backlog (NOT applied here, separate /dr-do tasks)

- **TUNE-0110 — `skills/plan-path-validator.md`** (new-skill). Pre-flight exists-check для file-paths в `/dr-plan` output; catches deprecated/missing tooling references. Spawned потому что Plan TUNE-0101 step E4 цитировал deprecated `dev-tools/scripts/check-drift.sh` (DEPRECATED v1.17), не обнаружено до /dr-do.
- **TUNE-0111 — `templates/shell-helper-template.sh`** (new-template). Conventions: `printf '%s\n'` newline-separated output, `while IFS= read -r x; do ... done < <(cmd)` iteration, `LC_ALL=C` scoping для regex. Spawned после двукратного word-splitting bug fix (R2 → R5).

### Class B — Held (PRD required)

- **PRD-revision gate at design pivot during `/dr-do`.** Когда implementation выбирает решение, отличное от PRD (e.g., flock → mkdir-lock platform substitution), агент обязан сделать inline ADR note в PRD § Alternatives Considered ИЛИ обновить PRD до merge. Drift PRD ↔ implementation в TUNE-0101 (flock cited, mkdir-lock implemented) был замечен только в `/dr-qa`. Class B (operating-model change to /dr-do contract). Awaiting PRD draft.

### Decisions Logged (TUNE-0101 implementation)

- **mkdir-lock vs flock substitution** (Round 2). PRD цитирует `flock`; macOS bash не поставляет `flock`. mkdir-based atomic mutex выбран как POSIX cross-platform substitute. Class B follow-up captures the workflow gap.
- **Plan E4 skip** (Round 6). `dev-tools/scripts/check-drift.sh` — deprecated v1.17, удаляется v1.18. Step moot; symlink-mode пользователи не имеют drift по определению.
- **+1 unplanned skill-registry check** (Round 5). Check 9 добавлен поверх 8 plan'ом checks как закрытие Round 4 side-observation про `dr-archive` симптом. Improvement, not scope creep.


---

## TUNE-0137 — Self-Verification v1 (v2.0.0)

**Date:** 2026-05-09
**Complexity:** L3
**Outcome:** v1 tri-layer architecture research + PRD v2 pivot. Phase 1 shipped: `skills/self-verification.md` + `commands/dr-verify.md` + `dev-tools/measure-verify-effectiveness.sh` + `dev-tools/test-self-verification-claude.sh` + `dev-tools/measure-verify-cost.sh`. AC-7 hit-rate 7.7% literal / 15.4% semantic on n=13 known gaps → R-5 KILL_OR_PIVOT triggered. Research dimensions consensus: vanity metric (retrospective recall), not feature failure. PRD v2 pivot to tri-layer (Layer 1 deterministic floor + Layer 2 cross-model peer-review + Layer 3 native dispatch). TUNE-0144 spawned for Phase 2 implementation.

### Class A Applied

- **`skills/self-verification.md` initial draft** — v1 single-pass Codex prompt path, basic findings schema, audit log spec.
- **`commands/dr-verify.md` initial draft** — Layer 3 native dispatch only; `--max-iter`, `--stage` args.
- **`dev-tools/measure-verify-{cost,effectiveness}.sh`** — v1 measurement harness; broken data-source path (`~/.local/share/coworker/log.jsonl` phantom). Deprecated in TUNE-0144.
- **`dev-tools/test-self-verification-claude.sh`** — AC-10 integration test harness (contract validator, not executable test).

### Class B (HELD — addressed in TUNE-0144 / gated tasks)

- **Layer 1 deterministic floor** → TUNE-0144 Phase 2.
- **Layer 2 cross-model peer-review** → TUNE-0144 Phase 2.
- **Post-step hook auto-trigger** → TUNE-0138 (gated on Phase 3-4 dogfood ≥1 per 5 tasks).

---

## TUNE-0144 — Self-Verification v2 tri-layer + tagging schema + token-cost tooling (v2.1.0)

**Date:** 2026-05-10
**Complexity:** L3
**Outcome:** Phase 2 PRD-TUNE-0137 v2 shipped. 6 deliverables: (1) Layer 1 deterministic floor `dev-tools/dr-verify-floor.sh` (340 LoC, shellcheck-clean, JSONL findings with `source_layer: floor`); (2) Layer 2 cross-model peer-review path wired into `commands/dr-verify.md` (`--peer-provider`, `--floor-only`, `--task-id` propagation); (3) `skills/self-verification.md` tri-layer sections + extended findings schema; (4) `dev-tools/measure-invocation-token-cost.sh` (XDG_STATE_HOME, OpenTelemetry dotted-key JSONL, per-task token aggregation); (5) `dev-tools/measure-prospective-rate.sh` (archive frontmatter walker, R-5 v2 decision_hint); (6) `templates/archive-template.md` canonical NEW with `verification_outcome` schema + `commands/dr-archive.md` MANDATORY filling instruction. Public-surface 4-way: `data/commands/dr-verify.php` (EN+RU), `docs/commands.md` row, `README.md` bullet, `code/datarim/CLAUDE.md` tri-layer rewrite. Old `measure-verify-cost.sh` deprecated side-by-side. Version 2.0.0 → 2.1.0 across 6 files.

### Class A Applied

- **`dev-tools/dr-verify-floor.sh`** (NEW) — Layer 1 deterministic floor shell pipeline. Checks: AC coverage grep, file-touched audit, test-presence parse (manifest-agnostic), shellcheck recursive. JSONL output with `source_layer: "floor"`, `check_name`, `severity`. Exit = count of `severity=high` findings.
- **`dev-tools/measure-invocation-token-cost.sh`** (NEW) — per-task coworker token cost aggregator. XDG_STATE_HOME resolution, daily-rotated JSONL, OpenTelemetry dotted-key dict access, provider breakdown.
- **`dev-tools/measure-prospective-rate.sh`** (NEW) — Phase 3 dogfood rate tracker. Walks `documentation/archive/**/archive-*.md`, extracts `verification_outcome` frontmatter, computes `caught_per_5_tasks`. `decision_hint` drives R-5 v2 kill-gate verdict.
- **`templates/archive-template.md`** (NEW canonical) — formal YAML frontmatter schema including closed `verification_outcome` block: `caught_by_verify`, `missed_by_verify`, `false_positive`, `n_a`, `dogfood_window`.
- **`commands/dr-archive.md` Step 2 extension** — MANDATORY `verification_outcome` fill instruction with pointer to template.
- **`code/datarim/CLAUDE.md` § /dr-verify rewrite** — tri-layer description + verification tagging workflow at archive time.
- **`data/commands/dr-verify.php`** (NEW) — public-surface EN+RU page on datarim.club.
- **`dev-tools/measure-verify-cost.sh` deprecation** — DEPRECATED header + stderr warning; side-by-side preserve; data-source path phantom corrected.

### Class B (HELD — gated tasks)

- **Post-step hook auto-trigger (TUNE-0138)** — gated on Phase 3-4 prospective dogfood verdict ≥1 per 5 tasks.
- **Auto-fix policy (TUNE-0140)** — gated on TUNE-0138 ship + FP rate <30%.
- **Cost-adaptive L4 self-degradation (TUNE-0139)** — gated on TUNE-0138 ship.
- **`dev-tools/check-version-consistency.sh`** — mechanical CI enforcer for TUNE-0019 version consistency rule. Optional follow-up backlog item.

### Decisions Logged (TUNE-0144 implementation)

- **D-4 (coworker log truth path):** `~/.local/state/coworker/log/<YYYY-MM-DD>.jsonl` (XDG_STATE_HOME, daily-rotated, OpenTelemetry keys) — NOT `~/.local/share/coworker/log.jsonl` as cited in PRD line 186. PRD edit deferred to TUNE-0137 parent archive.
- **D-5 (archive template phantom):** `templates/archive-template.md` did not exist; created as NEW canonical file.
- **D-6 (measure-prospective-rate.sh):** added as 6th deliverable beyond PRD 5-item roadmap — needed immediately for Phase 3 measurement.
- **D-7 (deprecated side-by-side):** `measure-verify-cost.sh` deprecated in-place; removal deferred 30 days via backlog.

---

## AUTH-0061 — Reflection-driven Class A skill updates (2026-05-10)

**Date:** 2026-05-10
**Source task:** AUTH-0061 (Auth Arcana Phase 2A — admin OIDC clients API + Redis cache + seed CLI). Reflection at `~/arcanada/datarim/reflection/reflection-AUTH-0061.md`.
**Outcome:** Two Class A skill updates accepted by operator and applied to runtime; one Class A project-CLAUDE.md update applied to consumer; one Class B proposal HELD pending PRD update. Stack-agnostic gate `--diff-only`: PASS clean on both runtime files.

### Class A Applied (framework runtime)

- **`skills/testing.md` — Reporting Test Counts in Audit Output (NEW section).** Mandates that QA/Compliance reports derive per-spec test counts via a mechanical extractor of the test-runner's case-declaration syntax (framework-neutral contract; per-language regex examples behind `<!-- gate:example-only -->`). Drift between operator memory and extractor output = finding. Source: a per-spec count off-by-one was caught only by independent re-execution at Compliance; mechanical derivation removes the drift class.
- **`skills/compliance.md` § Software Checklist Step 7 — Stale-base merge-result gate (`git`-only).** Adds an inline rule that before reporting a "regression" from a PR diff vs `origin/<base>`, the auditor MUST check whether the diff is a side-effect of `origin/<base>` advancing past the branch's merge-base (i.e. `git diff <merge-base>..HEAD -- <file>` empty), and if so, simulate the actual 3-way merge via `git merge-tree $(git merge-base HEAD origin/<base>) HEAD origin/<base>` before flagging. Source: a feature PR appeared to revert an upstream baseline-hardening fix that landed mid-flight; merge-tree simulation confirmed the fix was preserved by 3-way merge — a needless rebase cycle was avoided.

### Class A Applied (consumer CLAUDE.md, not framework runtime)

- **`~/arcanada/CLAUDE.md` § Backend Stack Standards — Devdep audit cadence.** Adds a quarterly `pnpm audit --audit-level=moderate` review on top of the existing `--audit-level=high` merge gate; moderate findings either patched or recorded as explicit waivers in the repo's SECURITY.md / `Areas/Credentials` note with reason + revisit date. First sweep due 2026-08-10. **Stack-specific (pnpm) — correctly placed in consumer CLAUDE.md, not framework runtime, per `feedback_datarim_stack_agnostic` memory.** Not part of `code/datarim/{skills,agents,commands,templates}/`.

### Class B (HELD — pending PRD)

- **Auth Arcana seed-CLI default-flip.** Until AUTH-0074 ships (P1 L3 — static OIDC `client_secret_basic` verification path on `/token`), the seed CLI MUST default `tokenEndpointAuthMethod='private_key_jwt'` (or refuse `client_secret_basic` without explicit env opt-in). Today's default ships static clients with an end-to-end-broken `/oidc/token` exchange. Modifies the default contract for shipping OIDC clients in the ecosystem and touches AUTH-0062 sequencing → requires PRD-AUTH-0002 amendment before approval. **HOLD until PRD update lands.**

### Verification

- `task-id-gate.sh` on `skills/testing.md`, `skills/compliance.md`: PASS clean (no task-IDs leaked into runtime artefacts; provenance lives here only).
- `stack-agnostic-gate.sh --diff-only` on both files: PASS clean (no stack-specific terms added to runtime).
- `bats tests/` baseline failures (T11/T12 skills/commands gate-clean, T17 brainstorming description >155, T26 check-drift SCOPES, T325 dr-reflect whitelist) confirmed pre-existing via stash-and-re-run on the canonical repo (Datarim framework); not regressions from this change.

---

## TUNE-0155 — /dr-verify provider auto-resolution + Class A reflection apply (2026-05-10)

**Date:** 2026-05-10
**Source task:** TUNE-0155 (zero-flag UX for /dr-verify Layer 2 peer-review provider). Reflection at `~/arcanada/datarim/reflection/reflection-TUNE-0155.md`. Audit logs at `datarim/qa/verify-TUNE-0155-do-{1,2}.md`. Compliance report at `datarim/reports/compliance-report-TUNE-0155.md`.
**Outcome:** Three Class A skill/command updates applied to runtime; zero Class B proposals (all changes are prompt/rule extensions, no operating-model contract change). Both runtime gates GREEN: stack-agnostic-gate.sh `PASS: clean` on changed files; history-agnostic gate `0 TUNE-* refs added` in diff.

### Class A Applied (framework runtime)

- **`skills/self-verification.md` § Layer 2 — JSONL emission discipline (NEW subsection at ~line 161).** Mandates suppression of PASS-as-finding entries: findings array carries only defects or incorrect-premise items, never «cleared»/«verified»/«no finding» confirmations. Compress confirmations into the final-line summary. Source: across iter 1 + iter 2 deepseek peer-reviewer emitted 8 of 15 raw findings as PASS-as-finding despite explicit prose rule — a structural prompt constraint with concrete correct/incorrect examples is needed.
- **`commands/dr-plan.md` Step 6.5 — Symbol Existence Check extension (PRD AC verification commands).** Adds requirement that every PRD AC `**Verification:**` line is smoke-checked at plan time against the implemented CLI surface (or pre-implementation skeleton). Phantom flags, positional-args invocations against named-flag contracts, and misnamed env vars caught here, not at /dr-verify post-/dr-do. Cost: ~5s per AC; saving: a full pipeline cycle. Source: TUNE-0155 PRD had 6 phantom AC verification commands (`--dry-run` flag, positional args, `dr-verify --dry-run`, `CLAUDE_RUNTIME` env var) discovered only at /dr-verify iter 1.
- **`commands/dr-plan.md` Step 6.5 — AC ↔ V-AC semantic match check.** Adds requirement that Validation Checklist rows verify what the AC actually asserts, not just verbatim mirror the AC number. Failure mode: PRD AC «cost-cap soft enforcement, exit 2 on breach» mirrored by V-AC `for f in ...; test -f $f` (file presence) — verbatim cite of AC, but verification tests something else. Source: TUNE-0155 V-AC-12 ↔ AC-12 mismatch surfaced only at /dr-verify iter 2 reviewer, then patched in /dr-compliance.

### Decisions Locked

- **D-1 (Layer 2 reviewer prompts):** structural rule with concrete examples wins over abstract prose rule. Applied with both correct (suppression) and incorrect (PASS-as-finding) JSONL examples inline.
- **D-2 (combined Step 6.5 extension):** AC verification command smoke + AC↔V-AC semantic match are sibling rules under same Symbol Existence Check umbrella — single docstring expansion preserves locality.
- **D-3 (Class B deferred):** none. All TUNE-0155 reflection proposals are prompt/rule extensions; operating-model contract unchanged.

### Verification

- Stack-agnostic gate: `bash scripts/stack-agnostic-gate.sh skills/self-verification.md` → PASS clean. `bash scripts/stack-agnostic-gate.sh commands/dr-plan.md` → PASS clean.
- History-agnostic gate: `git diff -- skills/self-verification.md commands/dr-plan.md | grep -E '^\+' | grep -cE 'TUNE-[0-9]+'` → 0.
- Provenance lives in this evolution-log entry + archive + git log per Datarim Rule #8.


---

## AUTH-0057 + AUTH-0075 — 5 Class A proposals applied (2026-05-10)

**Date:** 2026-05-10
**Source tasks:** AUTH-0057 (Phase 2A slice 0057a — OIDC interactions API core) + AUTH-0075 (Phase 2A slice 0057b — interactions API hardening). Reflections at `~/arcanada/datarim/reflection/reflection-AUTH-0057.md` and `reflection-AUTH-0075.md`.
**Outcome:** 4 framework-runtime updates + 1 consumer-CLAUDE.md update. Both runtime-runtime gates GREEN: stack-agnostic-gate.sh `PASS: clean` (`--diff-only` mode) on both `skills/testing.md` and `skills/ai-quality.md`. Workspace `~/arcanada/CLAUDE.md` is stack-specific by design (Backend Stack Standards) — gate exempt per `feedback_datarim_stack_agnostic` precedent.

### Class A Applied (framework runtime)

- **`skills/testing.md` § Coverage Instrumenter Blind-Spot Awareness (NEW section).** Merged AUTH-0057 P4.1 (detection: pre-flight discrepancy check at 20pp threshold) with AUTH-0075 P1 (remediation hierarchy: refactor-lift > switch instrumenter > ignore comments). Stack-neutral wording: «raw runtime hooks», «framework-internal pass-through», «framework-instrumented layers» — no `Fastify`/`v8`/`Istanbul`/`vitest`/`NestJS` literal terms. Documents the architectural-improvement rationale for refactor-lift and the «document the decision» discipline at every level of the hierarchy.
  - **File:** `skills/testing.md` (~+22 prose lines inserted before § Reporting Test Counts in Audit Output).
  - **Class:** A.
  - **Source:** AUTH-0057 reflection §4.1 + AUTH-0075 reflection §5 P1 (deduped + merged into single coherent section per evolution-apply procedure).
  - **Stack-agnostic gate:** PASS (mode: `--diff-only`).
  - **Summary:** detection rule + 3-level remediation hierarchy for coverage instrumenter blind spots through framework-internal pass-through code.

- **`skills/ai-quality.md` § RFC 7807 Problem-Details Envelope for Programmatic API Errors (NEW section).** AUTH-0075 P2 applied. Mandates RFC 7807 `application/problem+json` as the ecosystem standard for HTTP error responses on services with programmatic consumers; concentrates mapping in a single global error-mapping seam at the framework boundary; defines frozen title table, typed exception class, 5xx detail discipline, no-per-handler-error-JSON anti-pattern. Stack-neutral wording: «framework's idiomatic global exception filter, error middleware, or top-level handler» — no `NestJS`/`APP_FILTER`/`Fastify`/`Express` literal terms. RFC 7807 itself is a published standard, cited by number.
  - **File:** `skills/ai-quality.md` (~+24 prose lines inserted before § Atomic Multi-Surface Plan Amendment).
  - **Class:** A.
  - **Source:** AUTH-0075 reflection §5 P2.
  - **Stack-agnostic gate:** PASS (mode: `--diff-only`).
  - **Summary:** RFC 7807 envelope as ecosystem standard for HTTP errors on programmatic-consumer services; single global exit-point seam, frozen title table, 5xx detail suppression.

- **`skills/ai-quality.md` § Atomic Multi-Surface Plan Amendment (NEW section).** AUTH-0057 P4.2 applied verbatim per AUTH-0057 archive note (gate PASS, plan-time concept, no stack terms). Mandates atomic update of all parallel artefacts (PRD §2 + plan + task description Implementation Notes + Implementation Steps locus) within the same revision cycle when an AC's location moves mid-implementation. Cross-check via grep across surfaces; ship in same commit/branch push as the code; one operator-approval reference per amendment.
  - **File:** `skills/ai-quality.md` (~+18 prose lines inserted before § Fragment Routing).
  - **Class:** A.
  - **Source:** AUTH-0057 reflection §4.2.
  - **Stack-agnostic gate:** PASS (mode: `--diff-only`).
  - **Summary:** atomic multi-surface AC-amendment protocol — one revision cycle, cross-check after edit, ship-with-code, step-locus precision.

### Class A Applied (consumer CLAUDE.md, not framework runtime)

- **`~/arcanada/CLAUDE.md` § Backend Stack Standards — CSP / security-header decision matrix (narrow-prefix vs ecosystem-wide).** AUTH-0075 P3 applied. Decision rule for new ecosystem services: hand-rolled Fastify `onSend` hook when target is a single URL prefix + ≤6 static headers + no nonce/hash; `@fastify/helmet` (or equivalent middleware package) when ecosystem-wide / multi-prefix / dynamic / >6 headers / collision-with-other-module. Mandates inline prefix-guard-assumption comment in hand-rolled hooks. **Stack-specific by design (Fastify reference) — correctly placed in consumer CLAUDE.md, not framework runtime, per `feedback_datarim_stack_agnostic` memory.** Not part of `code/datarim/{skills,agents,commands,templates}/`.

### Decisions Locked

- **D-1 (P1 ↔ P4.1 dedup):** P4.1 (detection) and P1 (remediation hierarchy) live as a single section in `skills/testing.md` rather than two adjacent sections. Detection without remediation is incomplete; remediation without detection has no trigger. Combined section keeps the rule's full lifecycle in one place. Stack-neutral wording common to both sources is unified; AUTH-0075-specific «refactor-lift superior to instrumenter switch» framing wins because it captures the architectural-improvement rationale that AUTH-0057 wording lacked.
- **D-2 (P3 routing):** P3 (CSP decision matrix) deliberately bypasses the framework runtime and lands in `~/arcanada/CLAUDE.md`. The matrix names `Fastify` and `@fastify/helmet` as concrete artefacts — the rule cannot be useful without those names. Per `feedback_datarim_stack_agnostic`, stack-specific guidance lives in consumer CLAUDE.md, not framework runtime. Workspace CLAUDE.md gate is exempt by precedent (already contains Fastify/Prisma/pnpm references).
- **D-3 (P4 reject):** AUTH-0075 P4 («new skill `rfc7807-error-handling.md`») rejected by AUTH-0075 reflection itself as subset of P2; ai-quality.md is the canonical home for API contract patterns; a separate skill would create duplication. No action taken.

### Verification

- Stack-agnostic gate: `bash scripts/stack-agnostic-gate.sh skills/testing.md --diff-only` → PASS clean. `bash scripts/stack-agnostic-gate.sh skills/ai-quality.md --diff-only` → PASS clean.
- Workspace `~/arcanada/CLAUDE.md` is stack-specific by design — gate not applied (consumer config, not runtime artefact).
- Provenance lives in this evolution-log entry + reflection files + git log.

---

## 2026-05-11 — DEV-1362 Class A applied

### Proposal A1 (skill-update)

- **Target:** `skills/testing/live-smoke-gates.md`
- **What:** Added `Gate 6: UI Trigger → Cross-Datasource Write` — fires when a UI affordance triggers a server-side write to a data store that unit tests do not bind. Mandates live click + post-condition read in the target store, recorded in the QA report.
- **Why:** DEV-1362 round-5 QA — operator surfaced the gap that vitest mock at API boundary + jest mock at repository boundary leaves the click→row path uncovered. Asana-sync manual buttons only verified end-to-end via live DB row read in `bi_aggregate.tbl_asana_sync_runs`.
- **Impact:** Medium — affects any UI-write task across the framework. Generalises beyond Asana-sync to any audit-trail, event-log, or status-column write.

### Proposal A2 (skill-update)

- **Target:** `skills/evolution.md`
- **What:** Added `Pattern: Helper Extends Doctrine — Same-Task Reconcile`. When a runtime helper covers a wider set of conditions than the doctrine that documents it, the same task MUST update the doctrine OR record `narrower-doctrine-intentional` inline next to the helper. `/dr-compliance` Step 3 FAILs Layer 4 when both states co-exist.
- **Why:** DEV-1362 `isAbortError` doctrine looped twice — helper accepted both native + library-specific cancel-marker names, project convention file named only the native one. Doctrine was amended, reverted, re-amended; two QA rounds + one compliance round wasted on the loop.
- **Impact:** Medium — affects future helper-vs-doctrine drift across any project. Reusable for error-name normalizers, MIME-type allowlists, dialect-flag fallbacks, locale-tag aliases, soft-delete predicates, transitional schema shapes.

### Verification

- Stack-agnostic gate: `bash scripts/stack-agnostic-gate.sh --diff-only HEAD skills/testing/live-smoke-gates.md` → PASS clean. `bash scripts/stack-agnostic-gate.sh --diff-only HEAD skills/evolution.md` → PASS clean (after one rewrite: initial draft cited a specific HTTP-client library name, reworded to stack-neutral «library-specific cancel-marker name»).
- Provenance: this evolution-log entry + reflection `~/code/aether/local-env/datarim/reflection/reflection-DEV-1362.md` + git log on the canonical Datarim repo.

---

## 2026-05-11 — TUNE-0165 Class A applied

### Proposal B1 (template-update + command-update)

- **Target:** `templates/prd-template.md` + `commands/dr-prd.md` (Step 5 pre-save gates).
- **What:** Added `ships_in:` derivation rule. PRDs that ship framework / library releases MUST derive `ships_in:` from the canonical version source (`code/datarim/VERSION` or project equivalent) at PRD-draft time. `/dr-prd` Step 5 reads the current version and pre-fills `ships_in: <next-minor-or-patch>`. Manual override requires an inline justification comment. Drift between PRD-declared and actual release version becomes an explicit pre-save gate.
- **Why:** TUNE-0165 PRD shipped with `ships_in: Datarim v1.25.0` while framework was advancing v2.3.0 → v2.4.0; 5 body refs to the stale version drifted with the frontmatter and only surfaced at `/dr-compliance`, requiring an extra patch round.
- **Impact:** Medium — closes a recurring class of «PRD ships-version drift» defects across every framework / plugin / library release PRD.

### Proposal B2 (template-update + command-update)

- **Target:** `templates/prd-template.md` + `commands/dr-prd.md` (Step 5 pre-save gates).
- **What:** Added V-AC path live-validation gate. Every AC / V-AC line that cites a script / binary / spec file / directory MUST be live-validated (`command -v <bin>` / `test -f <path>` / dry-run exit code) before PRD approval. Cites intentionally produced by the plan must be marked `[to-be-created]` inline; everything else without a successful probe blocks save.
- **Why:** TUNE-0165 PRD shipped with 2 phantom-path cites — `tests/test_plugin_dispatch.bats` (real implementation: case in `test_plugin_register.bats`) + `dev-tools/check-version-consistency.sh` (real path: `scripts/version-consistency-check.sh`). Both survived `/dr-qa` and surfaced at `/dr-compliance`. Similar phantom in earlier TUNE-0164 PRD. `[to-be-created]` marker preserves compatibility with PRDs whose plans create new tooling.
- **Impact:** Medium — closes a recurring class of «PRD cites non-existent path» defects across all PRD-time artefacts.

### Verification

- Stack-agnostic gate: `bash scripts/stack-agnostic-gate.sh templates/prd-template.md` → PASS clean. `bash scripts/stack-agnostic-gate.sh commands/dr-prd.md` → PASS clean.
- Bats: `bats tests/` → 402 ok + 5 pre-existing not_ok (T11/T12 skill-scope gate, D5 SCOPES list, skill description >155 chars, dr-reflect whitelist). 0 new regressions — same baseline as before TUNE-0165 archive.
- Provenance: this evolution-log entry + reflection `~/arcanada/datarim/reflection/reflection-TUNE-0165.md` + git log on the canonical Datarim repo.

### Class B Held — Proposal B3 (deferral clause template)

- **Target (planned):** `templates/coverage-deferral-clause.md` + reference in `skills/compliance.md` § Step 4.
- **What:** Standardise «deferred V-AC» waiver template — explicit fields for measured-vs-deferred status, gating dependency (e.g. `INFRA-0137`), follow-up condition, timestamp + operator initials.
- **Why:** TUNE-0165 V-AC-22 (48h soak `false_escalate_rate < 0.15`) deferred to Linux runtime without a structured waiver — opens a class of «deferred-AC forgotten» defects across autonomy / quality-baseline metrics.
- **Class:** B — change in `skills/compliance.md` § Step 4 «Quantitative-threshold AC enforcement» is an operating-model contract change; requires a PRD draft before apply.
- **Status:** HELD. Spawned as backlog item `TUNE-0182` (P2 L2) with PRD draft as the gate.

## 2026-05-12 · TUNE-0185 Phase 4 archive — Class A applied

- **A1 — `feedback_rank1_mandate_canonical_text_split.md`**: rank-1 ecosystem mandates keep canonical rule text in consumer ecosystem `CLAUDE.md`; framework runtime ships only contract surface (yaml policy + loader entry-points + cross-link section). Stack-agnostic gate PASS. Pattern previously applied implicitly across AAL / Auth Arcana / File Sync / Operational Resilience / Documentation Taxonomy mandates — now explicit.
- **A2 — `feedback_yaml_policy_loader_orthogonality.md`**: new policy schemas in shared loader scripts get their own `load_<name>()` entry-point — never merge into the existing unified stream. Different cardinality + semantics make merge a maintenance liability. Smoke = `yq` pipeline + `shellcheck` clean.
- **Stack-agnostic gate**: PASS on both memory entries + reflection doc.
- **Class B (HELD, PRD-gated)**: B1 `/dr-orchestrate` consumer wiring full integration suite (extends TUNE-0187); B2 mandate drift detector automation via GH Actions (extends TUNE-0186).
- **Health-metrics**: 14-task backlog spawn fanout ≥10 target; 3-way cross-correlation INSIGHTS↔mandate↔yaml zero drift at archive time; framework `code/datarim/` repo 4 unpushed commits (operator push gate); workspace shared schema gate FAIL bypassed via `--no-schema-check` (root cause: 12 sibling active tasks + 50+ backlog legacy lines — `/dr-doctor` migration sweep deferred as separate task).
- **Provenance**: `documentation/archive/framework/archive-TUNE-0185.md` + reflection `Projects/Datarim/datarim/reflection/reflection-TUNE-0185.md` + framework commit `d5ef079` (`code/datarim/` repo) + workspace commit `689c210` (`~/arcanada/`).

## 2026-05-13 — TUNE-0202 Step 0.5 reflection (Class A applied)

- **A1 — `code/datarim/.gitignore` += `__pycache__/` + `*.pyc`**: cosmetic residue from any Python-based `dev-tools/*` debug session (importlib spec-load, ad-hoc test) leaked into `git status` as untracked. One-line addition under existing «Node» block, stack-agnostic per the framework's existing Python-runtime assumption. Smoke = `git status --porcelain` clean after `find . -name __pycache__ -type d -delete && rm -rf …`.
- **Stack-agnostic gate**: PASS on `.gitignore` diff (`scripts/stack-agnostic-gate.sh --diff-only .gitignore`).
- **A2 (DEFERRED, not applied this session)**: «portable latency measurement в bats» snippet for `skills/testing.md` — recommend `python3 -c 'import time; time.perf_counter()'` over `date +%s%N` (BSD macOS strips `%N`). Deferred because `skills/testing.md` is mid-flight in a parallel TUNE-0164 evolution-apply session (foreign `M` hunk at archive time); appending now would mix scopes. Surface as a backlog item for next-session apply.
- **Class B (HELD, PRD-gated)**: B1 `/dr-do` phase-completion version-bump gate (re-run `version-consistency-check.sh` inside `/dr-do` when phase touches `VERSION` — catches «claimed updated, actually not» earlier than `/dr-archive`); B2 `/dev/fd/` process-substitution path handling в `check-topic-overlap.py` (silent-skip vs stdin-alias contract decision).
- **Health-metrics**: skills 41, commands 22 + 1 plugin, agents 18 — thresholds not exceeded; `/dr-optimize` not auto-suggested.
- **Provenance**: reflection `Projects/Datarim/datarim/reflection/reflection-TUNE-0202.md` + compliance report `Projects/Datarim/datarim/reports/compliance-report-TUNE-0202.md` + framework commits `f11a2b3` (feat) + `604e12c` (refactor) + `76fb48a` (CLAUDE.md version fix) + site commit `7489123`.
