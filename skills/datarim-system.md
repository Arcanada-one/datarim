---
name: datarim-system
description: Core Datarim rules. Load this entry first, then only the fragment needed for paths, storage, numbering, backlog, routing, or archive behavior.
---

# Datarim System Rules

> **Core system rules for Datarim (датарим). Always load this entry first.**
> "Datarim" and "датарим" are the same framework. Recognize both forms in any language context.

## Always-Apply Rules

- All Datarim workflow state lives in `datarim/` at the project root.
- Resolve the correct `datarim/` path before any read/write operation.
- Never create `datarim/` outside `/dr-init`.
- Use task IDs in `{PREFIX}-{NNNN}` format across the whole lifecycle.
- Keep `datarim/` for local workflow state and `documentation/archive/` for committed long-term archives.
- Never create `documentation/tasks/`.
- Use `$HOME/.claude/` or project-relative paths, not absolute machine-specific paths.
- **Operational files are thin indexes**: `tasks.md`, `backlog.md`, `activeContext.md` carry one-liner-per-task pointers — never full task content. Descriptions live in `tasks/{TASK-ID}-task-description.md`. `progress.md` is **abolished**. See § Operational File Schema below.

## Operational File Schema (v1.19.0+)

Operational files are **indexes**, not content. Each line answers: which task, what state, where the description lives. Detailed contract: `skills/datarim-doctor.md`.

### `tasks.md` and `backlog.md` line format

Canonical regex (anchored, single-line):

```
^- ([A-Z]{2,10}-[0-9]{4}) · (STATUS) · P[0-3] · L[1-4] · (.{1,80}) → tasks/\1-task-description\.md$
```

`STATUS` ∈
- `tasks.md`: `in_progress|blocked|not_started`
- `backlog.md`: `pending|blocked-pending|cancelled`

Separator: `·` (U+00B7 MIDDLE DOT). Arrow: `→` (U+2192). Title: 1–80 chars, single-line, no `→`.

Example:
<!-- gate:history-allowed -->
```
- TUNE-0071 · in_progress · P1 · L3 · Index-Style Refactor → tasks/TUNE-0071-task-description.md
```
<!-- /gate:history-allowed -->

Section headers (`## Active`, `## Pending`) and blank lines allowed; only `- {PREFIX}-{NNNN}` bullets are validated.

### `activeContext.md` thin contract (v2 — ≤30 lines)

One section only — strict mirror of `tasks.md` § Active:

```markdown
# Active Context

## Active Tasks
<!-- strict mirror of tasks.md § Active — identical lines, identical order -->
- {ID} · {status} · P{n} · L{n} · {title} → tasks/{ID}-task-description.md
```

**Removed in v1.19.1:** `## Последние завершённые` and `## Last Updated`
sections. Recency hint is now a runtime computation in `/dr-status --recent N`
that mtime-sorts `documentation/archive/**/archive-*.md`. Single source of
truth for completion history = `documentation/archive/`.

### `progress.md`

**Abolished as of v1.19.0.** `/dr-doctor --fix` deletes the file. Per-task
progress notes belong in `tasks/{TASK-ID}-task-description.md` § Implementation
Notes or in the archive doc.

### `backlog-archive.md`

**Abolished as of v1.19.1.** `/dr-doctor --fix` migrates each
entry to `documentation/archive/{area or cancelled}/archive-{ID}.md` with
per-task content-presence assertion, then deletes the file. `pre-archive-check.sh`
blocks when the file exists.

### Description File Contract

`datarim/tasks/{TASK-ID}-task-description.md` is the **only** place for task content. Required 12-key YAML frontmatter (closed schema):

```yaml
---
id: <TASK-ID>                 # ^[A-Z]{2,10}-[0-9]{4}$
title: <string>               # ≤ 80 chars
status: <enum>                # in_progress|blocked|not_started|pending|blocked-pending|cancelled
priority: <enum>              # P0|P1|P2|P3
complexity: <enum>            # L1|L2|L3|L4
type: <string>                # free-form (framework, infra, content, …)
project: <string>             # free-form (Datarim, Arcanada, Verdicus, …)
started: <date>               # YYYY-MM-DD
parent: <TASK-ID|null>
related: <list[TASK-ID]>      # empty list ok
prd: <relpath|null>           # e.g. prd/PRD-{ID}.md
plan: <relpath|null>          # e.g. plans/{ID}-plan.md
---
```

