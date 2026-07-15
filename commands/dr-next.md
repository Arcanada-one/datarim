---
name: dr-next
description: Resume work on current task from last checkpoint with context awareness
---

# /dr-next - Resume Task

Continue from where you left off.

## Steps

**Stage Header (mandatory)**: Emit `**{TASK-ID} · {title}**` as the first line of your response, before any tool-call narration. The title is the verbatim one-liner field from `tasks.md` (between `L{N} · ` and ` → tasks/`). Skip this header only for `/dr-help`, `/dr-status`, `/dr-doctor`, and `/dr-init` Steps 1-3 (which emit it immediately after Step 4). See `$HOME/.claude/skills/cta-format/SKILL.md` § Stage Header.
1. **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system/SKILL.md` § Path Resolution Rule.

### EXECUTION HOST

1. Source the resolver: `source "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/lib/execution-host.sh"`.
2. Call `eh_decision <workspace-root> <execution-hosts-map-path>` (default map: `~/.claude/local/config/execution-hosts.yml`).
3. On **off-host** (exit code 10) for this read/utility command: proceed LOCALLY in read-only mode -- do NOT dispatch (dispatching an observational command to the very host the laptop is meant to monitor buys nothing). Surface the delegation directive (`dev-tools/datarim-dispatch.sh --workspace <root> --task <TASK-ID>`) as information only, never as a blocking question.
4. On **unconfigured** (exit code 0, binding absent): proceed unchanged (fail-open).
5. On **on-host** (exit code 0, binding present): proceed normally.

Note: the machine-local PreToolUse guard remains the hard floor; this Step-0 check is the cooperative soft layer sharing the same resolver library.

2. **TASK RESOLUTION**: Apply Task Resolution Rule from `$HOME/.claude/skills/datarim-system/SKILL.md` § Task Resolution Rule. Use the resolved task ID for all subsequent steps. If >1 active tasks, show all with their current phase and ask which to resume.
2.5. **SNAPSHOT-FIRST READ**: Before reading any other state, probe `datarim/snapshots/{TASK-ID}.snapshot.md`. If `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-stage-snapshot-on-exit.sh" --validate-frontmatter --task {TASK-ID}` exits 0 — read the snapshot as primary context and emit the replay-prompt per `$HOME/.claude/skills/dr-next-snapshot-replay/SKILL.md` § Replay-prompt template (recommended CTA + bilingual autonomy reminder + `done before:` + snapshot body). STOP the downstream Read pipeline — primary context is the snapshot. If the validator returns non-zero (missing or malformed) — silently fall through to Step 3 with no warning lines (V-AC-7).
3. Read current state for the resolved task
4. Determine phase (INIT/PLAN/DESIGN/DO/REFLECT)
5. Show context summary
6. Resume appropriate action

## Read
- `datarim/activeContext.md`
- `datarim/tasks.md`
- `datarim/progress.md`
- `datarim/backlog.md` (for routing when no active task)

## Write
Depends on current phase

## Routing
- No active task → check `datarim/backlog.md` for pending items:
  - If pending items exist → display them and suggest `/dr-init` with backlog selection
  - If no pending items → suggest `/dr-init` with new task
- Multiple active tasks → show all with phases, ask which to resume
- In PLAN → continue planning
- In DO → continue implementation
- Ready for ARCHIVE → suggest `/dr-archive`

## Next Steps (CTA)

After resolving the current phase, the planner/architect/developer agent (whichever owns the resumed phase) MUST emit a CTA block ([definition](../skills/cta-format/SKILL.md)) per `$HOME/.claude/skills/cta-format/SKILL.md`.

**Routing logic for `/dr-next`:**

- Resumed in PLAN phase → primary `/dr-plan {TASK-ID}` (continue planning)
- Resumed in DESIGN phase → primary `/dr-design {TASK-ID}`
- Resumed in DO phase → primary `/dr-do {TASK-ID}`
- Ready for QA / archive → primary `/dr-qa {TASK-ID}` or `/dr-archive {TASK-ID}` per pipeline
- No active tasks but backlog has items → primary `/dr-init` (pick from backlog)
- Always include `/dr-status` as escape hatch

The CTA block MUST follow the canonical format. If >1 active tasks, the entire `## Active Tasks` list is the menu (Variant B fully expanded).
