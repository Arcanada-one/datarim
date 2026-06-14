---
name: dr-auto
description: Orchestrate a task to a passing /dr-compliance + reflection (not final archive) by spawning per-stage subagents and summarising their results. Resume a known task from its checkpoint or bootstrap a new one from a brief. Stage-replay allowed. Reversible actions proceed automatically; irreversible actions (production deploys, secret rotation, force-push to main, public messages) still ask the operator.
model: inherit
metadata:
  model_tier: reasoning
current_aal: 2
target_aal: 2
---

# /dr-auto — Autonomous Execution

`/dr-auto` drives a single task from its current status through to a successful `/dr-compliance` + reflection, with reduced operator prompting. It is a **subagent orchestrator**: for each pipeline stage it spawns the matching Datarim agent via the Agent tool (`planner` for plan, `architect` for prd/design, `developer` for do, `reviewer` for qa, `compliance` for compliance), summarises that subagent's returned result, and decides the next stage. It does **not** run the final `/dr-archive` — archival stays an explicit operator step. Stages run under the autonomous-mode flag and skip clarifying questions whose answers can be derived from the existing artefacts, memory, or a quick probe.

**Role:** Orchestrator (spawns and summarises planner / architect / developer / reviewer / compliance subagents per stage; does not itself perform the stage work).

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
   - The marker is removed at the terminal step (successful `/dr-compliance` + reflection, or a hard stop that surrenders control to the operator). If the env var is set without a matching marker, downstream stages treat the session as non-autonomous (fail-safe).

4. **Load the operating rules.** Read the autonomous-mode skill at `${DATARIM_RUNTIME:-$HOME/.claude}/skills/autonomous-mode/SKILL.md`. It defines the decision rules every stage uses: how to handle minor gaps inline, when to walk through the question-suppression checks before prompting the operator, and which actions are always operator-gated regardless of mode.

5. **Dispatch the pipeline as subagents.** For each stage that needs running, spawn the matching agent via the Agent tool, pass it the resolved task state, wait for its result, then summarise that result and decide the next stage. Stage → agent map: prd/design → `architect`, plan → `planner`, do → `developer`, qa → `reviewer`, compliance → `compliance`. The orchestrator itself does not perform stage work — it dispatches, summarises, and routes.
   - **Re-assert the marker before each dispatch.** Before spawning a stage subagent, re-assert the auto-mode marker at its current path: if the file is absent, unparseable, holds a different task ID, or is stale, rewrite it for the current task (mechanics: `${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/auto-mode-marker.sh reassert --root <workspace> --task-id <TASK-ID>`). This is idempotent — a valid current marker is left untouched. Reference the marker by its current path via the helper's `MARKER_RELPATH` constant rather than a hard-coded filename, so the step survives a future marker rename.
   - **Carry the auto-signal in the subagent prompt.** Include an explicit line in every stage subagent's prompt: "You run stage `<stage>` in autonomous mode for `<TASK-ID>`." The spawned subagent activates the autonomous-mode skill from this signal plus the re-asserted marker, without the (un-inherited) environment variable — see `skills/autonomous-mode/SKILL.md` § When this skill is active, Spawned subagents (relaxed activation).
   - **Resume mode:** read the last stage snapshot for the task (via `/dr-next` semantics) and continue from there.
   - **Bootstrap mode:** run the stages in order, applying the complexity routing from the framework's CLAUDE.md: `/dr-init` always runs; prd/design are added for L3+ tasks; plan/do/qa/compliance run as their gates require.
   - **Terminal point:** the pipeline stops after a **successful `/dr-compliance`** (COMPLIANT or COMPLIANT_WITH_NOTES), which now writes the reflection internally (see `commands/dr-compliance.md` Step 8.5). `/dr-auto` does **not** dispatch an archive subagent — archival is left to the operator.
   - **Stage-replay is normal.** Re-entering an already-completed stage (e.g. after a `/dr-qa` or `/dr-compliance` finding routes work back) updates or append-merges the existing stage artefact rather than failing "already done". The same task may pass through the same stage many times across review rounds; treat each pass as an update to that stage's artefact, not a fresh creation.

6. **Stage-level question suppression.** Each stage that supports autonomous mode has its own `## /dr-auto Mode` block. When a stage reaches a point where it would normally ask the operator a question, it first tries to resolve the answer from documentation, a quick re-run of the relevant test or probe, prior memory, or matching patterns in the codebase. Only when none of those work does it actually prompt the operator.

7. **Inline gap closure.** When a stage discovers a small gap that refines an existing acceptance criterion or contract (without changing its meaning), it fixes it in the same cycle and records the change in `datarim/tasks/<TASK-ID>-auto-inline-log.md` with a timestamp, the files touched, the line delta, and a one-sentence rationale. Bigger gaps that change a contract are written as new backlog items, not patched inline.

8. **Operator escalation.** Two cases always come back to the operator, even under `/dr-auto`:
   - The stage's resolution rules above did not produce an unambiguous answer.
   - The action falls into the **always-gated** list (see below).

   When this happens, the stage uses `AskUserQuestion` to prompt the operator, and records the round in the task's init-task append-log via `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh" --decided-by operator --stage <current-stage>`.

9. **Terminal cleanup.** On success (a passing `/dr-compliance` + reflection) or a hard stop:
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

## Stage Snapshot Emission (Mandatory Terminal Step)

At the terminal cleanup step (step 9 above), after emitting the CTA block, the agent MUST perform snapshot emission ([definition](../skills/stage-snapshot-writer/SKILL.md)) per `$HOME/.claude/skills/cta-format/SKILL.md` § Snapshot Emission. Parameters bound for this command:

- `stage`: `auto`
- `command`: `/dr-auto`
- `captured-by`: `agent`
- `recommended-next`: primary CTA option (slash-prefixed `/dr-*` form)

This snapshot overwrites the last delegated sub-stage snapshot — the intended behaviour: it records the autonomous run as the canonical resume point. Fail-closed: on non-zero writer exit, emit a single stderr warning line and continue (V-AC-7 contract). Kill switch `DATARIM_DISABLE_SNAPSHOT=1` is handled inside the library; under the switch the writer is a no-op without warning.

## Related

- Skill: `skills/autonomous-mode/SKILL.md` — the operating rules every stage loads.
- Mandate: `documentation/mandates/autonomous-agents.md` — the source-of-truth rules for autonomous behaviour.
- Commands: `/dr-next` (the underlying mechanism for resume mode), `/dr-orchestrate` (parallel multi-task, complementary).
