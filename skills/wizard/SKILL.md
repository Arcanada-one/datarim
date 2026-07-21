---
name: wizard
description: Interactive task-spec wizard — a thin orchestrator over the discovery and consilium skills that runs a guided, interruptible, tree-drilling interview, persists it to an append-only JSONL event log, and emits a knowledge/dependency graph. Use from /dr-wizard, or before /dr-prd on L3-4 tasks where "agent misread the intent" is costly.
model: inherit
current_aal: 1
target_aal: 3
---

# Wizard — Interactive Task-Spec Interview

## What is the Wizard

The wizard turns the linear `discovery` → `/dr-prd` chain into a **guided,
one-question-at-a-time interview** the operator can branch, pause, and re-scope. It
exists to eliminate "the agent misread the task intent" by co-authoring the PRD WITH
the operator. It is a **thin orchestrator**: it composes the existing `discovery`
(the one-question-at-a-time engine) and `consilium` (the on-demand panel) skills —
it never re-implements their prompting — and persists every step through the
deterministic state engine `dev-tools/lib/wizard-state.sh`.

Boundary: this skill covers the framework mechanism only — the state engine, this
skill, `/dr-wizard`, and the graph contract. The interactive `arcana` CLI/TUI carrier
— rich prompt panes, terminal graph rendering, cross-`arcana`-session persistence — is
owned by the agent-system track, not here. The graph ingestion, enrichment, and query
surface is owned by the memory/graph track.

## Four capabilities

1. **Nested drill with auto-context-capture (no session_id).** The operator can drill
   into a hard sub-question in a side-thread and pull the conclusion back into the head
   thread without carrying a manual `session_id`. State is anchored to the TASK-ID; the
   captured context is a persisted drill frame holding **references** to prior answers
   (qids), not a copy — it resolves at pop, and the conclusion is written back as the
   parent question's answer.
2. **On-demand consilium.** For a hard decision, convene a panel via the `consilium`
   skill and record the verdict as a `decision` graph node + a `resolves` edge.
3. **Mid-flow re-scope.** Adding/revising a requirement or changing a goal sets a
   `research_dirty`/`plan_dirty` flag. In v1 the actual re-research/re-plan stays
   operator-confirmed (dirty-flag tracking only — no auto-fire loop).
4. **Knowledge/dependency graph emission.** Concepts, requirements, and decisions
   surfaced during the interview are emitted as graph nodes/edges to a side artefact
   for the graph sink.

## State model — append-only JSONL, projection over events

State is an **append-only JSONL event log**; the current state is a **projection
(fold)** over events. This is what makes the interview resumable and branchable:

- **Resume** = replay the log (re-running `/dr-wizard` continues, never restarts).
- **Branch** = a derived drill-stack (`drill_push`/`drill_pop`) plus parent links.
- **Idempotency** = the latest event per `qid` wins on projection.
- Every event carries `v` (schema_version) and a monotonic `seq`.
- A terminal `finalized` event closes the interview; open drill frames are popped as
  `abandoned`. `/dr-prd` consumes only a **finalized** artefact — a half-finished
  interview is never authoritative.

Files (under the gitignored runtime tree):

- `datarim/wizard/{TASK-ID}.wizard.jsonl` — the interview event log (kinds: `meta`,
  `question`, `answer`, `drill_push`, `drill_pop`, `flag`, `finalized`).
- `datarim/wizard/{TASK-ID}.graph.jsonl` — the knowledge/dependency graph.

## Engine API (`dev-tools/lib/wizard-state.sh`)

Source the library, then call the public functions (each takes `--root <KB-root>`):
`wizard_init`, `wizard_add_question`, `wizard_answer`, `wizard_get_answer`,
`wizard_drill_push`, `wizard_drill_pop`, `wizard_rescope`, `wizard_flags`,
`wizard_finalize`, `wizard_status`, `wizard_validate`, `wizard_graph_node`,
`wizard_graph_edge`. The engine is the single point of correctness: run
`wizard_validate` before any consumer trusts the log (it checks balanced push/pop,
monotonic seq, known event kinds/schema_version, and that every graph edge references
an existing node). Validation **rejects** — it never best-effort-repairs.

## Graph artefact — graph-sink ingestion contract

`datarim/wizard/{TASK-ID}.graph.jsonl` is the documented ingestion contract Munera
consumes. One JSON object per line:

- meta header: `{"v":1,"seq":0,"kind":"meta","ts":...,"task_id":...,"artifact":"wizard-graph"}`
- node: `{"v":1,"seq":N,"kind":"node","ts":...,"id":<slug>,"type":"concept|requirement|decision","label":<redacted>}`
- edge: `{"v":1,"seq":N,"kind":"edge","ts":...,"from":<node-id>,"to":<node-id>,"relation":"dependency|refines|resolves"}`

The graph flows OUTBOUND to Munera/LTM, so node **labels are redacted at the sink
boundary** (token shapes, `Bearer …`, PRIVATE KEY blocks, `user:pass@host`, home
paths, RFC1918 addresses) before write. The local `wizard.jsonl` keeps raw interview
text. Enrichment, merge, and query semantics belong to the graph sink — this skill only
emits against the contract; it builds no sink.

## Composition with /dr-prd

`/dr-prd` gains a single, non-invasive hook: **if a finalized wizard artefact exists
for the task, consume its Requirements Summary and graph instead of running the plain
discovery interview.** The hook is idempotent — a re-run re-reads the same artefact and
never double-consumes. When no wizard artefact exists, the plain discovery path is
unchanged. This keeps one interview engine with two entry ergonomics (plain `/dr-prd`
vs guided `/dr-wizard`), avoiding a second, drifting discovery pass.

## Security posture (S1 / S5 / S9)

Enforced by the engine, not by prose: S9 injection gate (escape `\`/`"`/TAB, reject
LF/CR/other C0/DEL); allowlists (qid/node-id `^[A-Za-z0-9_-]+$`; category slug;
type/relation closed enums); S5 path containment (TASK-ID `^[A-Z]{2,10}-[0-9]{4}$`,
symlink target refused, append under an mkdir-lock); S1 redaction on the outbound
graph sink. See `dev-tools/lib/wizard-state.sh` header and `tests/wizard-state.bats`.

## When to stop

Same contract as `discovery` § When to Stop: all branches resolved (no open drill
frame), done criteria defined, no question left whose answer would change the approach.
Then `wizard_finalize` + `wizard_validate` + emit the Requirements Summary. Do not
over-interview — one-word confirmations mean the scope is clear; wrap up.