Body sections (markdown, ≤ 250 lines): `## Overview`, `## Acceptance Criteria`, `## Constraints`, `## Out of Scope`, `## Related`. Optional `## Implementation Notes`, `## Decisions`. Anything beyond ~250 lines → split into PRD/design doc.

### activeContext.md Write Rules

When mutating `## Active Tasks`:
- **Append** new task as a one-liner; do NOT remove other active tasks.
- **Remove** archived task on `/dr-archive`, keep other active tasks intact.
- **Convert** any legacy `**Current Task:** {ID}` line into the thin list before appending. (Self-heal via `/dr-doctor`.)

### Self-Heal Entry Points

- `/dr-init` Step 2.4 — probes `scripts/datarim-doctor.sh --quiet`; offers `/dr-doctor --fix` on non-compliance.
- `/dr-archive` pre-archive gate — `pre-archive-check.sh` validates line format; bypass with `--no-schema-check` only during in-flight migration.

## Fragment Routing

Load only the fragment needed for the current sub-problem:

- `skills/datarim-system/path-and-storage.md`
  Use for path resolution, core file locations, report storage, and archive/documentation boundaries.
- `skills/datarim-system/task-identity-and-context.md`
  Use for task numbering, active task tracking, prefix rules, and rename policy.
- `skills/datarim-system/model-assignment.md`
  Use for `model` / `effort` frontmatter rules and agent-skill assignment policy.
- `skills/datarim-system/backlog-and-routing.md`
  Use for backlog architecture, complexity levels, date handling, and mode transitions.
- `skills/datarim-system/command-and-archive-rules.md`
  Use for `/dr-` namespace rules, archive area mapping, project setup, and critical invariants.

## Quick Path Resolution Rule

Before writing any file to `datarim/`:

1. Check whether `datarim/` exists in the current working directory.
2. If not, walk up the directory tree until a parent containing `datarim/` is found.
3. If no such directory exists, stop and instruct the user to run `/dr-init`.

## Loading Order (v1.17.0+)

Skills, agents, commands, and templates load from two layers:

1. **Framework layer:** `$HOME/.claude/{skills,agents,commands,templates}/{name}.md`.
   In symlink-mode (default since v1.17.0) this resolves to the
   cloned datarim repo. In copy-mode it resolves to local copies.
2. **Local overlay:** `$HOME/.claude/local/{skills,agents,commands,templates}/{name}.md`.
   User-private. Gitignored. Created empty by `install.sh`.

**Conflict resolution:** if a name collides between layer 1 and layer 2, the
local overlay wins. `validate.sh` emits a WARN line per detected override.

**Convention:** prefix local files with a personal namespace
(`local/skills/my-org-style.md`) to avoid accidental overrides of framework
skills you actually wanted to keep tracking upstream.

## Task Disposition Patterns

When closing a task, choose the disposition that matches the actual outcome:

| Disposition | When | Action |
|---|---|---|
| `completed` | All ACs PASS, full archive done | Standard `/dr-archive` flow → `documentation/archive/{area}/archive-{ID}.md` + `backlog-archive.md` ## Completed |
| `cancelled` | User abandoned the task; no deliverable shipped | `backlog-archive.md` ## Cancelled with status `cancelled`, date, **reason**. No archive document. |
| `absorbed` | Scope and deliverable fully delivered **inside another task** | `backlog-archive.md` ## Completed with status `absorbed`, link to absorbing task ID, note `delivered as part of {OTHER-TASK}`. No separate archive document — reference the absorbing task's archive. |
| `superseded` | Replaced by a newer task with broader/different scope; no deliverable from this ID | `backlog-archive.md` ## Cancelled with status `superseded`, link to replacing task. |

Source: prior incident — an `update.sh` deliverable was shipped inside a different task's scope; `cancelled` was inaccurate (deliverable existed) and `completed` was inaccurate (no separate archive). `absorbed` captures the reality and preserves audit trail.

## Quick Routing Heuristic

- Need file placement or archive destination? Load `path-and-storage.md` or `command-and-archive-rules.md`.
- Need task ID, active task, or backlog lifecycle logic? Load `task-identity-and-context.md` and `backlog-and-routing.md`.
- Need complexity-driven stage routing? Load `backlog-and-routing.md`.
- Need `model` or `effort` guidance for agents/skills? Load `model-assignment.md`.

## Why This Skill Is Split

This skill is always in the hot path, so the entry file stays short and routing-focused. Detailed rules now live in focused supporting fragments to reduce context waste while preserving the full system contract.
