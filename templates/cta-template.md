# CTA Template — Reusable Snippet

Reusable Markdown snippet for the canonical "Next Step" CTA block. The authoritative specification lives in `$HOME/.claude/skills/cta-format.md`. This template provides fill-in-the-blank examples for agents/commands; update both files together if either changes.

---

## Single Active Task

```markdown
---

**Следующий шаг — {TASK_ID}** (L{LEVEL}, {STATUS})

1. `{COMMAND_PRIMARY}` — **рекомендуется** — {PURPOSE_PRIMARY}
2. `{COMMAND_ALT_1}` — альтернатива — {PURPOSE_ALT_1}
3. `{COMMAND_ALT_2}` — {PURPOSE_ALT_2}

---
```

Placeholders:

| Placeholder | Source | Example |
|-------------|--------|---------|
| `{TASK_ID}` | `datarim/activeContext.md` § Active Tasks (resolved) | `TUNE-0032` |
| `{LEVEL}` | task complexity from `tasks.md` | `3` |
| `{STATUS}` | task lifecycle status | `in_progress` |
| `{COMMAND_PRIMARY}` | recommended next pipeline step | `/dr-design TUNE-0032` |
| `{COMMAND_ALT_1}`, `{COMMAND_ALT_2}` | reasonable alternatives or escape hatches | `/dr-do TUNE-0032`, `/dr-status` |
| `{PURPOSE_*}` | one-sentence outcome (≤80 chars) | `Auto-transition после plan для L3` |

## Multiple Active Tasks (>1 in activeContext.md)

```markdown
---

**Следующий шаг — {TASK_ID}** (L{LEVEL}, {STATUS})

1. `{COMMAND_PRIMARY}` — **рекомендуется** — {PURPOSE_PRIMARY}
2. `{COMMAND_ALT_1}` — альтернатива — {PURPOSE_ALT_1}
3. `/dr-status` — backlog overview

**Другие активные задачи:**
- {OTHER_TASK_ID_1} (L{LEVEL_1}) — `{OTHER_NEXT_CMD_1}` — {OTHER_CONTEXT_1}
- {OTHER_TASK_ID_2} (L{LEVEL_2}) — `{OTHER_NEXT_CMD_2}` — {OTHER_CONTEXT_2}

---
```

Order rules for "Другие активные задачи":
1. Priority descending (P0 > P1 > P2 > P3)
2. Tie-break by complexity descending (L4 > L3 > L2 > L1)
3. List up to 5 entries; if more than 5 active tasks exist, link to `/dr-status` instead

## FAIL-Routing (`/dr-qa` BLOCKED, `/dr-compliance` NON-COMPLIANT)

```markdown
---

**{VERDICT_LABEL} для {TASK_ID} — earliest failed layer: Layer {LAYER_NUM} ({LAYER_NAME})**

1. `{RETURN_COMMAND} {TASK_ID}` — **рекомендуется** — {FIX_HINT}
2. `{ALTERNATIVE_RETURN} {TASK_ID}` — если {CONDITION}
3. Эскалация — после 3 same-layer fails (loop guard)

---
```

Placeholders:

| Placeholder | Values |
|-------------|--------|
| `{VERDICT_LABEL}` | `QA failed`, `Compliance NON-COMPLIANT` |
| `{LAYER_NUM}` | `1`, `2`, `3`, `4` |
| `{LAYER_NAME}` | `PRD`, `Design`, `Plan`, `Code` |
| `{RETURN_COMMAND}` | `/dr-prd`, `/dr-design`, `/dr-plan`, `/dr-do` (per Layer-to-command map in `cta-format.md`) |
| `{ALTERNATIVE_RETURN}` | typically the next-earlier-layer command |
| `{FIX_HINT}` | one-sentence pointer to the failure root cause |

## Reference

- **Spec:** `skills/cta-format.md` — single source of truth
- **Source task:** TUNE-0032 (v1.16.0)
- **Research:** `datarim/insights/INSIGHTS-TUNE-0032.md`
- **Tests:** `tests/cta-format.bats` (39 spec-regression tests) and golden fixtures in `tests/cta-format/fixtures/`