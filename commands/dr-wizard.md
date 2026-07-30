---
name: dr-wizard
description: Guided, one-question-at-a-time interactive task-spec wizard — drill into sub-questions with auto-context-capture, convene consilium on demand, track mid-flow re-scope, and emit a knowledge/dependency graph. Co-authors a PRD with the operator.
globs:
  - datarim/projectbrief.md
  - $HOME/.claude/skills/discovery/SKILL.md
  - $HOME/.claude/skills/consilium/SKILL.md
---

# /dr-wizard — Interactive Task-Spec Wizard

Evolve the linear discovery → `/dr-prd` chain into a **guided, interruptible,
tree-drilling interview**. The operator answers one question at a time, can drill
into a hard sub-question in a nested side-thread and return WITHOUT carrying a
manual session_id (the wizard persists context itself), can convene a consilium on
demand per hard decision, and can re-scope mid-flow. The output feeds `/dr-prd`, and
a knowledge/dependency graph of the discussion is emitted as a side artefact for
the graph sink.

This command is a **thin orchestrator**: it composes the existing `discovery` and
`consilium` skills — it never re-implements their prompting — and persists every
step through the deterministic state engine `dev-tools/lib/wizard-state.sh`. The
interactive `arcana` CLI/TUI carrier (rich panes, terminal graph rendering,
cross-session persistence) is owned by the agent-system track; the graph sink is a separate track.

## Instructions

**Stage Header (mandatory)**: emit `**{TASK-ID} · {title}**` as the first line of your
response. See `$HOME/.claude/skills/cta-format/SKILL.md` § Stage Header.

0. **RESOLVE PATH**: before any read/write to `datarim/`, walk up from cwd to find it.
   If absent, STOP and tell the user to run `/dr-init`. Only `/dr-init` may create
   `datarim/`. See `$HOME/.claude/skills/datarim-system/SKILL.md` § Path Resolution Rule.

1. **SOURCE THE ENGINE**:
   `source "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/lib/wizard-state.sh"`, then
   `wizard_init <TASK-ID> --root <KB-root>`. All state lives in the gitignored
   `datarim/wizard/{TASK-ID}.wizard.jsonl` (interview log) and
   `datarim/wizard/{TASK-ID}.graph.jsonl` (graph). Re-running `/dr-wizard` on an
   existing artefact RESUMES it — the engine replays the event log; do not restart the
   interview from scratch. Read `wizard_status <TASK-ID> --root <KB-root>` first.

2. **RUN THE INTERVIEW** (compose `discovery`): pick the mode (Quick/Standard/Deep) by
   complexity per `$HOME/.claude/skills/discovery/SKILL.md`. For each question:
   - Propose an answer from context (Codebase-First Rule). Emit ONE question at a time.
   - On the operator's reply, persist it:
     `wizard_add_question <TASK-ID> <qid> <category> "<text>" --root <root>` then
     `wizard_answer <TASK-ID> <qid> "<answer>" --root <root>`.
   - Emit a graph node for each concept/requirement surfaced:
     `wizard_graph_node <TASK-ID> <node-id> <concept|requirement|decision> "<label>" --root <root>`
     and an edge when a dependency/refinement appears:
     `wizard_graph_edge <TASK-ID> <from> <to> <dependency|refines|resolves> --root <root>`.
     Labels are redacted at the sink boundary automatically — but keep them distilled,
     not pasted operator paragraphs.

3. **DRILL (nested side-thread, auto-context-capture)**: when a question is hard enough
   that it needs its own sub-interview, open a drill frame:
   `wizard_drill_push <TASK-ID> <parent-qid> "<ref-qid-csv>" --root <root>`. The `refs`
   are qid REFERENCES into the same log — the captured context is those prior answers,
   not a copy. Run the sub-questions, then close it:
   `wizard_drill_pop <TASK-ID> "<conclusion>" --root <root>` — the conclusion is written
   back as the parent question's answer and you return to the head thread. Drills may
   nest; every push must be matched by a pop.

4. **CONSILIUM ON DEMAND** (compose `consilium`): for a hard architectural decision, run
   a panel per `$HOME/.claude/skills/consilium/SKILL.md`, then record the verdict as a
   `decision` graph node plus a `resolves` edge from the decision to the question it
   settles. Do NOT re-implement the panel here.

5. **RE-SCOPE MID-FLOW**: if the operator adds/revises a requirement or changes a goal,
   mark the downstream stale: `wizard_rescope <TASK-ID> <research|plan|both> "<note>" --root <root>`.
   This sets `research_dirty`/`plan_dirty` flags (read them with
   `wizard_flags <TASK-ID> --root <root>`). In v1 the actual re-research/re-plan is
   **operator-confirmed** — surface the dirty flags and recommend `/dr-prd` re-run;
   do NOT auto-fire a re-plan loop.

6. **FINALIZE**: when the interview is complete (discovery § When to Stop),
   `wizard_finalize <TASK-ID> --root <root>` (this pops any dangling drill frame as
   `abandoned`) and `wizard_validate <TASK-ID> --root <root>` (must exit 0). Produce the
   discovery-style Requirements Summary. Only a **finalized** artefact is authoritative
   for `/dr-prd`.

## /dr-auto Mode (when DATARIM_AUTO_MODE=1)

When auto-mode is active (env var + matching marker), this command:

1. Consults `${DATARIM_RUNTIME:-$HOME/.claude}/skills/autonomous-mode/SKILL.md`
   § Question Suppression Ladder before any operator prompt — resolve each interview
   question through L1–L4 (codebase/runtime/memory/coworker) and only surface the
   genuinely ambiguous ones. A wizard that suppresses every question is a plain
   discovery pass; that is acceptable — persist the L1–L4-resolved answers to the log.
2. Runs a consilium autonomously for L3–L4 hard decisions instead of asking the operator.
3. For a discovered gap during the interview: apply the L1 Inline Rule; log inline-resolved
   gaps to `datarim/tasks/{TASK-ID}-auto-inline-log.md`.
4. Never auto-fires a re-plan on re-scope — dirty-flag tracking only (hard boundary).

## Next Steps (CTA)

After `wizard_finalize`, emit a CTA block per `$HOME/.claude/skills/cta-format/SKILL.md`:
primary `/dr-prd {TASK-ID}` (it consumes the finalized wizard artefact — requirements +
graph — instead of a fresh discovery interview). Escape hatch: `/dr-status`.
