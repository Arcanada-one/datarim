---
name: dr-auto
description: Run a task end-to-end with minimal operator interruption. Either resume a known task from its last checkpoint, or kick off a fresh task from a free-text brief. Reversible actions proceed automatically; irreversible actions (production deploys, secret rotation, force-push to main, public messages) still ask the operator.
model: inherit
metadata:
  model_tier: reasoning
current_aal: 2
target_aal: 2
---

# /dr-auto — Autonomous Execution

`/dr-auto` runs the full Datarim pipeline on a single task with reduced operator prompting. It is a thin orchestrator: it decides whether to resume or bootstrap, sets an autonomous-mode flag, and then delegates each stage to its existing command (`/dr-init`, `/dr-prd`, `/dr-plan`, `/dr-do`, `/dr-qa`, `/dr-compliance`, `/dr-archive`). Stages see the flag and skip clarifying questions whose answers can be derived from the existing artefacts, memory, or a quick probe.

**Role:** Adaptive (planner / architect / developer / reviewer / compliance — whichever the dispatched stage requires).

## Usage

```
/dr-auto <TASK-ID>           # Resume an existing task from its last checkpoint.
/dr-auto "<free-text brief>" # Bootstrap a brand-new task (runs /dr-init first).
```

`TASK-ID` is matched by the pattern `^[A-Z]{2,10}-[0-9]{4}$` — two to ten upper-case letters, a hyphen, then four digits. Anything else is treated as a free-text brief for a new task.

## What happens, step by step

1. **Resolve the workspace.** Walk up from the current directory to find the `datarim/` workflow-state folder. If none is found, stop and tell the operator to run `/dr-init` — autonomous mode does not create state directories.

2. **Pick a mode.**
   - If the argument matches a task ID listed in `datarim/tasks.md`, the command is in **resume mode**.
   - Otherwise it is in **bootstrap mode**: the argument is treated as the operator brief for a new task and the pipeline starts at `/dr-init`.

3. **Turn on autonomous mode.**
   - Export `DATARIM_AUTO_MODE=1` for the rest of the session.
   - Write a marker file at `datarim/.auto-mode-active` containing:
     ```yaml
     task_id: "<TASK-ID>"
     activated_at: "<ISO 8601 timestamp>"
     activated_by: /dr-auto
     mode: resume | bootstrap
     ```
   - The marker is removed at the terminal step (successful archive, or a hard stop that surrenders control to the operator). If the env var is set without a matching marker, downstream stages treat the session as non-autonomous (fail-safe).

4. **Load the operating rules.** Read the autonomous-mode skill at `${DATARIM_RUNTIME:-$HOME/.claude}/skills/autonomous-mode/SKILL.md`. It defines the decision rules every stage uses: how to handle minor gaps inline, when to walk through the question-suppression checks before prompting the operator, and which actions are always operator-gated regardless of mode.

5. **Dispatch the pipeline.**
   - **Resume mode:** read the last stage snapshot for the task (via `/dr-next` semantics) and continue from there to `/dr-archive`.
   - **Bootstrap mode:** run the stages in order, applying the complexity routing from the framework's CLAUDE.md: `/dr-init` always runs; `/dr-prd` and `/dr-design` are added for L3+ tasks; `/dr-plan`, `/dr-do`, `/dr-qa`, `/dr-compliance`, `/dr-archive` run as their gates require.

6. **Stage-level question suppression.** Each stage that supports autonomous mode has its own `## /dr-auto Mode` block. When a stage reaches a point where it would normally ask the operator a question, it first tries to resolve the answer from documentation, a quick re-run of the relevant test or probe, prior memory, or matching patterns in the codebase. Only when none of those work does it actually prompt the operator.

7. **Inline gap closure.** When a stage discovers a small gap that refines an existing acceptance criterion or contract (without changing its meaning), it fixes it in the same cycle and records the change in `datarim/tasks/<TASK-ID>-auto-inline-log.md` with a timestamp, the files touched, the line delta, and a one-sentence rationale. Bigger gaps that change a contract are written as new backlog items, not patched inline.

8. **Operator escalation.** Two cases always come back to the operator, even under `/dr-auto`:
   - The stage's resolution rules above did not produce an unambiguous answer.
   - The action falls into the **always-gated** list (see below).

   When this happens, the stage uses `AskUserQuestion` to prompt the operator, and records the round in the task's init-task append-log via `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh" --decided-by operator --stage <current-stage>`.

9. **Terminal cleanup.** On success or a hard stop:
   - Remove `datarim/.auto-mode-active`.
   - Emit the standard call-to-action block defined in the cta-format skill.
   - Emit the stage snapshot defined in the cta-format skill (`stage: auto`, `command: /dr-auto`).
   - The operator may explicitly `unset DATARIM_AUTO_MODE` in the shell. Otherwise, the next `/dr-*` invocation will detect that the env var is set but the marker is gone, log a single warning, and continue as a normal (non-autonomous) run.

## Actions that always ask the operator

Even under `/dr-auto`, the following actions never run automatically. They come from `documentation/mandates/autonomous-agents.md`; the autonomous-mode skill has the canonical, runtime-readable copy.

- Production deploys (any production environment).
- Secret rotation: Vault keys, OAuth tokens, API keys, signing keys.
- Irreversible database operations: `DROP`, `TRUNCATE`, schema migrations without a backup.
- Public communications: posts to Telegram channels, blogs, social media, or any operator-fronting channel.
- Finance or legal actions.
- Force-push to `main` or `master`.
- Deletion of git history (force-push that drops commits, `git reflog expire --expire=now`, `gc --prune=now`).
- Actions that affect more than one human user (mass emails, broadcast notifications).
- Cross-project boundary writes: edits to a repository whose task-prefix is not the current task's project.

## When to use it

- A task with a clear brief and well-defined acceptance criteria where the back-and-forth pattern is mostly overhead — typically L1 and L2 backlog items.
- Resuming a task after an interruption. The pipeline replays from the last snapshot rather than starting over.
- Dogfood runs and benchmarks that measure how often the framework actually has to fall back to operator prompts.

## When not to use it

- Exploratory work where the operator's intent is going to be refined as the task progresses.
- High-risk changes to the framework's operating model, where each stage gate is genuinely a decision point that needs the operator present.
- Coordinating work across multiple repositories. Use `/dr-orchestrate` for that — it is built for parallel multi-task execution and `/dr-auto` is not.

## Related

- Skill: `skills/autonomous-mode/SKILL.md` — the operating rules every stage loads.
- Mandate: `documentation/mandates/autonomous-agents.md` — the source-of-truth rules for autonomous behaviour.
- Commands: `/dr-next` (the underlying mechanism for resume mode), `/dr-orchestrate` (parallel multi-task, complementary).
