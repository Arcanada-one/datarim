# Evolution Log

Append-only log of framework changes accepted from `/dr-archive` Step 0.5 reflection or curated runtime → repo updates.

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
- **TUNE-0034** — Bats test suite cleanup: 10 pre-existing failures (optimizer.md restructure, removed go-to-market.md, dr-reflect references, file-sync-config description >155 chars). L1, P2.
- **TUNE-0035** — Site update cross-product checklist generalisation (folded into Proposal 3 above; backlog entry kept as tracking checkpoint to verify wiring on next site update). L1, P3.
- **TUNE-0036** — `/dr-archive` Step 0.1 staged-diff audit (folded into Proposal 5 above; backlog entry kept as tracking checkpoint). L1, P3.

Items 2-4 are candidates for opportunistic batch (one L1 cleanup pass).
