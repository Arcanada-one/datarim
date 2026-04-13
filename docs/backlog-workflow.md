# Backlog Workflow Guide

## Overview

The backlog (`datarim/backlog.md`) is a priority-ordered queue of pending tasks. It provides a structured way to capture, prioritize, and track work items before they become active tasks.

Datarim uses a **two-file architecture** for the backlog:

- **`datarim/backlog.md`** — active items (`pending` and `in_progress` only)
- **`datarim/backlog-archive.md`** — historical items (`completed` and `cancelled`)

This split keeps the active backlog small and fast to read. The archive provides a historical record without slowing down day-to-day operations.

---

## Backlog File Format

### Location

| File | Contents | Read frequency |
|------|----------|---------------|
| `datarim/backlog.md` | `pending` and `in_progress` items | Every `/dr-init`, `/dr-status` |
| `datarim/backlog-archive.md` | `completed` and `cancelled` items | Rarely (historical reference) |

### Unified Task Numbering

Backlog items use the **same ID** they will carry throughout their entire lifecycle:

```
backlog.md → tasks.md → documentation/archive/ → backlog-archive.md
```

The ID is assigned once — when the item is added to the backlog — and never changes. When `/dr-init` picks up a backlog item, the active task keeps the same ID. When `/dr-archive` completes it, the archive file uses the same ID.

**Prefix selection (priority order):**

1. **Project prefix** — `ARCA`, `VERD`, `DATA`, `CONS`, `SUP`, `ROB`, `VOICE`, `OVER` — if the task belongs to one project.
2. **Area prefix** — `INFRA`, `WEB`, `DEV`, `DEVOPS`, `CONTENT`, `RESEARCH`, `AGENT`, `BENCH`, `MAINT`, `FIN`, `QA`, `TUNE` — if the task is cross-project or general.
3. **`TASK`** — fallback, avoid if possible.

See the full prefix registry in `$HOME/.claude/skills/datarim-system.md` § Unified Task Numbering.

> **Note:** The generic `BACKLOG-XXXX` format is deprecated. Older entries in `backlog-archive.md` may still use it for historical accuracy.

### Entry Format

Each backlog entry follows this structure:

```markdown
### [PREFIX]-[XXXX]: [Title]
- **Status:** pending | in_progress
- **Priority:** critical | high | medium | low
- **Complexity:** Level 1 | Level 2 | Level 3 | Level 4
- **Project:** [Project name]
- **Description:** [Brief description]
- **Added:** [Date]
- **Source:** [Optional: PRD-slug, reflection, or manual]
```

**Examples:**

```markdown
### INFRA-0004: Google Search Console для всех доменов
### SUP-0002: Support Center — Infrastructure
### CONTENT-0002: Telegram discussion group API
```

**Field notes:**

- **[PREFIX]-XXXX** — Scan existing tasks and backlog for the prefix, pick the next sequential 4-digit number. The ID is invariant across lifecycle.
- **Status** — Only `pending` and `in_progress` belong in the active backlog. Completed and cancelled items move to `backlog-archive.md`.
- **Priority** — Determines selection order: `critical` > `high` > `medium` > `low`.
- **Complexity** — Estimated effort level (see [complexity.md](complexity.md) for definitions). Helps plan iterations.
- **Source** — Where this task originated. Useful for traceability. Common values: `manual`, `PRD-SUP-0001`, `CONTENT-0001 reflection`, `INFRA-0003 reflection`.

---

## Adding Tasks to the Backlog

Three paths to add a task:

### 1. Manual Entry

Edit `datarim/backlog.md` directly. Choose the appropriate prefix (project or area, see Unified Task Numbering above), then add a new entry under `## Active Items` with the next available `{PREFIX}-{NNNN}` number for that prefix.

### 2. From a PRD

After `/dr-prd` generates a Product Requirements Document, it can extract actionable items and propose adding them as backlog entries. The architect agent identifies features, components, and infrastructure work from the PRD and drafts entries with appropriate complexity estimates.

### 3. From Task Decomposition

When `/dr-init` encounters a Level 3-4 task, it may decompose it into subtasks. Subtasks that won't be worked on immediately get proposed as backlog entries, creating a natural work queue for the project.

---

## Status Lifecycle

```
pending → in_progress → completed
                      → cancelled
```

### Transitions

