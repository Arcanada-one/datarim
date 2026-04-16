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

Read the first task line from `datarim/activeContext.md`:

```markdown
**Current Task:** [TASK-ID] - [Task Title]
```

## Task Context Tracking

`activeContext.md` must identify the current task:

```markdown
**Current Task:** [TASK-ID] - [Task Title]
- **Status**: [in_progress|completed|paused]
- **Started**: [Date]
- **Complexity**: Level [1-4]
- **Type**: [Type]
- **Priority**: [Priority]
- **Repository**: [Repository]
- **Branch**: [Branch name]
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
2. Read `activeContext.md` to get the current task ID.
3. Verify the task exists in `tasks.md`.
4. Archive only that specific task.
5. Update `activeContext.md` after archiving.

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
