---
task_id: TUNE-0516
artifact: init-task
schema_version: 1
captured_at: 2026-07-26
captured_by: /dr-init
operator: operator
status: canonical
source: /dr-init
---

# TUNE-0516 — Init-Task (canonical operator brief)

> Контракт: оператор может на любом этапе работы дополнять файл; каждый этап
> pipeline ОБЯЗАН сверяться с ним и фиксировать в своём выходе любые
> расхождения.

## Source command

```
/dr-init TUNE-0516
```

## Operator brief (verbatim)

TUNE-0516 · P2 · L2 (Class A — advisory/declarative rules, no pipeline routing change)

TITLE: Codify two orchestration-hygiene invariants missing from shipped Datarim: (A) one-orchestrator-per-task / parallel-is-default / never-serialize, and (B) commit-and-push status immediately, never accumulate uncommitted status flips.

=== CONTEXT (why these two, and ONLY these two) ===
A framework-maintenance reconnaissance confirmed the shipped Datarim already covers three related rules and should NOT be duplicated:
  - per-task auto-mode marker namespacing (skills/autonomous-mode/SKILL.md:18 — datarim/.auto/<TASK-ID>.mode, collision-safe) — DONE
  - hard-block on merge integration->protected branch (CLAUDE.md § S10 + branch-integration-guard hook + security-baseline/SKILL.md:379) — DONE (on execution)
  - pre-flight reconcile of a task's claim against actual code before starting (backlog-and-routing.md:86-100, dr-init.md:132-140 SYMPTOM-FRESHNESS RE-PROBE, research-workflow/SKILL.md:141) — DONE
Only TWO gaps remain. This task closes exactly those two. Do not re-implement C/D/E.

=== GAP A: parallel-is-default, one orchestrator per task, never serialize ===
Symptom this fixes (generalized, NO Arcanada/DEVS/Aether/tailscale/space names in shipped text): an agent acting as orchestrator repeatedly PAUSES to ask the operator "where do I run this / will I collide with the other running session?" and tends to SERIALIZE tasks, when the correct default is: each task gets its own isolated orchestrator session (own working tree + own branch), and parallel sessions are the expected norm — isolated by branch and by file set. No question is warranted unless two tasks genuinely touch the SAME branch or SAME files.

The mechanics already exist but the DECLARATIVE norm does not:
  - dr-init.md:43b already does probe-for-existing-session / attach-don't-relaunch
  - autonomous-mode/SKILL.md:42 already binds dispatch_session per task
  - dr-auto.md:127 already delegates parallel multi-task work to /dr-orchestrate
What is MISSING is a plain invariant an agent can cite so it stops asking. Add it.

SCOPE for A:
  1. Add a short declarative subsection to skills/datarim-system/backlog-and-routing.md (near the existing Variant-B multi-task-awareness block ~line 165) titled e.g. "Parallel orchestration is the default". State, generically:
     - Each task runs in its OWN isolated orchestrator/session (own worktree, own branch).
     - Parallel sessions across tasks are EXPECTED and normal; they are isolated by branch and by file set.
     - Do NOT serialize tasks and do NOT ask the operator "where to run" or "will this collide" UNLESS two tasks share the same branch OR the same target files.
     - Collision handling: only same-branch/same-file overlap requires coordination (reference the existing workspace-discipline rule for foreign-hunk safety).
  2. Cross-link this from commands/dr-orchestrate.md and commands/dr-auto.md (one line each pointing to the new subsection). Do NOT change routing logic.
  3. OPTIONAL example block, EXPLICITLY marked "example — adapt to your infrastructure" (per operator: generic + optional example). Show ONE generic multi-host pattern (e.g. "if your project config declares a remote execution-host, each task dispatches its own remote session") using PLACEHOLDER names only (my-dev-host, task-id) — never real infra. The example must be clearly non-normative.

=== GAP B: commit-and-push status immediately, never accumulate uncommitted status flips ===
Symptom this fixes (generalized): a long-running orchestrator flips task statuses (pending->done etc.) in the working copy of the tracked backlog/tasks file but does NOT commit+push them, accumulating many uncommitted status changes. On a stale clone this is fragile — any checkout/reset loses the progress, and reconciling it later against a moved canon is error-prone. The shipped rules today only REACTIVELY check for a dirty tree at archive/compliance time (command-and-archive-rules.md:112, compliance/SKILL.md:219, dr-archive.md:46). There is no PROACTIVE norm.

SCOPE for B:
  1. Add a short declarative rule (best home: skills/datarim-system/command-and-archive-rules.md near the existing dirty-tree checks, OR backlog-and-routing.md) titled e.g. "Persist status changes immediately". State, generically:
     - When a command flips a task's status in a TRACKED operational file (backlog / tasks / activeContext), commit AND push that change promptly — do not accumulate uncommitted status flips across many tasks.
     - Rationale (one line): uncommitted progress is not canonical progress; a stale-clone checkout or a moved upstream can lose it, forcing risky manual reconciliation.
     - Applies to status-flip writes specifically; it does NOT force intermediate WIP commits of in-progress code (keep that distinction explicit so users with normal feature-branch flows are not disrupted).
  2. Add a bats regression asserting the new rule text is present and that status-flip guidance exists (light-touch — this is doc/skill guidance, Class A; a presence-assertion test is sufficient, matching how similar advisory rules are tested).

=== HARD CONSTRAINTS (shipped-surface hygiene) ===
  - ENGLISH-ONLY. Zero non-ASCII in any shipped skill/command/CLAUDE.md text (Datarim is public OSS).
  - Zero operator-specific names: no Arcanada, DEVS, dev-ai, Aether, tailscale, space.yml literals, no real hostnames/IPs. All examples use placeholders and are marked non-normative.
  - Class A: advisory/declarative only. Do NOT alter pipeline routing, exit codes, or eh_decision logic.
  - Full Datarim lifecycle on this task itself: /dr-init -> /dr-plan (L2, no PRD needed) -> /dr-do -> /dr-qa -> /dr-compliance -> /dr-archive.
  - Own worktree + own branch. Signed commits for framework main. Commit+push the CLOSE of this task immediately (dogfood rule B). Autonomous per operator; hard-gate only on production deploy / public release / secret rotation (none expected here).
  - Also fix the noted doc-drift: CLAUDE.md's /dr-auto description still cites the legacy single-file marker datarim/.auto-mode-active — update it to the per-task datarim/.auto/<TASK-ID>.mode scheme to match skills/autonomous-mode/SKILL.md:18. (Small, in-scope, no test needed beyond presence.)

DoD:
  - New subsection A present + cross-linked from dr-orchestrate/dr-auto; optional example clearly marked non-normative.
  - New rule B present + bats presence-assertion green.
  - CLAUDE.md /dr-auto marker doc-drift fixed.
  - All shipped-surface English-only, zero operator-specific literals (grep-verify).
  - Full lint/bats/shellcheck gate green; signed commit pushed to framework main; task archived.

## Append-log (operator amendments)

> Дополнения добавляются хронологически; каждое — отдельная подпись.
> Агенты должны читать **весь** append-log, не только верхний блок.

_(пусто на момент создания)_