---
name: datarim-system
description: Core workflow rules — file locations, task numbering, path resolution, backlog format, complexity routing. Always loaded.
---

# Datarim System Rules

> **Core system rules for Datarim workflow and file organization. Always loaded.**

## File Locations

**CRITICAL:** All Datarim state files reside in `datarim/` directory at the **project root** (the top-level git repository root, NOT a submodule or subdirectory).

### Path Resolution Rule (MANDATORY)

Before writing ANY file to `datarim/`, you MUST resolve the correct path:

1. **Check if `datarim/` exists in the current working directory.** If yes, use it.
2. **If NOT found:** Walk up the directory tree (parent, grandparent, etc.) until you find a directory that contains `datarim/`. Use that path.
3. **If still NOT found anywhere up the tree:** **STOP. Do NOT create the directory.** Only the `/dr-init` command is authorized to create a new `datarim/` directory. If you are not running `/dr-init`, output an error: _"datarim/ directory not found. Run `/dr-init` first to initialize it in the correct project root."_

**Why:** In monorepos and submodule setups, the working directory may be a subdirectory. Creating `datarim/` there pollutes the subproject. The correct location is always the top-level project root.

**Quick shell check (use before any write):**
```bash
DR_DIR=$(pwd); while [ "$DR_DIR" != "/" ]; do [ -d "$DR_DIR/datarim" ] && break; DR_DIR=$(dirname "$DR_DIR"); done
if [ "$DR_DIR" = "/" ]; then echo "ERROR: datarim/ not found"; else echo "$DR_DIR/datarim"; fi
```

### Core Files
- `tasks.md` — Active task tracking (ephemeral)
- `backlog.md` — Active task queue (v2.0 — performance optimized)
- `backlog-archive.md` — Historical completed/cancelled tasks
- `activeContext.md` — Current state
- `progress.md` — Overall progress
- `projectbrief.md` — Project overview
- `productContext.md` — Product requirements
- `systemPatterns.md` — System patterns
- `techContext.md` — Technical context
- `style-guide.md` — Code style guide

### Directories
- `prd/` — Product Requirements Documents
- `tasks/` — ALL operational task documentation
- `creative/` — Creative phase documents
- `reflection/` — Reflection documents
- `qa/` — QA reports
- `archive/` — Completed task archives
- `reports/` — Debug/diagnostic reports
- `docs/` — Framework evolution log and documentation

---

## Documentation Storage Rules

### MANDATORY: Task ID in ALL Report Filenames

**Format:** `[PREFIX]-[4-digit-number]` (e.g., `TASK-0001`, `FIN-0001`)

**Report Types:**
- QA reports: `qa-report-[task_id]-[phase].md`
- Compliance reports: `compliance-report-[task_id]-[date].md`
- Test reports: `test-report-[task_id]-[component].md`
- Debug reports: `debug-[task_id]-[feature].md`
- Creative: `creative-[task_id]-[feature_name].md`

### Prohibited Locations

**NEVER create MD files (except README.md) in:**
- Application source directories
- Component directories (`frontend/src/`, `backend/src/`)
- Service root directories (except README.md)
- Any directory containing source code

---

## Task Numbering System

### Format
```
[PREFIX]-[NUMBER]
```

**Examples:**
- `TASK-0001` (General task #1)
- `FIN-0001` (Finance task #1)
- `QA-0008` (QA task #8)

### Auto-Generation
If user doesn't provide task ID, system automatically:
1. Determines prefix from task content/keywords
2. Scans existing tasks for same prefix
3. Generates next sequential number (4-digit with leading zeros)

### Task ID Extraction
Get current task ID from `datarim/activeContext.md` first line:
```markdown
**Current Task:** [TASK-ID] - [Task Title]
```

---

## Task Context Tracking

### Active Task Identification

`activeContext.md` MUST track current task:

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
```
not_started → in_progress → completed → archived
     ↓              ↑
   paused ←────────┘
```

### Archive Command Behavior
`/dr-archive` command:
1. Reads `activeContext.md` to get current task ID
2. Verifies task exists in `tasks.md`
3. Archives ONLY that specific task (not all completed)
4. Updates `activeContext.md` after archiving

---

## Backlog Management (v2.0)

### Two-File Architecture

**Active Backlog** (`backlog.md`):
- Contains ONLY `pending` and `in_progress` items
- Performance optimized (~10x faster reads)
- Format: `BACKLOG-[4-digit-number]`

**Backlog Archive** (`backlog-archive.md`):
- Historical `completed` and `cancelled` items
- Rarely read during normal operations
- Provides historical reference

### When to Update
- Task completion: Move from `backlog.md` to `backlog-archive.md`
- New task: Add to `backlog.md` with `pending` status

---

## Complexity Decision Tree

### Level 1 (Quick Fix)
- Single file change
- < 50 lines of code
- No architecture changes
- Flow: init → do → reflect → archive

### Level 2 (Enhancement)
- Few files (2-5)
- < 200 lines of code
- Minor refactoring
- Flow: init → plan → do → reflect → archive

### Level 3 (Feature)
- Multiple files (5-15)
- 200-1000 lines
- Requires design
- Flow: init → prd → plan → design → do → qa → reflect → archive

### Level 4 (Major Feature)
- Many files (15+)
- > 1000 lines
- Complex architecture
- Flow: init → prd → plan → design → phased-do → qa → compliance → reflect → archive

---

## Date Handling

For dates in filenames and reports, use native shell commands:
```bash
date +%Y-%m-%d          # 2026-04-09
date -u +%Y-%m-%dT%H:%M:%SZ  # UTC ISO 8601
```
Or use the current date from conversation context. See `$HOME/.claude/skills/utilities.md` for additional utility recipes.

---

## Mode Transition Optimization

### Automatic Transitions
- Level 3-4 → Auto-enter CREATIVE mode (/dr-design)
- QA validation needed → Auto-enter QA mode (/dr-qa)
- Implementation done → Auto-suggest REFLECT mode

### Manual Transitions
- `/dr-plan` → PLAN mode
- `/dr-design` → CREATIVE mode
- `/dr-do` → DO mode
- `/dr-qa` → QA mode
- `/dr-reflect` → REFLECT mode
- `/dr-archive` → ARCHIVE mode

---

## Critical Rules (Always Apply)

1. **Datarim is Truth** — Never work outside `datarim/`
2. **Task ID Required** — ALL reports must include task ID
3. **No documentation/tasks/** — This directory must NOT exist
4. **Context Tracking** — Always update `activeContext.md`
5. **Backlog v2.0** — Use two-file architecture (active + archive)
6. **Path Resolution First** — Always find `datarim/` before writing
7. **No Absolute Paths** — Use `$HOME/.claude/` or project-relative only

---

*These rules ensure clean organization and efficient workflow.*
