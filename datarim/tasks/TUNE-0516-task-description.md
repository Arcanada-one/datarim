---
id: TUNE-0516
title: "Codify parallel-orchestration default and immediate status commit"
status: completed
priority: P2
complexity: L2
type: framework
project: Datarim
started: 2026-07-26
parent: null
related: []
prd: null
plan: plans/TUNE-0516-plan.md
---

## Overview

The Datarim framework already enforces three orchestration-hygiene rules
(auto-mode marker namespacing, hard branch-integration block, pre-flight task-claim
reconciliation) but lacks explicit declarative norms for two additional invariants
that agents repeatedly violate: (A) parallel orchestration is the default—each task
gets its own isolated orchestrator session and serialization is never assumed without
proven branch/file overlap—and (B) status changes in tracked operational files must be
committed and pushed immediately, not accumulated uncommitted. This task adds both
invariants as advisory (Class A) rules in the shipped documentation, along with a
lightweight presence-regression test, and fixes a doc-drift in CLAUDE.md about the
auto-mode marker scheme.

## Acceptance Criteria

- [ ] AC-1: A new subsection “Parallel orchestration is the default” exists in
        `skills/datarim-system/backlog-and-routing.md` (near line 165) that states:
        each task runs in its own isolated orchestrator/session; parallel sessions
        are expected and normal; do not serialize or ask operator unless tasks share
        the same branch or same target files; collision handling references the
        existing foreign-hunk safety rule.

- [ ] AC-2: `commands/dr-orchestrate.md` and `commands/dr-auto.md` each contain a
        single cross-link line pointing to the new subsection; no routing logic
        changed.

- [ ] AC-3: An optional example block is present immediately after the new
        subsection, clearly marked “example — adapt to your infrastructure”, showing
        one generic multi-host dispatch pattern with placeholder names only
        (`my-dev-host`, `task-id`) and styled as non-normative.

- [ ] AC-4: A new declarative rule “Persist status changes immediately” exists in
        either `skills/datarim-system/command-and-archive-rules.md` (near the
        existing dirty-tree checks) or `backlog-and-routing.md`, stating that when a
        command flips a task’s status in a tracked operational file, it must commit
        and push that change promptly; includes a one-line rationale and explicitly
        distinguishes that this does not force intermediate WIP commits of in‑progress
        code.

- [ ] AC-5: A bats regression test is added that asserts the new rule text for
        “Persist status changes immediately” is present and that status‑flip guidance
        exists (presence‑assertion only, matching advisory‑rule testing
        conventions).

- [ ] AC-6: In `CLAUDE.md`, the `/dr-auto` description no longer cites the legacy
        single‑file marker `datarim/.auto-mode-active`; it correctly references the
        per‑task `datarim/.auto/<TASK-ID>.mode` scheme per
        `skills/autonomous-mode/SKILL.md:18`.

- [ ] AC-7: All shipped‑surface text (skills/commands/CLAUDE.md) is English‑only
        and contains zero operator‑specific names, real hostnames, IPs, or
        infrastructure literals; verified by grep.

- [ ] AC-8: Lint, bats, and shellcheck suite pass; the final commit is signed and
        pushed; the task is archived following the standard compliance lifecycle.

## Constraints

- Class A only — advisory/declarative rules; no pipeline routing, exit‑code, or
  `eh_decision` changes.
- English‑only in all shipped skill, command, and `CLAUDE.md` text.
- Zero operator‑specific identifiers (no project names, no real infrastructure
  names/IPs). Examples use placeholders and are marked non‑normative.
- Commit‑and‑push the closure of this task immediately to dogfood invariant B.
- All work done in an isolated worktree/branch for TUNE-0516; signed commits for
  framework main.

## Out of Scope

- Re‑implementing the three already‑shipped rules (auto‑mode markers, merge‑block,
  pre‑flight task‑claim reconciliation).
- Changing the orchestrator dispatch or routing logic — the changes are textual
  advisory additions only.
- Adding more than the two invariants described above.
- Any production deploy, public release, or secret rotation.

## Related

- Parent PRD: none
- Sibling tasks: none
- Prior reflection: none

## Implementation Notes

- 2026-07-26: Added a failing six-case bats presence contract before changing shipped prose.
- 2026-07-26: Added both Class A invariants, command cross-links, and the per-task marker correction without changing routing or executable logic.
- Evidence: focused bats 6/6 PASS; `validate.sh` PASS; added-line ASCII and forbidden-literal scans PASS; full bats and CI-equivalent shellcheck continue as QA gates.
