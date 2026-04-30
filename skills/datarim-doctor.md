---
name: datarim-doctor
description: Schema and migration semantics for /dr-doctor — thin one-liner contract, YAML description schema, conflict resolution. Loaded by /dr-doctor + /dr-init.
---

# Datarim Doctor — Schema and Migration Semantics

This skill is the runtime knowledge module for `/dr-doctor`. It defines the **canonical thin contract** that operational files (`tasks.md`, `backlog.md`, `activeContext.md`) MUST conform to, and the **migration algorithm** that `scripts/datarim-doctor.sh` applies. Source: prior incident.

Loaded by:
- `/dr-doctor` (always)
- `/dr-init` Step 0.6 self-heal (when probe returns exit 1)
- `/dr-archive` Step 0.1.4 line-format gate (on failure, to explain non-compliance)

Not loaded by other commands — they should read the operational files as opaque indexes and follow the description-file pointer.

## Why Thin Indexes

Operational files are **indexes**, not content. Each line answers four questions: which task, what state, where the description lives. No prose, no requirements, no plan content lives in `tasks.md` / `backlog.md`.

Goals:
- **Bounded context** — agents read 1 KB index instead of 100 KB monolith.
- **Single source of truth per task** — description, ACs, constraints live in one file: `datarim/tasks/{TASK-ID}-task-description.md`.
- **Greppable state** — line format is machine-parseable; status changes are 1-line diffs.
- **Idempotent migrations** — `/dr-doctor` can run any number of times without drift.

`progress.md` is **abolished**. Its content (last-completed log) folds into `activeContext.md` § «Последние завершённые».

## Operational File Schema

### `tasks.md` and `backlog.md` line format

Canonical regex (anchored, single-line):

```
^- ([A-Z]{2,10}-[0-9]{4}) · (STATUS) · P[0-3] · L[1-4] · (.{1,80}) → tasks/\1-task-description\.md$
```

Where `STATUS` ∈:
- `tasks.md`: `in_progress|blocked|not_started`
- `backlog.md`: `pending|blocked-pending|cancelled`

Separator: `·` (U+00B7 MIDDLE DOT, NOT bullet, NOT period). Arrow: `→` (U+2192). Title length: 1–80 chars, no newlines, no `→`.

Examples (compliant):

<!-- gate:history-allowed -->
```
- TUNE-0071 · in_progress · P1 · L3 · Index-Style Refactor → tasks/TUNE-0071-task-description.md
- INFRA-0099 · pending · P2 · L2 · Vault MFA Rollout → tasks/INFRA-0099-task-description.md
```
<!-- /gate:history-allowed -->

Section headers (`## Active`, `## Pending`, etc.) and blank lines are allowed — only bullet lines starting with `- {PREFIX}-{NNNN}` are validated against the regex.

### `activeContext.md` thin contract

Three sections, all index-style:

<!-- gate:history-allowed -->
```markdown
## Active Tasks
- TUNE-0071 · in_progress · P1 · L3 · Index-Style Refactor → tasks/TUNE-0071-task-description.md

## Last Updated
YYYY-MM-DD HH:MM · prior incident — short summary

## Последние завершённые
- 2026-04-30 · TUNE-0071 · Index-Style Refactor → ../documentation/archive/framework/archive-TUNE-0071.md
```
<!-- /gate:history-allowed -->

Last-completed line regex:

```
^- ([0-9]{4}-[0-9]{2}-[0-9]{2}) · ([A-Z]{2,10}-[0-9]{4}) · (.{1,80}) → \.\./documentation/archive/[a-z]+/archive-\2\.md$
```

Keep ≤ 20 entries; oldest fall off (older entries already exist in `archive/` directory).

### `progress.md`

**Abolished.** `/dr-doctor --fix` deletes the file after promoting any unique last-completed entries into `activeContext.md` § «Последние завершённые».

If a project legitimately needs running progress notes, those belong in the per-task description file (`datarim/tasks/{TASK-ID}-task-description.md` § Implementation Notes) or in the archive. Not in a global running file.

## Description File Contract

