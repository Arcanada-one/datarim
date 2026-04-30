---
name: cta-format
description: Canonical CTA "Next Step" block format for every /dr-* command and pipeline agent. Load when generating slash-command output or finishing a phase.
---

# CTA Format — Canonical Specification

This skill is the **single source of truth** for the "Next Step" Call-to-Action block produced by every `/dr-*` command and every pipeline agent (`planner`, `architect`, `developer`, `reviewer`, `compliance`).

It exists because free-form Next-Step prose forces operators to mentally map task IDs to commands, especially when 2+ tasks are active. The fix: every command output ends with a structured, predictable CTA block with explicit task IDs and one marked primary action.

## When to Apply

- Any `/dr-*` command finishing its work — at the very end of the response
- Any agent (planner / architect / developer / reviewer / compliance) returning control to the operator
- After a Phase boundary in `/dr-prd`, `/dr-plan`, `/dr-design`, `/dr-do`
- After QA/Compliance verdict (PASS, CONDITIONAL_PASS, BLOCKED, NON-COMPLIANT) — see § FAIL-Routing

If a command intentionally produces no actionable next step (e.g. `/dr-help`, `/dr-status` in read-only mode), it MUST still emit a CTA block listing pipeline-entry commands.

## Canonical Block — Single Active Task

```markdown
---

**Следующий шаг — {TASK-ID}** (L{N}, {status})

1. `/dr-{command} {TASK-ID}` — **рекомендуется** — {one-line purpose}
2. `/dr-{command} {TASK-ID}` — альтернатива — {one-line purpose}
3. `/dr-{command}` — {one-line purpose}

---
```

### Field rules

| Field | Rule |
|-------|------|
| Top/bottom separator | Markdown HR `---` (CommonMark, confirmed working in Claude Code renderer) |
| Header | Exactly `**Следующий шаг — {TASK-ID}** (L{N}, {status})`. `{TASK-ID}` MUST resolve to one currently-active task. |
| Number of options | Min 1, recommended 3, hard ceiling 5 (Miller / Hick / Chernev 2015) |
| Option syntax | `N. \`{command + args}\` — **рекомендуется** / альтернатива / {plain text} — {purpose}` |
| Primary marker | Exactly one `**рекомендуется**` per block. Never zero, never two. |
| Purpose clause | One sentence, ≤80 chars. Describe outcome, not mechanics. |
| Task ID inclusion | Every command that operates on a specific task MUST include the `{TASK-ID}` argument inline. Pipeline-entry commands (`/dr-status`, `/dr-help`, `/dr-init`) MAY omit it. |

## Canonical Block — Multiple Active Tasks (Variant B)

When `## Active Tasks` in `datarim/activeContext.md` lists more than one task, append an "Другие активные задачи" section:

```markdown
---

**Следующий шаг — {CURRENT-TASK-ID}** (L{N}, {status})

1. `/dr-{command} {CURRENT-TASK-ID}` — **рекомендуется** — {purpose}
2. `/dr-{command} {CURRENT-TASK-ID}` — альтернатива — {purpose}
3. `/dr-status` — посмотреть весь backlog

**Другие активные задачи:**
- {OTHER-TASK-ID-1} (L{N}) — `/dr-{recommended-command} {OTHER-TASK-ID-1}` — {1-3 word context}
- {OTHER-TASK-ID-2} (L{N}) — `/dr-{recommended-command} {OTHER-TASK-ID-2}` — {1-3 word context}

---
```

Rules:
- "Другие активные задачи" appears only if >1 active task. Skip the section entirely with 0 or 1 active tasks.
- Each "Other" entry shows the recommended next command for that task (deduced from its own pipeline state), not a menu of alternatives.
- Order entries by priority then complexity (P0 first; ties broken by L4 > L3 > L2 > L1).

## Canonical Block — FAIL-Routing

When `/dr-qa` returns BLOCKED or `/dr-compliance` returns NON-COMPLIANT, emit a FAIL-routing CTA. Header changes; structure stays:

```markdown
---

**QA failed для {TASK-ID} — earliest failed layer: Layer {N} ({Layer name})**

1. `/dr-{return-command} {TASK-ID}` — **рекомендуется** — {what to fix}
2. `/dr-{alternative-command} {TASK-ID}` — если {condition}
3. Эскалация — после 3 same-layer fails (loop guard)

---
```

Layer-to-command map (mirrors `skills/datarim-system/backlog-and-routing.md` § FAIL Return Routing):

| Failed Layer | Return Command |
|--------------|----------------|
| Layer 1 (PRD) | `/dr-prd {TASK-ID}` |
| Layer 2 (Design) | `/dr-design {TASK-ID}` |
| Layer 3 (Plan) | `/dr-plan {TASK-ID}` |
| Layer 4 (Code) | `/dr-do {TASK-ID}` |
| Compliance NON-COMPLIANT | `/dr-do {TASK-ID}` (default) or earlier stage if PRD/plan gap identified |

## Authoring Rules for Agents

When an agent generates the CTA block:

