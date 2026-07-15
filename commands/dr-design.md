---
name: dr-design
description: Explore architectural and design decisions for complex features (Level 3-4)
---

# /dr-design - Architecture & Design Mode

**Role**: Architect Agent
**Source**: `$HOME/.claude/agents/architect.md`

## Instructions


**Stage Header (mandatory)**: Emit `**{TASK-ID} · {title}**` as the first line of your response, before any tool-call narration. The title is the verbatim one-liner field from `tasks.md` (between `L{N} · ` and ` → tasks/`). Skip this header only for `/dr-help`, `/dr-status`, `/dr-doctor`, and `/dr-init` Steps 1-3 (which emit it immediately after Step 4). See `$HOME/.claude/skills/cta-format/SKILL.md` § Stage Header.
1.  **LOAD**: Read `$HOME/.claude/agents/architect.md` and adopt that persona.
2.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system/SKILL.md` § Path Resolution Rule.

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

3.  **CONTEXT**: Read `datarim/tasks.md` and `datarim/systemPatterns.md`. Additionally, read `datarim/tasks/{TASK-ID}-init-task.md` if present (mandatory per `$HOME/.claude/skills/init-task-persistence/SKILL.md`): the verbatim operator brief + every append-log block. Any divergence between the operator's stated intent and the design proposals MUST be recorded in each creative doc's § Decisions. Missing init-task is non-blocking — flag as advisory and continue.

4.  **DETERMINE DESIGN TYPE**: Classify each component needing design into one of these types:

    | Type | When | Key Activities |
    |------|------|----------------|
    | **UI/UX Design** | User-facing interfaces, layouts, flows | User flow analysis, component hierarchy, interaction patterns, visual principles |
    | **Architecture Design** | System structure, component organization | Component structure, data flow, interface design, system integration, diagrams |
    | **Data Model Design** | Database schemas, entity relationships | Entity relationships, schema design, validation rules, query optimization |
    | **Algorithm Design** | Complex logic, processing pipelines | Complexity analysis, efficiency optimization, edge case handling, scaling |

5.  **FOR EACH COMPONENT** — execute the creative phase:
    - **Define problem** clearly and specifically.
    - **Explore 3+ options** with different approaches.
    - **Analyze tradeoffs** — pros, cons, complexity, effort for each option.
    - **Make decision** with clear rationale. If the decision only takes observable effect after a deploy/cutover (not merely after the code merges), mark it explicitly in the § Decision subsection — e.g. `**Deploy-gated:** yes — takes effect after <deploy step>` — so `/dr-plan` can cross-reference it via a `[deploy-gated — see creative-{TASK-ID}.md § Decision]` annotation on the dependent Implementation Step(s).
    - **Document implementation plan** — specific steps to realize the decision.
    - **Visualize** — include diagrams (mermaid) where helpful.
    - **Apply quality rules**: #6 Corner Cases, #7 Skeleton, #9 Cognitive Load, #13 Transactions (see `ai-quality.md` § Stage-Rule Mapping).

6.  **CREATE DOCUMENT**: `datarim/creative/creative-[task_id]-[type]-[name].md`
    - Format: Problem → Options (3+) → Pros/Cons → Decision → Implementation Plan → Visualization

7.  **CONSILIUM** (for L3-4 tasks):
    - Load `$HOME/.claude/skills/consilium/SKILL.md`.
    - Assemble relevant agent panel based on the design question.
    - Run pipeline: SCOPE -> ASSEMBLE -> ANALYZE -> DEBATE -> CONVERGE -> DELIVER.
    - Include conflict resolution via Priority Ladder.
    - Output includes Failure Mode Table.
    - **Waiver:** If one option clearly dominates all others across every tradeoff dimension, Consilium may be waived. Record: "Consilium waived — Option X dominates (see tradeoff table)" in the creative document. Include a Failure Mode Table regardless (lightweight version acceptable).

7.5. **APPEND Q&A IF ANY** (mandatory per `$HOME/.claude/skills/init-task-persistence/SKILL.md` § Q&A round-trip contract): for every operator clarification round captured during design exploration — either operator answer or autonomous agent-decision under FB-1..FB-5 — invoke `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh"` to persist the round into `datarim/tasks/{TASK-ID}-init-task.md § Append-log`.
    -   Write the question, answer, and rationale (when applicable) to temp files first; free-form text MUST come via `--*-file <path>` per Security Mandate § S1.
    -   Required flags: `--root <repo-root> --task {TASK-ID} --stage design --round <N> --question-file <path> --answer-file <path> --decided-by <operator|agent> --summary "<one-line>"`.
    -   When `--decided-by agent`: `--rationale-file <path>` MUST contain ≥ 50 non-whitespace characters citing the architectural basis of the choice.
    -   On contradiction with an existing expectation or PRD scope: add `--conflict-with <wish_id>`; CTA MUST route back to `/dr-prd` to revise discovery before the design is consumed by `/dr-do`.
    -   Skip if no clarification rounds occurred.

8.  **OUTPUT**: New creative docs + `tasks.md` update. For L3-4 tasks, output also includes consilium panel summary, key debates, resolutions, and Failure Mode Table.

## Transition Checkpoint

Before proceeding to `/dr-do`:
```
[ ] Problem clearly defined for each component?
[ ] 3+ options analyzed with tradeoffs?
[ ] Decision made with documented rationale?
[ ] Implementation plan included?
[ ] tasks.md updated with design decisions?
```

## Next Steps (CTA)

After design phase, the architect agent MUST emit a CTA block ([definition](../skills/cta-format/SKILL.md)) per `$HOME/.claude/skills/cta-format/SKILL.md`.

**Routing logic for `/dr-design`:**

- All design checks pass → primary `/dr-do {TASK-ID}` (begin TDD implementation)
- Missing items in design → primary `/dr-design {TASK-ID}` (continue) + alternative `/dr-prd {TASK-ID}` if requirements gap
- Always include `/dr-status` as escape hatch

The CTA block MUST follow the canonical format (numbered list, one primary recommendation marker, `---` HR wrapping, task ID included). Variant-B menu of other active tasks when more than one is active. Exact marker tokens live in `cta-format.md`.

## Stage Snapshot Emission (Mandatory Terminal Step)

After the `## Next Steps (CTA)` block above, the agent MUST perform snapshot emission ([definition](../skills/stage-snapshot-writer/SKILL.md)) per `$HOME/.claude/skills/cta-format/SKILL.md` § Snapshot Emission. Parameters bound for this command:

- `stage`: `design`
- `command`: `/dr-design`
- `captured-by`: `agent`
- `recommended-next`: primary CTA option (slash-prefixed `/dr-*` form)

Fail-closed: on non-zero writer exit, emit a single stderr warning line and continue (V-AC-7 contract). Kill switch `DATARIM_DISABLE_SNAPSHOT=1` is handled inside the library; under the switch the writer is a no-op without warning.
