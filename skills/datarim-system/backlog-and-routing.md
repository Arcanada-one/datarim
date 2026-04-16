# Datarim System — Backlog and Routing

## Backlog Management (v2.0)

### Two-File Architecture

**Active Backlog** (`backlog.md`)
- contains only `pending` and `in_progress`
- optimized for normal reads
- uses the same `{PREFIX}-{NNNN}` ID the task will keep later

**Backlog Archive** (`backlog-archive.md`)
- stores `completed` and `cancelled` items
- used for history, not routine execution

### When to Update

- On task completion: move from `backlog.md` to `backlog-archive.md`
- On new work: add to `backlog.md` with `pending`

## Complexity Decision Tree

### Level 1

- single file change
- under 50 lines of code
- no architecture changes
- flow: `init → do → archive`

### Level 2

- 2-5 files
- under 200 lines
- minor refactoring
- flow: `init → plan → do → archive`

### Level 3

- 5-15 files
- 200-1000 lines
- requires design
- flow: `init → prd → plan → design → do → qa → archive`

### Level 4

- 15+ files
- over 1000 lines
- complex architecture
- flow: `init → prd → plan → design → phased-do → qa → compliance → archive`

All levels: `archive` runs reflection internally as mandatory Step 0.5 (v1.10.0, TUNE-0013).

## Date Handling

Use native shell date utilities:

```bash
date +%Y-%m-%d
date -u +%Y-%m-%dT%H:%M:%SZ
```

Or use the current date from session context.

## Mode Transition Optimization

### Automatic Transitions

- Level 3-4 → auto-enter `/dr-design`
- QA validation needed → auto-enter `/dr-qa`
- Implementation done → auto-suggest `/dr-archive` (runs reflection as Step 0.5)

### Manual Transitions

- `/dr-plan` → planning mode
- `/dr-design` → creative mode
- `/dr-do` → execution mode
- `/dr-qa` → QA mode
- `/dr-archive` → archive mode (includes reflection as Step 0.5)