1. **Resolve task ID first.** Read `## Active Tasks` from `datarim/activeContext.md`. If 0 → suggest `/dr-init`. If 1 → use it. If >1 → use the task explicitly being worked on; surface the rest in "Другие активные задачи".
2. **Choose primary by complexity rules.** Per `backlog-and-routing.md`:
   - L1 after `/dr-do` → primary is `/dr-archive {ID}`
   - L2 after `/dr-do` → primary is `/dr-archive {ID}`
   - L3-4 after `/dr-plan` → primary is `/dr-design {ID}`
   - L3-4 after `/dr-do` → primary is `/dr-qa {ID}`
   - L3-4 after `/dr-qa` PASS → primary is `/dr-compliance {ID}`
   - On any failure verdict → primary is the layer-return command per FAIL-Routing table
3. **List 2-3 alternatives** that are reasonable (not absurd). Prefer escape-hatches (`/dr-status`) over off-pipeline commands.
4. **Render literally.** The block is markdown emitted as final output, not a prompt to the user — no surrounding prose.

## Anti-Patterns (DO NOT)

| Anti-pattern | Why bad | Correct form |
|--------------|---------|--------------|
| `Run /dr-prd or maybe /dr-plan, depends on what you want` | No primary, no task ID, prose burying action | Numbered list with one `**рекомендуется**` + task ID |
| `Next steps: → continue implementation` | Generic, not actionable | `/dr-do {TASK-ID}` with explicit ID |
| 7+ numbered options | Choice paralysis (Miller / Chernev 2015) | Cap at 5; sweet spot 3 |
| `─── Следующий шаг ───` (box-drawing) | Mojibake on Windows (Claude Code issue #34247) | `---` Markdown HR |
| `## Следующий шаг` (header) | All headers render identical bold in CC terminal — no hierarchy distinction | Bold inline `**Следующий шаг — {ID}**` |
| Two `**рекомендуется**` markers | Defeats primary-CTA hierarchy | Exactly one |
| Missing task ID in actionable command | Re-introduces the original bug this format is designed to prevent | Always include `{TASK-ID}` for task-scoped commands |

## Examples

<!-- gate:history-allowed -->
The illustrative task IDs in the examples below (`ARCA-0001`, `TUNE-0031`, `TUNE-0032`, `AUTH-0001`, etc.) are placeholders for the rendered shape — substitute with the actual current task ID when emitting a real CTA block.

### Example 1 — `/dr-init` for new L4 task (single active)

```markdown
---

**Следующий шаг — ARCA-0001** (L4, in_progress)

1. `/dr-prd ARCA-0001` — **рекомендуется** — PRD обязателен для L4 (10 подзадач в backlog)
2. `/dr-design ARCA-0001` — если предпочитаешь начать с архитектуры
3. `/dr-status` — посмотреть подзадачи (ARCA-0004…ARCA-0013)

---
```

### Example 2 — `/dr-plan` complete, multiple active tasks

```markdown
---

**Следующий шаг — TUNE-0032** (L3, in_progress)

1. `/dr-design TUNE-0032` — **рекомендуется** — auto-transition после plan для L3
2. `/dr-do TUNE-0032` — если creative-phase не нужен
3. `/dr-status` — backlog overview

**Другие активные задачи:**
- TUNE-0031 (L1) — `/dr-do TUNE-0031` — update.sh implementation
- AUTH-0001 (L4) — `/dr-plan AUTH-0001` — PRD approved, 36 backlog items

---
```

### Example 3 — `/dr-qa` BLOCKED at Layer 3

```markdown
---

**QA failed для TUNE-0032 — earliest failed layer: Layer 3 (Plan)**

1. `/dr-plan TUNE-0032` — **рекомендуется** — пересмотреть план (missing rollback strategy)
2. `/dr-prd TUNE-0032` — если нужно ревизовать scope
3. Эскалация — после 3 same-layer fails (loop guard)

---
```
<!-- /gate:history-allowed -->

## Loading

Loaded by the following agents (declared in their `Context Loading` section):

- `agents/planner.md` — emits CTA after `/dr-init`, `/dr-plan`
- `agents/architect.md` — emits CTA after `/dr-prd`, `/dr-design`
- `agents/developer.md` — emits CTA after `/dr-do`
- `agents/reviewer.md` — emits CTA after `/dr-qa` (PASS, CONDITIONAL_PASS, BLOCKED)
- `agents/compliance.md` — emits CTA after `/dr-compliance` (COMPLIANT, NON-COMPLIANT)

Referenced from all 15 `/dr-*` command files in `commands/dr-*.md`.

## Templates

- `templates/cta-template.md` — fill-in-the-blank Markdown snippet with placeholder tables for the three CTA shapes (Single Active Task, Multiple Active Tasks, FAIL-Routing). Use when generating a CTA block in agent / command output; copy the appropriate snippet and substitute placeholders. Update both files together if the format changes.

## Versioning

Introduced in Datarim v1.16.0. See `docs/evolution-log.md` for provenance and source research.

Future changes to this format MUST update golden fixtures in `tests/cta-format/` and `evolution-log.md`.