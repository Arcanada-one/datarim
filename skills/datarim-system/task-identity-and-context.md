# Datarim System — Task Identity and Context

## Task Numbering System

### Format

```text
{PREFIX}-{NNNN}
```

Examples:

- `TASK-0001`
- `FIN-0001`
- `QA-0008`

### Auto-Generation

If the user does not provide a task ID, the system:

1. Determines a prefix from the task content or project area.
2. Scans existing tasks for the same prefix.
3. Generates the next sequential 4-digit number.

### Task ID Extraction

Read active tasks from `datarim/activeContext.md` under `## Active Tasks`:

```markdown
## Active Tasks

- **TASK-0001** — Description (Level 2, started 2026-04-18)
- **TASK-0002** — Description (Level 3, started 2026-04-17)
```

### Task Resolution Rule

When a pipeline command needs a task ID, apply this logic:

1. If user provided a task ID argument → use it directly.
2. Read `## Active Tasks` from `datarim/activeContext.md`.
3. If 0 active tasks → STOP, suggest `/dr-init`.
4. If 1 active task → use it (backward compatible, no prompt).
5. If >1 active tasks → prompt user:
   `"Несколько активных задач: [list]. По какой задаче? (укажите ID)"`

### activeContext.md Write Rules

- `/dr-init` **APPENDS** a new task to `## Active Tasks`.
- `/dr-archive` **REMOVES** the specific archived task from `## Active Tasks`. Other active tasks remain.
- No command overwrites the entire `## Active Tasks` section.
- Legacy format (`**Current Task:**` single line) — if encountered, convert to `## Active Tasks` list on first write.

## Task Context Tracking

`activeContext.md` tracks all active tasks:

```markdown
# Active Context

## Active Tasks

- **TASK-0001** — Description (Level 2, started 2026-04-18)
- **TASK-0002** — Description (Level 3, started 2026-04-17)

## Последние завершённые

- **TASK-0000** ✅ (2026-04-17) → Summary. `archive-TASK-0000.md`.
```

### Task Status Lifecycle

```text
not_started → in_progress → completed → archived
     ↓              ↑
   paused ←────────┘
```

### Archive Command Behavior

`/dr-archive` must:

1. **Verify clean git status** for every repo touched by the task. If dirty, STOP and force commit/accept/abort decision — never archive silently over uncommitted changes. (See TUNE-0003 reflection: applied ≠ committed ≠ canonical.)
2. **Resolve task ID** using Task Resolution Rule (argument or disambiguation).
3. Verify the task exists in `tasks.md`.
4. Archive only that specific task.
5. **Remove** the archived task from `## Active Tasks` in `activeContext.md` (keep other active tasks).

### PRD Waiver Policy (Level 3-4 follow-up tasks)

A Level 3 or Level 4 task MAY waive `/dr-prd` regeneration if all conditions hold:

1. It executes **one clearly scoped track** from a parent PRD/archive.
2. The parent PRD or archive was approved within the **last 30 days**.
3. No new requirements are introduced — the waiver is for scope already covered.

When waived, `tasks.md` MUST include a line `**PRD waived:**` with the parent reference and rationale. Absent this line, `/dr-plan` for L3-4 requires PRD generation.

## Unified Task Numbering

The same task ID persists across the whole lifecycle:

```text
backlog.md → tasks.md → documentation/archive/ → backlog-archive.md
```

No renumbering occurs when a backlog item becomes active.

### Prefix Selection

1. Use a project prefix if the task belongs to one specific project.
2. Otherwise use an area prefix.
3. Use `TASK` only as a fallback.

### Prefix Registry

#### Project Prefixes

| Prefix | Project |
|--------|---------|
| `ARCA` | Arcanada Ecosystem core |
| `VERD` | Verdicus |
| `DATA` | Datarim framework |
| `CONS` | Consilium |
| `SUP` | Support Center |
| `ROB` | Rules of Robotics |
| `VOICE` | Voice Agent |
| `OVER` | Overlook |
| `CONN` | Model Connector |
| `SRCH` | Scrutator (Search & Retrieval) |
| `LTM` | Long Term Memory |

#### Area Prefixes

| Prefix | Area |
|--------|------|
| `INFRA` | Infrastructure |
| `WEB` | Websites |
| `DEV` | Application development |
| `DEVOPS` | CI/CD and automation |
| `CONTENT` | Articles and social media |
| `RESEARCH` | Research and analysis |
| `AGENT` | AI agents |
| `BENCH` | Benchmarks |
| `MAINT` | Maintenance |
| `FIN` | Finance and legal |
| `QA` | Standalone QA |
| `TUNE` | Datarim self-improvement |

### Deprecated Namespace

`BACKLOG-XXXX` is deprecated for new work. Historical references may remain in archives.

### Rename Policy

A task ID changes only by explicit request. If renamed, update all references atomically.
