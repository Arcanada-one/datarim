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

### EXECUTION HOST

1. Source the resolver: `source "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/lib/execution-host.sh"`.
2. Call `eh_decision <workspace-root> <execution-hosts-map-path>` (default map: `~/.claude/local/config/execution-hosts.yml`).
3. On **off-host** (exit code 10), AUTO-DISPATCH -- do NOT stop and hand the command back for the operator to type. The `required_host` binding IS the operator's standing authorization to run there, and dispatch (spawning a remote tmux session) is a reversible transport action; every irreversible step (prod deploy, secret rotation, force-push, public message) stays hard-gated on the remote agent downstream. Contract:
   a. **RUN vs INSPECT.** Auto-dispatch only when intent is to RUN the task (operator asked to run/execute/go, autonomous-mode marker active, or reached via `/dr-auto`). On INSPECT/read-only intent, do NOT dispatch: proceed locally read-only and surface the dispatch directive as information, not a blocking question.
   b. **Before dispatch, probe for an existing session for this task** on the required host. If one exists and is live: DO NOT relaunch -- attach and monitor. If it exists but is dead/stale: report it and ask before resuming (resuming a partially-done mutating task is not unconditionally reversible). If absent: dispatch.
   c. **Target integrity (fail-closed).** Before the SSH, the target host key MUST match a pinned `known_hosts` entry and the map MUST be the operator-local gitignored file. Host-key mismatch, missing pin, or any probe failure -> STOP and report; NEVER run the stage locally (that violates the binding) and NEVER dispatch to an unverified host. Pass `<TASK-ID>`/`<root>` as single non-evaluated argv elements; the dispatch payload is the bare task-id only -- never forward an autonomy/confirm-suppression flag to the remote.
   d. **Exit 10 has exactly two outcomes: successful remote dispatch, or STOP-and-report.** Local execution of the stage is never an outcome of exit 10 (a corrupted/unreadable map under exit 10 is fail-CLOSED, not fail-open).
   e. **After dispatch/attach, act only as a READ-ONLY MONITOR.** Poll the task runtime status file (`datarim/runtime/<TASK-ID>.status`) and classify the remote pane (`dev-tools/classify-pane.sh`). Wait up to ~90s for the first status write; if none, re-send the bare task-id ONCE into the existing pane and wait once more; still none = FAILED-LAUNCH -> durable local log line + escalate + STOP (never silent re-dispatch). Steady-state supervise; when the remote agent hits a hard-gate, relay the question+options to the operator and pass back their choice as an option index -- NEVER answer a hard-gate yourself and never proceed on silence. Write one identifier-free local audit line per dispatch attempt.
4. On **unconfigured** (exit code 0, binding absent): proceed unchanged (fail-open).
5. On **on-host** (exit code 0, binding present): proceed normally.

Note: the machine-local PreToolUse guard remains the hard floor; this Step-0 check is the cooperative soft layer sharing the same resolver library.


2. **Pick a mode.**
   - If the argument matches a task ID listed in `datarim/tasks.md`, the command is in **resume mode**.
   - Otherwise it is in **bootstrap mode**: the argument is treated as the operator brief for a new task and the pipeline starts at `/dr-init`.

3. **Turn on autonomous mode.**
   - Export `DATARIM_AUTO_MODE=1` for the rest of the session.
   - Write the per-task marker at `datarim/.auto/<TASK-ID>.mode` (collision-safe in a shared workspace) by running the helper — do not hand-write the path:
     ```
     ${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/auto-mode-marker.sh reassert --root <workspace> --task-id <TASK-ID> --space <resolved-space-name>
     ```
     which produces a marker containing:
     ```yaml
     task_id: "<TASK-ID>"
     activated_at: "<ISO 8601 timestamp>"
     activated_by: /dr-auto
     mode: resume | bootstrap
     space: "<resolved-space-name>"
     ```
   - The `space` value is required when the active space cannot be derived
     from the workspace path. An absent or invalid value remains fail-closed.
   - The marker is removed at the terminal step (successful `/dr-compliance` + reflection, or a hard stop that surrenders control to the operator). If the env var is set without a matching marker, downstream stages treat the session as non-autonomous (fail-safe).

