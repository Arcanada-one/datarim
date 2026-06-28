# Datarim System — Task Identity and Context

## Task Numbering System

### Format

```text
{PREFIX}-{NNNN}
```

Examples:

<!-- gate:history-allowed -->
- `TASK-0001`
- `FIN-0001`
- `QA-0008`
<!-- /gate:history-allowed -->

### Auto-Generation

If the user does not provide a task ID, the system:

1. Determines a prefix from the task content or project area.
2. Computes the candidate ID using the deterministic formula:
   `max(claimed across documentation/archive ∪ datarim/tasks.md ∪ datarim/backlog.md) + 1`
   (max taken over all `PREFIX-NNNN` entries for the chosen prefix across all three claim surfaces — archive, active tasks, and backlog).
3. **Do not emit or announce the chosen task ID — in reply text or in any artefact — until this 3-surface collision probe completes.**
4. If the computed candidate is already claimed (a parallel-session race on the agent's own new ID), auto-bump to the next free ID and emit a warning — no operator prompt.

This generalises § Pre-Spawn ID-Claim Probe (below) from multi-ID PRD spawns to every single-ID assignment.

### Task ID Extraction

Read active tasks from `datarim/activeContext.md` under `## Active Tasks`:

<!-- gate:history-allowed -->
```markdown
## Active Tasks

- **TASK-0001** — Description (Level 2, started 2026-04-18)
- **TASK-0002** — Description (Level 3, started 2026-04-17)
```
<!-- /gate:history-allowed -->

### Task Resolution Rule

When a pipeline command needs a task ID, apply this logic:

1. If user provided a task ID argument → use it directly.
2. Read `## Active Tasks` from `datarim/activeContext.md`.
3. If 0 active tasks → STOP, suggest `/dr-init`.
4. If 1 active task → use it (backward compatible, no prompt).
5. If >1 active tasks → prompt the operator with a multiple-active-tasks disambiguation message that lists the candidates and asks which task ID to resume. The exact wording follows the operator's interaction language; the contract is the disambiguation, not the literal phrasing.

### activeContext.md Write Rules

- `/dr-init` **APPENDS** a new task to `## Active Tasks`.
- `/dr-archive` **REMOVES** the specific archived task from `## Active Tasks`. Other active tasks remain.
- No command overwrites the entire `## Active Tasks` section.
- Legacy format (`**Current Task:**` single line) — if encountered, convert to `## Active Tasks` list on first write.

### tasks.md Content Discipline

**Allowed content** in `tasks.md`:
- Task entries (header `### {ID} — Title`, status, overview, acceptance criteria)
- Implementation plans for L1-L2 tasks (inline)
- Plan pointers for L3+ tasks (`**Implementation Plan:** [link to datarim/plans/{ID}-plan.md]`)
- `## Archived Tasks` table (one row per archived task)

**Prohibited content** — must go to dedicated files:
- Credentials, secrets, access policies → `documentation/credentials/`
- Specification templates, conventions → `skills/` or `documentation/`
- Audit reports → `datarim/docs/` or `documentation/`
- Infrastructure runbooks → `documentation/infrastructure/`
- Code blocks > 50 lines → external file with link

### File Size Guards

Before writing to `tasks.md` or `activeContext.md`, check file size:

| File | Warn threshold | Hard limit | Action at limit |
|------|---------------|------------|-----------------|
| `tasks.md` | 3,000 lines | 5,000 lines | STOP writing. Inform user: "tasks.md exceeds 5K lines. Run `/dr-optimize` or archive completed tasks before proceeding." |
| `activeContext.md` | 100 lines | 200 lines | Prune the recent-archives section (canonical heading in `templates/activeContext-template.md`) to 5 most recent entries. |

Check command: `wc -l < datarim/tasks.md`

### Concurrent Write Safety

Before modifying `tasks.md`:
1. Note the file's current `Last Updated` timestamp line.
2. After writing, verify the timestamp you read matches — if it changed between read and write, another session modified the file.
3. If conflict detected: re-read the file, merge your changes manually, do NOT overwrite blindly.

## Task Context Tracking

`activeContext.md` tracks all active tasks:

<!-- gate:history-allowed -->
```markdown
# Active Context

## Active Tasks

- **TASK-0001** — Description (Level 2, started 2026-04-18)
- **TASK-0002** — Description (Level 3, started 2026-04-17)

## Последние завершённые

- **TASK-0000** ✅ (2026-04-17) → Summary. `archive-TASK-0000.md`.
```
<!-- /gate:history-allowed -->

### Task Status Lifecycle

```text
not_started → in_progress → completed → archived
     ↓              ↑
   paused ←────────┘
```

### Archive Command Behavior

`/dr-archive` must:

1. **Verify clean git status** for every repo touched by the task. If dirty, STOP and force commit/accept/abort decision — never archive silently over uncommitted changes. (Key lesson: applied ≠ committed ≠ canonical.)
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

#### Area Prefixes (universal, owned by Datarim runtime)

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
| `SEC` | Security |
| `ROB` | Rules of Robotics (universal AI governance) |
| `TUNE` | Datarim self-improvement |

#### Project Prefix Resolution

Datarim is stack-agnostic and ecosystem-agnostic — it does not embed names of specific consumer projects. Project-prefix registries live in the consumer's own `CLAUDE.md`, declared as a `## Task Prefix Registry` section with a Markdown table:

```markdown
## Task Prefix Registry

| Prefix | Project | Archive Subdir |
|--------|---------|----------------|
| EXAMPLE | Example project | example |
```

`Archive Subdir` MUST match `^[a-z][a-z0-9-]*$` (single lowercase path component, no `/`, no `..`).

Resolution algorithm (implemented in `scripts/datarim-doctor.sh`):

1. **Area prefix:** look up the Area Prefixes table above. If matched → use that area subdir.
2. **Project prefix:** walk up the directory tree from the Datarim root; for each `CLAUDE.md` encountered, parse `## Task Prefix Registry` and search for a row with the requested prefix. First match wins.
3. **Fallback:** if neither matched → `general`.

Each ecosystem (or each project that owns a registry) declares its own prefixes in its own `CLAUDE.md`. Adding a new project does not require a Datarim framework change.

### Deprecated Namespace

`BACKLOG-XXXX` is deprecated for new work. Historical references may remain in archives.

### Rename Policy

A task ID changes only by explicit request. If renamed, update all references atomically.

### Pre-Spawn ID-Claim Probe

When a PRD's «Spawned Backlog Items» table assigns sequential IDs to a batch <!-- gate:history-allowed -->(e.g. `XYZ-0011..XYZ-0015`)<!-- /gate:history-allowed -->, probe ALL THREE claim surfaces before finalising the assignment — do not rely on an archive-only «next free» calculation captured at `/dr-init` time.

**Required surfaces:**

1. `documentation/archive/<area>/archive-<PREFIX>-*.md` — historical completions.
2. `datarim/tasks.md` — active in-progress / not-started one-liners.
3. `datarim/backlog.md` — pending / blocked-pending one-liners.

The first free ID is `max(claimed across all three) + 1`. Archive-only probe is insufficient: a pending row in `backlog.md` from a parallel session, added between `/dr-init` and `/dr-plan`, will claim an ID that the archive does not yet know about. The collision becomes visible only when `/dr-do` is invoked against the colliding ID, by which time downstream artefacts (PRD spawned-items table, plan dependency graph, sibling task `Depends:` references) have all baked in the wrong number.

**When to apply.** Any agent finalising a multi-ID spawn from a PRD — typically `/dr-plan` for L4 epics with a Spawned Backlog Items table. The probe is a 3-file `grep` + `sort -V` + max-pick; cost is sub-second.

**Anti-pattern.** Treating the `Next free: <PREFIX>-NNNN` line written at `/dr-init` time as authoritative N days later. That line is a snapshot, not a contract; the registry mutates between captures.

**Recovery.** If a collision is discovered post-spawn, the canonical fix is atomic multi-surface amendment (see `skills/ai-quality/SKILL.md` § Atomic Multi-Surface Plan Amendment): rename the newer batch in `backlog.md`, the owning PRD's Spawned Backlog Items table (with `AMENDED YYYY-MM-DD` marker), the plan's dependency graph + critical path + V-AC mapping, the init-task append-log, and every sibling `Depends:` / `Concurrent with` reference — all in the same revision cycle, with grep cross-check to prove zero stale residue.
