# Evolution Log

Append-only log of framework changes accepted from `/dr-archive` Step 0.5 reflection or curated runtime → repo updates.

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