`datarim/tasks/{TASK-ID}-task-description.md` is the **only** place that holds the task's content. Format:

### YAML Frontmatter (12 fixed keys, all required)

```yaml
---
id: <TASK-ID>                 # regex ^[A-Z]{2,10}-[0-9]{4}$
title: <string>               # ≤ 80 chars, single line
status: <enum>                # in_progress|blocked|not_started|pending|blocked-pending|cancelled
priority: <enum>              # P0|P1|P2|P3
complexity: <enum>            # L1|L2|L3|L4
type: <string>                # free-form (e.g. framework, infra, content, bugfix)
project: <string>             # free-form (e.g. Datarim, Arcanada, Verdicus)
started: <date>               # YYYY-MM-DD
parent: <TASK-ID|null>        # null if no parent
related: <list[TASK-ID]>      # YAML list, empty list ok
prd: <relpath|null>           # e.g. prd/PRD-{TASK-ID}.md, null if none
plan: <relpath|null>          # e.g. plans/{TASK-ID}-plan.md, null if none
---
```

All 12 keys are mandatory. Schema is closed — additional keys are NOT added by `/dr-doctor`. Project-specific extensions go inside the body, not in frontmatter.

### Body (markdown, ≤ 250 lines total)

Five canonical sections (in order):

```markdown
## Overview
2–5 sentences. Problem + outcome.

## Acceptance Criteria
- [ ] AC-1: …
- [ ] AC-2: …

## Constraints
Bullet list of immutable boundaries (security, performance, compatibility).

## Out of Scope
Explicit non-goals. What this task does NOT do.

## Related
Cross-references: parent PRD, sibling tasks, prior reflection notes.
```

Implementation Notes (free-form scratch, optional) MAY follow as `## Implementation Notes`.

Discussion / decisions log MAY follow as `## Decisions`.

Anything beyond ~250 lines is a smell — split into a PRD or design doc.

## Migration Algorithm (`--fix`)

Applied by `scripts/datarim-doctor.sh --fix`. Single transactional pass per file (atomic rename via `mv`).

### Pass 1 — Description files (build cache)

1. Walk `datarim/tasks.md` for legacy block-style headings: `^### ([A-Z]+-[0-9]+):\s*(.+)$`.
2. For each legacy block, extract the body until the next `### ID:` heading or section break.
3. Parse known fields (case-insensitive, leading `- ` or `* ` allowed):
    - **Status / Status:** → frontmatter `status`
    - **Priority / Приоритет:** → frontmatter `priority`
    - **Complexity / Уровень / Level:** → frontmatter `complexity`
    - **Type / Тип:** → frontmatter `type`
    - **Started / Дата / Date / Date Started:** → frontmatter `started`
    - **Parent / Родитель / Parent task:** → frontmatter `parent`
    - **Related / Связанные:** → frontmatter `related`
    - **PRD:** → frontmatter `prd`
    - **Plan:** → frontmatter `plan`
4. Heading first capture group → `id`. Second capture group → `title` (truncated to 80 chars on word boundary).
5. Remaining body → write under `## Overview` (until first sub-heading) and pass through other sub-headings unchanged.
6. Normalize fields:
    - Status case-folded; alias `pending` ↔ `not_started` resolved by source file (tasks.md → `not_started`/`in_progress`/`blocked`; backlog.md → `pending`/`blocked-pending`/`cancelled`).
    - Priority normalized to `P[0-3]`; missing → `P3`.
    - Complexity normalized to `L[1-4]`; missing → `L2` (most common default).
    - Started missing → today (UTC).
    - Project missing → derive from prefix (`TUNE` → `Datarim`, `INFRA` → `Arcanada`, …) or `unknown`.
7. Write to `datarim/tasks/{TASK-ID}-task-description.md`. **Skip if already exists with valid frontmatter** (idempotent).

### Pass 2 — Operational files (rewrite indexes)

8. Generate one-liner per task ID (regex above).
9. Group by section: tasks.md → `## Active` (in_progress/blocked/not_started); backlog.md → `## Pending` (pending/blocked-pending/cancelled).
10. Atomic rewrite via `mv tasks.md.tmp tasks.md`.