| From | To | Trigger | What happens |
|------|----|---------|-------------|
| `pending` | `in_progress` | `/dr-init` selects a backlog item | Status updated in `backlog.md` |
| `in_progress` | `completed` | `/dr-archive` completes the task | Entry moves from `backlog.md` to `backlog-archive.md` |
| `pending` | `cancelled` | `/dr-archive cancel` or manual | Entry moves to `backlog-archive.md` with a reason |
| `in_progress` | `cancelled` | `/dr-archive cancel` | Entry moves to `backlog-archive.md` with a reason |

Items only move **one direction**. If a cancelled item needs to be revived, create a new backlog entry.

---

## Checking Backlog Status

Three ways to see what's pending:

- **`/dr-status`** — Shows a summary of pending backlog items alongside the current active task and progress.
- **Read `datarim/backlog.md`** — Full details on all active items.
- **Read `datarim/backlog-archive.md`** — Historical completed and cancelled items.

---

## Working with Backlog via Commands

### Starting Work

```bash
# Show pending backlog items, pick one to start
/dr-init

# Directly start working on a specific backlog item (ID is invariant)
/dr-init SUP-0002

# Create a new task (not from backlog)
/dr-init "Add rate limiting to the API"
```

When `/dr-init` starts a backlog item, it:
1. Changes the item's status to `in_progress` in `backlog.md`
2. Creates the task in `datarim/tasks.md`
3. Sets up `datarim/activeContext.md`
4. Routes to the appropriate next stage based on complexity

### Generating Backlog Items from Requirements

```bash
# After generating a PRD, the architect offers to create backlog items
/dr-prd
```

The `/dr-prd` command identifies features and components during requirements analysis. After the PRD is approved, it offers to create backlog entries for each identified work item.

### Completing or Cancelling

```bash
# Complete current task — if it came from backlog, update both files
/dr-archive

# Cancel a task — moves to archive with a reason
/dr-archive cancel
```

`/dr-archive` checks whether the current task originated from a backlog item. If it did, the command moves the entry from `backlog.md` to `backlog-archive.md` with the appropriate status and completion date.

---

## Use Case: Project Manager

A project manager who doesn't use Claude Code directly can still participate in the backlog workflow. All state lives in plain markdown files.

### Reading Progress

| What you want to know | Where to look |
|----------------------|---------------|
| What's pending and in progress | `datarim/backlog.md` |
| Overall project progress | `datarim/progress.md` |
| Current active task details | `datarim/tasks.md` |
| Completed task history | `datarim/backlog-archive.md` |
| Detailed task archives with decisions | `documentation/archive/` |

### Adding a Task

1. Open `datarim/backlog.md` in any text editor
2. Choose the prefix:
   - Project prefix (e.g., `SUP` for Support Center work, `VERD` for Verdicus) — if the task is scoped to one project
   - Area prefix (e.g., `INFRA`, `CONTENT`, `WEB`) — if it's cross-project or general
3. Find the last number used for that prefix (check both `backlog.md` and `tasks.md` archived list), increment by 1
4. Add a new entry at the appropriate priority position under `## Active Items`:

```markdown
### SUP-0010: Implement user notifications
- **Status:** pending
- **Priority:** high
- **Complexity:** Level 2
- **Project:** Support Center
- **Description:** Add email and push notifications for key user events (signup, order status, password reset)
- **Added:** 2026-04-13
- **Source:** manual
```

4. Save the file. The next `/dr-init` run will display this item for selection.

### Prioritization

- Items **higher in the file** have greater visibility when `/dr-init` lists pending work.
- Use the **Priority field** (`critical` > `high` > `medium` > `low`) for sorting decisions.
- Reorder entries within `backlog.md` to reflect current priorities. The file order is the display order.

---

## Tips

- **Keep entries concise.** The backlog captures what and why. Detailed requirements, constraints, and acceptance criteria belong in PRDs (`datarim/prd/`).
- **Use complexity estimates for planning.** A backlog full of Level 3-4 items signals that work needs decomposition before it can flow.
- **Review periodically.** Stale items accumulate. Move items that are no longer relevant to the archive with `cancelled` status.
- **Trace origins.** The `Source` field connects backlog items to their origin — a PRD, a reflection, or a manual decision. This helps when revisiting why something was added.
- **One item per concern.** Avoid multi-part backlog items. If a task has distinct deliverables, split it into separate entries. Each entry should map to a single `/dr-init` session.
