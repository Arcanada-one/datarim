# Orchestration Hygiene Invariants Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two advisory orchestration-hygiene invariants, their cross-links and regression coverage, and correct the documented per-task auto-mode marker.

**Architecture:** Keep both norms in the existing `datarim-system` policy fragments and link commands to the canonical rule instead of duplicating it. A standalone bats contract test protects the shipped prose while leaving routing and executable behavior unchanged.

**Tech Stack:** Markdown, Bash, bats-core, existing Datarim validation scripts.

---

## 1. Security Summary

- **Attack surface:** Shipped agent instructions can influence orchestration and git behavior.
- **Risks:** Accidental routing changes, infrastructure-specific literals, task-ID provenance, non-ASCII text, or wording that incorrectly forces WIP commits.
- **Controls:** Class A prose-only edits, a presence-contract test, ASCII and forbidden-literal scans, task-ID gate, diff review, and existing full validation gates.

## 2. Architecture Impact

No runtime component, API, database, configuration schema, exit code, or dispatch decision changes. The canonical rules live in:

- `skills/datarim-system/backlog-and-routing.md` for cross-task scheduling.
- `skills/datarim-system/command-and-archive-rules.md` for tracked operational status persistence.

`commands/dr-orchestrate.md` and `commands/dr-auto.md` receive one cross-link each. `CLAUDE.md` receives only the marker correction. The live path probe found all five edit targets tracked at `HEAD`; the new test path is `tests/tune-0516-orchestration-hygiene.bats`.

## 3. Detailed Design

### 3.1 Parallel orchestration

Add `### Parallel orchestration is the default` immediately after the existing multi-task-awareness section. State that each task owns an isolated session, worktree, and branch; parallel work is expected; serialization or operator collision questions are warranted only for same-branch or same-target-file overlap; and foreign-hunk safety follows workspace discipline. Add a clearly non-normative placeholder example using `my-dev-host` and `task-id`.

### 3.2 Immediate status persistence

Add `## Persist status changes immediately` near the existing critical archive rules. Require prompt commit and push after a status flip in tracked backlog, tasks, or active-context files. Explain that uncommitted progress is not canonical and can be lost on a stale-clone checkout or moved upstream. Explicitly exclude intermediate WIP code.

### 3.3 Contract coverage

Create a bats file with separate assertions for the parallel rule, both command cross-links, immediate persistence wording including commit/push and WIP distinction, and the corrected per-task marker. Tests inspect files only and do not execute routing.

## 4. Security Design

| Threat | Control | Verification |
|---|---|---|
| Instruction injection through machine-specific examples | Placeholder-only, explicitly non-normative example | Forbidden-literal grep |
| Behavioral scope creep | No scripts or decision logic modified | `git diff` path/content review |
| Public-surface encoding drift | ASCII-only additions/edits | byte-class grep over changed shipped files |
| Historical provenance leakage | No task ID in shipped rule bodies | `scripts/task-id-gate.sh` |
| False requirement to commit unfinished code | Explicit status-only boundary | bats presence assertion |

Appendix A mapping: S1 uses literal file reads and quoted shell arguments; S2 has no new input surface; S3 forbids secrets/operator literals; S4-S9 are unchanged because this task adds no runtime behavior, dependency, network, auth, or data path.

## 5. Implementation Steps

### Task 1: Add the failing contract test

**Files:**
- Create: `tests/tune-0516-orchestration-hygiene.bats`

- [ ] Add presence assertions for every required rule, cross-link, status-only distinction, and marker correction.
- [ ] Run `bats tests/tune-0516-orchestration-hygiene.bats` and confirm it fails against the pre-implementation prose.

Verifies: V-AC-1, V-AC-2, V-AC-3, V-AC-4, V-AC-5

### Task 2: Add the two canonical advisory rules

**Files:**
- Modify: `skills/datarim-system/backlog-and-routing.md`
- Modify: `skills/datarim-system/command-and-archive-rules.md`

- [ ] Add the parallel-orchestration subsection and non-normative placeholder example.
- [ ] Add the immediate status-persistence subsection with rationale and WIP boundary.

Verifies: V-AC-1, V-AC-3

### Task 3: Add command cross-links and correct marker drift

**Files:**
- Modify: `commands/dr-orchestrate.md`
- Modify: `commands/dr-auto.md`
- Modify: `CLAUDE.md`

- [ ] Add one canonical-rule cross-link in each command without changing routing.
- [ ] Replace the legacy marker in the `/dr-auto` table row with `datarim/.auto/<TASK-ID>.mode`.

Verifies: V-AC-2, V-AC-4

### Task 4: Verify and persist

- [ ] Run the focused bats test and confirm PASS.
- [ ] Run ASCII, forbidden-literal, task-ID, diff, lint, bats, and shellcheck gates.
- [ ] Update implementation evidence and expectations, then sign, commit, and push the implementation checkpoint.

Verifies: V-AC-5, V-AC-6, V-AC-7

## 6. Test Plan

1. Red/green: `bats tests/tune-0516-orchestration-hygiene.bats`.
2. Formatting: `git diff --check`.
3. Public-surface ASCII: scan only changed shipped files for bytes outside `\x00-\x7F`.
4. Operator neutrality: scan changed shipped files for every literal prohibited by the brief.
5. History agnosticism: run `scripts/task-id-gate.sh` on changed shipped files.
6. Full repository gates: `./validate.sh`, `bats tests`, and the repository shellcheck command discovered from CI/validation scripts.

## 7. Rollback Strategy

All targets are tracked. Before integration, revert the task commits with `git revert <commit>` and push the branch. After integration, revert the merge or individual signed commits. No migration, state repair, or deployment rollback is required.

## 8. Validation Checklist

- [ ] V-AC-1: `skills/datarim-system/backlog-and-routing.md` contains the canonical parallel-default rule, collision exception, workspace-discipline reference, and non-normative placeholder example.
- [ ] V-AC-2: `commands/dr-orchestrate.md` and `commands/dr-auto.md` each link to that canonical subsection.
- [ ] V-AC-3: `skills/datarim-system/command-and-archive-rules.md` contains prompt commit-and-push guidance, rationale, and the status-only/WIP distinction.
- [ ] V-AC-4: `CLAUDE.md` documents `datarim/.auto/<TASK-ID>.mode` and no longer uses the legacy marker in the `/dr-auto` description.
- [ ] V-AC-5: `tests/tune-0516-orchestration-hygiene.bats` exists and passes.
- [ ] V-AC-6: Changed shipped files are ASCII-only, contain none of the prohibited operator literals, and carry no task-ID provenance.
- [ ] V-AC-7: `./validate.sh`, full bats, and shellcheck gates pass with no new failures.

Runtime-body probe: clean by design, with no task-ID provenance prescribed; five tracked edit paths are present, one new bats path is planned, and zero deprecated target paths were found. Install-topology survey is not applicable because no path-resolution canon is introduced.

## 9. Next Steps

Execute inline with `executing-plans`, beginning with the failing bats contract and continuing through the full verification checklist.