### Pass 3 — `activeContext.md`

11. Convert any legacy `**Current Task:** {ID}` line into `## Active Tasks` list with the corresponding one-liner.
12. Preserve existing thin sections untouched.

### Pass 4 — `progress.md` retirement

13. Extract last-completed entries (any line matching `archive-{ID}.md` reference).
14. Merge into `activeContext.md` § «Последние завершённые», dedupe by `(date, id)`, cap at 20.
15. Delete `progress.md`.

### Idempotency Guard

Before Pass 1: if `tasks.md` and `backlog.md` contain ZERO `### TASK-ID:` headings AND ZERO bold-id legacy lines AND `progress.md` does not exist AND every bullet line matches the canonical regex → exit 0 immediately. Cheap probe for `/dr-init` Step 0.6.

## Conflict Resolution

### Description file already exists

- **Compliant frontmatter (12 keys, ID matches)** → skip; do not overwrite.
- **Frontmatter missing or wrong ID** → backup existing to `tasks/{TASK-ID}-task-description.md.bak-{timestamp}` and write canonical version. Operator merges manually if needed.
- **File exists for ID that has no entry in tasks.md/backlog.md** → leave alone (orphan description; operator decides).

### Duplicate IDs across tasks.md and backlog.md

If a task ID appears in both files (legacy state):
- Status comes from `tasks.md` (active wins over pending).
- Backlog entry is dropped from `backlog.md`.
- Single description file written.

### Status/priority/complexity contradicts

Source-file state wins (tasks.md status overrides description's frontmatter `status` if they disagree). Description frontmatter is rewritten to match.

### Path traversal in legacy entries

`scripts/lib/canonicalise.sh` rejects any path that resolves outside `$DATARIM_ROOT` (lexical canonicalisation, no I/O). Tool exits 4. Operator inspects the entry manually.

## Edge Cases

- **Bash 3.2 (macOS default)** — tool uses two-pass grep+awk parser, NOT NUL-delimited reads. Verified across bash 3.2 / 4.4 / 5.x.
- **Empty `datarim/tasks.md`** — exit 0; nothing to do.
- **Title with `→` character** — escaped or rejected (regex disallows). Operator must rename.
- **Non-UTF-8 file** — tool refuses; operator must convert (`iconv`).
- **Concurrent invocation** — `flock $DATARIM_ROOT/.dr-doctor.lock`. Second instance exits 3.
- **Read-only filesystem** — exit 2 on first write attempt; partial state preserved (atomic per file).
- **Missing `tasks/` subdirectory** — created with `mkdir -p` before any description file write.

## CLI Surface (reference)

```
scripts/datarim-doctor.sh [OPTIONS]

OPTIONS:
  --fix               Apply fixes (default: dry-run)
  --scope=<scope>     One of: tasks|backlog|active|progress|descriptions|all (default: all)
  --root=<path>       Datarim root (default: walk up from $PWD)
  --task-id=<id>      Limit operations to one TASK-ID (debug)
  --no-color          Plain output
  --quiet             Exit-code only (used by /dr-init Step 0.6)
  --help

EXIT CODES:
  0   Compliant (or --fix succeeded)
  1   Non-compliant findings (dry-run)
  2   Migration error (--fix aborted; state preserved)
  3   Concurrent invocation (lock held)
  4   Path traversal / security violation
  64  Usage error
```

## Validation (CI gate)

`pre-archive-check.sh` runs the line-format validator before `/dr-archive` proceeds. Lines that don't match the canonical regex block the archive with: `BLOCK: {file} contains non-compliant lines (run /dr-doctor)`.

Escape hatch: `pre-archive-check.sh --no-schema-check` (used during in-flight migration; not for normal use).

## See Also

- `commands/dr-doctor.md` — operator-facing wrapper.
- `scripts/datarim-doctor.sh` — implementation.
- `tests/datarim-doctor.bats` — 15 cases covering compliance detection, migration, security, regex compliance, CLI/UX.
- `skills/datarim-system.md` — broader Datarim file layout and path resolution.
