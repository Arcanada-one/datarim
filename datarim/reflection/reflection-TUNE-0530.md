---
task_id: TUNE-0530
artifact: reflection
captured_at: 2026-07-29
captured_by: /dr-compliance
status: canonical
reflection_basis: 267b5e35e9f21fc7
---

# Reflection — TUNE-0530

## What worked

1. **Fable 5 consilium caught design gaps that survived PRD review.** The panel surfaced 15 concrete design decisions (D-1 through D-15) that the original Approach C did not address: Security posture as mandatory factor, Escape velocity, trigger classifier default catch-all, concrete Return-to-Source escape sequence, candidate ordering separation from recommendation, licence/cost split. Each of these would have been a future defect if shipped without consilium review. **Pattern to keep:** L3+ framework changes that touch a decision surface loaded by ≥3 agents should run a multi-model consilium before implementation.

2. **The "Starting Points & Alternatives" table format is simpler than expected.** The three-column format (Default Recommendation | Viable Alternatives | When to Reconsider) required no new mechanism to parse — it's just a markdown table. Agents read it naturally. The complexity is in the proposal template (10 factors), not the table. **Lesson:** the table change alone (Strategist's MVP) addresses 80% of the defect; the proposal mechanism addresses the remaining 20%.

3. **Bats tests for markdown structure work well.** The 10 bats tests (T1-T10) are deterministic, fast (<1s total), and caught a real issue during development (T1 initially failed because the old "Required Stack" heading was still present in the first draft). **Pattern to keep:** structural bats tests for shipped markdown skills.

## What could be better

1. **Spec-graph Covers-line format friction.** The PRD's V-ACs used `**Covers:** D-REQ-X` (bold inline) but the gate expects `Covers: D-REQ-X` (plain, separate line). This format mismatch produces 10 advisory warnings at every pipeline stage. The format was corrected mid-pipeline but the gate cache may not have reflected it. **Evolution proposal:** either (a) document the exact format in the PRD template's V-AC authoring instructions, or (b) make the gate tolerant of bold `**Covers:**` inline format. Class A.

2. **Worktree removal lost the expectations QA transitions on first pass.** The expectations file was edited during `/dr-qa` in the merged main repo, but the initial edits were in the worktree (which was removed after merge). The QA status transitions had to be re-applied. **Lesson:** stage snapshot artefacts should survive worktree removal — the expectations file is already committed as part of the PR, so post-merge QA edits happen in the canonical repo. This was operator error (worktree removal before QA), not a framework defect.

3. **Provenance gate blocks on pre-existing untracked directories.** The `skills/fleet/_test_no_budget/` directory (not from TUNE-0530) caused the provenance gate to fail throughout the pipeline. The gate's "clean working tree" requirement is correct in principle but over-broad — an untracked directory unrelated to the current task should not block certification. **Evolution proposal:** provenance gate should accept `--exclude-untracked <path>` or auto-exclude paths not touched by the current task. Class B (operating-model change to the gate contract).

## Evolution proposals

### Class A (operator approval needed)

1. **Document V-AC Covers-line format in PRD template.** Add a comment in `${DATARIM_RUNTIME:-$HOME/.claude}/templates/prd-template.md` showing the exact expected format: `Covers: D-REQ-N` on a separate line (not bold, not inline). This prevents the 10-warning class from recurring.

2. **Extend bats tests for shipped skills to include "no prescriptive MANDATORY" as a standard check.** The T3 test pattern ("no prescriptive MANDATORY language") is reusable for any skill that ships guidance. Consider adding a reusable bats helper that checks a shipped skill for anti-choice language patterns.

### Class B (hold for PRD update)

3. **Provenance gate: add `--exclude-untracked` flag.** The gate's clean-tree check should accept exclusion of untracked paths that are not touched by the current task. This is an operating-model change to the gate contract and needs a dedicated TUNE task with its own PRD.

## Follow-up tasks

1. **TUNE-0532: Add domain-specific security guidance for new tech-stack domains.** The five new domains (CLI, Desktop, Systems, Data/ML, WASM) were added without equivalent security hardening checklists. Each domain needs ≥1 page of security guidance in `skills/tech-stack/` (e.g., `tauri-security.md`, `go-cli-security.md`, `wasm-sandbox.md`). Priority: P2. Source: Security Agent's consilium condition #4 + compliance report remaining risk #1.

2. **TUNE-0533: Monitor toolchain reform effectiveness.** If the "Recommended Toolchains" section (renamed from "Mandatory Toolchains") proves to be the same rigid-default problem at smaller scale, spawn a follow-up for a lightweight toolchain-choice mechanism. Trigger: 3+ instances of agents treating toolchain recommendations as mandatory despite the rename. Source: Architect's dissent (recorded in creative doc D-12).

## Health metrics

- **Pipeline stages completed:** 5/5 (init, prd, plan, design, do) + qa + compliance
- **Consilium panel size:** 5 agents (architect, strategist, planner, security, developer) on Fable 5
- **Design decisions:** 15 (D-1 through D-15)
- **Dissents recorded:** 3 (architect on toolchains, strategist on immutability + mechanism scope)
- **Bats tests:** 10/10 pass
- **CI security gates:** 10/10 pass
- **Expectations:** 5/5 met
- **PR:** #264, merged to main (squash)
- **Files changed:** 17 (1541+ insertions, 124 deletions in runtime; additional workflow artefacts)
- **VERSION:** 2.58.0 → 2.59.0
