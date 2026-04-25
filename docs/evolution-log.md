# Evolution Log

Append-only log of framework changes accepted from `/dr-archive` Step 0.5 reflection or curated runtime → repo updates.

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