4. **Load the operating rules.** Read the autonomous-mode skill at `${DATARIM_RUNTIME:-$HOME/.claude}/skills/autonomous-mode/SKILL.md`. It defines the decision rules every stage uses: how to handle minor gaps inline, when to walk through the question-suppression checks before prompting the operator, and which actions are always operator-gated regardless of mode.

5. **Dispatch the pipeline as subagents.** For each stage that needs running, spawn the matching agent via the Agent tool, pass it the resolved task state, wait for its result, then summarise that result and decide the next stage. Stage → agent map: prd/design → `architect`, plan → `planner`, do → `developer`, qa → `reviewer`, compliance → `compliance`. The orchestrator itself does not perform stage work — it dispatches, summarises, and routes.
   - **Re-assert the marker before each dispatch (mandatory pre-dispatch gate).** Before spawning any stage subagent you MUST run the re-assert helper as the first action of every per-stage dispatch — skipping this step means skipping the dispatch gate:
     ```
     ${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/auto-mode-marker.sh reassert --root <workspace> --task-id <TASK-ID> --space <resolved-space-name>
     ```
     If the marker file (located via the helper's `MARKER_RELPATH` constant — do not hard-code the filename) is absent, unparseable, holds a different task ID, or is stale, the helper rewrites it for the current task. If a valid current marker already exists the call is a no-op. The helper exits 0 when the marker is valid afterward; proceed to spawn the subagent only after exit 0.
   - **Carry the auto-signal in the subagent prompt.** Include an explicit line in every stage subagent's prompt: "You run stage `<stage>` in autonomous mode for `<TASK-ID>`." The spawned subagent activates the autonomous-mode skill from this signal plus the re-asserted marker, without the (un-inherited) environment variable — see `skills/autonomous-mode/SKILL.md` § When this skill is active, Spawned subagents (relaxed activation).
   - **Resume mode:** read the last stage snapshot for the task (via `/dr-next` semantics) and continue from there.
     -   **Description-vs-oneliner consistency probe (MANDATORY before dispatching `/dr-do`).** A reused task ID can leave a stale `datarim/tasks/{TASK-ID}-task-description.md` § Overview describing a different scope than the current `tasks.md` one-liner for that ID. Compare the two before continuing: if § Overview and the one-liner describe materially different work, STOP and flag the mismatch to the operator instead of proceeding into `/dr-do` against the stale description. Precedent: a prior resume incident — § Overview described a landing-page task while the one-liner had been reassigned to a DNS-cutover task; resuming without this check would have run `/dr-do` against the wrong scope.
   - **Bootstrap mode:** run the stages in order, applying the complexity routing from the framework's CLAUDE.md: `/dr-init` always runs; prd/design are added for L3+ tasks; plan/do/qa/compliance run as their gates require.
   - **L1 doc-only fast-path (narrow class).** When the task is classified L1 AND all three conditions hold — (a) the diff touches exactly one documentation file (markdown), (b) the change is small (no structural split, no new sections requiring architectural review), and (c) the change carries no runtime behaviour (no code, no configuration, no migration) — then instead of silently skipping `/dr-qa`, the orchestrator runs a lightweight inline check: style/banlist scan of the added lines plus a cross-reference grep (internal links resolve, no stale references introduced). If both checks pass, write a minimal `qa-stub` artefact (`datarim/qa/qa-stub-{TASK-ID}.md`) recording the checks performed and their outcomes. This stub counts as the QA artefact for this class (see `skills/compliance/SKILL.md` § Documentation Checklist). This fast-path does NOT apply to real code or infrastructure L1 tasks — those keep the normal routing and the full `/dr-qa` stage.
   - **Terminal point:** the pipeline stops after a **successful `/dr-compliance`** (COMPLIANT or COMPLIANT_WITH_NOTES), which now writes the reflection internally (see `commands/dr-compliance.md` Step 8.5). `/dr-auto` does **not** dispatch an archive subagent — archival is left to the operator.
   - **Stage-replay is normal.** Re-entering an already-completed stage (e.g. after a `/dr-qa` or `/dr-compliance` finding routes work back) updates or append-merges the existing stage artefact rather than failing "already done". The same task may pass through the same stage many times across review rounds; treat each pass as an update to that stage's artefact, not a fresh creation.

6. **Stage-level question suppression.** Each stage that supports autonomous mode has its own `## /dr-auto Mode` block. When a stage reaches a point where it would normally ask the operator a question, it first tries to resolve the answer from documentation, a quick re-run of the relevant test or probe, prior memory, or matching patterns in the codebase. Only when none of those work does it actually prompt the operator.

7. **Inline gap closure.** When a stage discovers a small gap that refines an existing acceptance criterion or contract (without changing its meaning), it fixes it in the same cycle and records the change in `datarim/tasks/<TASK-ID>-auto-inline-log.md` with a timestamp, the files touched, the line delta, and a one-sentence rationale. Bigger gaps that change a contract are written as new backlog items, not patched inline.

8. **Operator escalation.** Two cases always come back to the operator, even under `/dr-auto`:
   - The stage's resolution rules above did not produce an unambiguous answer.
   - The action falls into the **always-gated** list (see below).

   When this happens, the stage uses `AskUserQuestion` to prompt the operator, and records the round in the task's init-task append-log via `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh" --decided-by operator --stage <current-stage>`.

9. **Terminal cleanup.** On success (a passing `/dr-compliance` + reflection) or a hard stop:
   - Remove the per-task marker `datarim/.auto/<TASK-ID>.mode` (resolve via `auto-mode-marker.sh resolve --root <workspace> --task-id <TASK-ID>`; also clear the legacy `datarim/.auto-mode-active` if it was written by a hand-run for this task-id).
   - **Surface the compliance outcome before the CTA.** Print one line stating how compliance resolved, so the operator can see it ran rather than inferring it from a bare archive CTA:
     - When the run reached a passing compliance stage, print the verdict the orchestrator already summarised from the `compliance` subagent — e.g. `Compliance: COMPLIANT — ready to archive` or `Compliance: COMPLIANT_WITH_NOTES — ready to archive`.
     - When compliance was skipped by design (a complexity level whose routing has no compliance stage, e.g. L1's init → do → archive), print the skip reason instead — e.g. `Compliance skipped by design at this complexity level`.
     - This line is emitted after the marker is removed and immediately before the call-to-action block below.
   - Emit the standard call-to-action block defined in the cta-format skill.
   - Emit the stage snapshot defined in the cta-format skill (`stage: auto`, `command: /dr-auto`).
   - The operator may explicitly `unset DATARIM_AUTO_MODE` in the shell. Otherwise, the next `/dr-*` invocation will detect that the env var is set but the marker is gone, log a single warning, and continue as a normal (non-autonomous) run.

## Actions that ask the operator

Before asking, call `${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/resolve-space-autonomy.sh gate` with the
canonical action kind and any required discriminator payload. Exit `0` means
execute autonomously; exit `10` means ask the operator; exit `2` means the
policy is invalid and therefore also asks the operator.

The always-gated floor never executes automatically in any space: finance or
legal actions, irreversible database operations without a verified backup,
git-history deletion, force-pushes that drop commits, and Supreme Directive
violations. Other operational actions ask only when the resolved
`autonomy.policy` value is `operator` or the space/policy cannot be resolved.

## When to use it

- A task with a clear brief and well-defined acceptance criteria where the back-and-forth pattern is mostly overhead — typically L1 and L2 backlog items.
- Resuming a task after an interruption. The pipeline replays from the last snapshot rather than starting over.
- Dogfood runs and benchmarks that measure how often the framework actually has to fall back to operator prompts.

## When not to use it

- Exploratory work where the operator's intent is going to be refined as the task progresses.
- High-risk changes to the framework's operating model, where each stage gate is genuinely a decision point that needs the operator present.
- Coordinating work across multiple repositories. Use `/dr-orchestrate` for that — it is built for parallel multi-task execution and `/dr-auto` is not. **Note:** `/dr-orchestrate` command and the autonomy policy floor are core (no plugin required). The **tmux/bot transport runner** is the opt-in plugin — enable it with `/dr-plugin enable <abs-path>/plugins/dr-orchestrate` when you need the pane-driven runner.

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
- Commands: `/dr-next` (the underlying mechanism for resume mode), `/dr-orchestrate` (parallel multi-task, complementary — command is core; the tmux/bot transport runner is the opt-in plugin, enabled via `/dr-plugin enable <abs-path>/plugins/dr-orchestrate`).
