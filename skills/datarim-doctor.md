---
name: datarim-doctor
description: Schema and migration semantics for /dr-doctor — thin one-liner contract, YAML description schema, 5-pass migration, data-loss safety contract, conflict resolution. Loaded by /dr-doctor + /dr-init self-heal + /dr-archive line-format gate.
---

# Datarim Doctor — Schema and Migration Semantics

This skill is the runtime knowledge module for `/dr-doctor`. It defines the **canonical thin contract** that operational files (`tasks.md`, `backlog.md`, `activeContext.md`) MUST conform to, the **5-pass migration algorithm** that `scripts/datarim-doctor.sh` applies, and the **data-loss safety contract** that wraps every `--fix` invocation.

Loaded by:
- `/dr-doctor` (always)
- `/dr-init` self-heal (when `--quiet` probe returns exit 1)
- `/dr-archive` line-format gate (on failure, to explain non-compliance)

Not loaded by other commands — they read the operational files as opaque indexes and follow the description-file pointer.

## Why Thin Indexes

Operational files are **indexes**, not content. Each line answers four questions: which task, what state, where the description lives. No prose, no requirements, no plan content lives in `tasks.md` / `backlog.md`.

Goals:
- **Bounded context** — agents read 1 KB index instead of 100 KB monolith.
- **Single source of truth per task** — description, ACs, constraints live in one file: `datarim/tasks/{TASK-ID}-task-description.md`.
- **Greppable state** — line format is machine-parseable; status changes are 1-line diffs.
- **Idempotent migrations** — `/dr-doctor` can run any number of times without drift.

`progress.md` is **abolished**, and the legacy `activeContext.md § Последние завершённые` rolling log is **abolished** as well. Completion history lives only in `documentation/archive/{area}/archive-{TASK-ID}.md` and git log.

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

**Active-Tasks-only mirror.** The file is bounded (≤ 30 lines) and contains a strict mirror of `tasks.md § Active`:

<!-- gate:history-allowed -->
```markdown
# Active Context

## Active Tasks
<!-- strict mirror of tasks.md § Active — identical lines, identical order -->

- TUNE-0071 · in_progress · P1 · L3 · Index-Style Refactor → tasks/TUNE-0071-task-description.md

## Last Updated
YYYY-MM-DD HH:MM · short summary
```
<!-- /gate:history-allowed -->

The legacy `## Последние завершённые` section is **abolished** — `/dr-doctor` removes it during Pass 3. Completion history must be looked up in `documentation/archive/` or git log instead of being mirrored into a rolling section.

### `progress.md`

**Abolished.** `/dr-doctor --fix` deletes the file unconditionally during Pass 3. No rolling completion log is maintained anywhere; per-task notes live in `datarim/tasks/{TASK-ID}-task-description.md` § Implementation Notes, and historical context lives in `documentation/archive/`.

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

## Migration Algorithm (`--fix`) — 5 passes

Applied by `scripts/datarim-doctor.sh --fix`. Single transactional sequence guarded by the data-loss safety contract (see next section). Atomic per file via `mv tmp file`.

### Pass 1 — Description files (build cache)

1. Walk `datarim/tasks.md` and `datarim/backlog.md` for legacy block-style headings: `^### ([A-Z]+-[0-9]+):\s*(.+)$`.
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

### Pass 3 — `activeContext.md` + `progress.md` retirement

11. Convert any legacy `**Current Task:** {ID}` line into `## Active Tasks` list with the corresponding one-liner; mirror is bounded to ≤ 30 lines.
12. Strip the `## Последние завершённые` section if present (abolished — see § activeContext.md thin contract above).
13. Delete `progress.md` if it exists.

### Pass 4 — `backlog-archive.md` migration

14. AWK section-state machine + per-ID dispatch reads legacy `backlog-archive.md`.
15. Cancelled entries → synthesised stubs in `documentation/archive/cancelled/archive-{TASK-ID}.md` (header notes `synthesised from backlog-archive.md by datarim-doctor.sh Pass 4`).
16. Completed entries → verify-or-synthesise into area-specific `documentation/archive/{area}/archive-{TASK-ID}.md`; unrecognised area falls back to `general/`.
17. Conflict policy is configurable via `--conflict-policy=prompt|keep|overwrite|skip|abort` (default `prompt`; auto-`skip` in non-TTY); `--no-prompt` is the canonical CI alias for `skip`.
18. The legacy `backlog-archive.md` is preserved in-tree as `backlog-archive.md.pre-v2.bak` (sidecar; operator-visible).

### Pass 6 — Operational-files archive section migration

Strips legacy archive sections (`## Archived` in `tasks.md` / `backlog.md`; `### Archived`, `### Recently Archived`, `## Последние завершённые` in `activeContext.md`) and migrates each archive bullet to a canonical `documentation/archive/{area}/archive-{TASK-ID}.md` doc. The canonical thin-index contract (§ activeContext.md thin contract above, § Operational File Schema) prohibits archive sections in operational files: completion history lives in `documentation/archive/`, recency hint is computed at runtime via `/dr-status --recent N`. Pass 6 enforces that contract.

Four archive-bullet shapes are recognised (priority S1 → S2 → S4 → S3):

- **S1 (arrow-link):** `- **TASK-ID** — title (YYYY-MM-DD) → documentation/archive/{area}/archive-TASK-ID.md`
- **S2 (status-paren):** `- **TASK-ID** (status, YYYY-MM-DD) — title` (status ∈ `completed | cancelled | …`)
- **S4 (mid-bold-context):** `- **TASK-ID** context-words — title` (context word(s) between `**ID**` and em-dash)
- **S3 (plain-bold):** `- **TASK-ID** — title` (no date, no link, no mid-bold context)

Task IDs may be **compound** — `DEV-1226`, `DEV-1212-S8`, `DEV-1196-FOLLOWUP-lock-ownership-doc`. Numeric component (`-[0-9]{4}`) is required; suffix `(-[A-Za-z0-9]+)*` is optional.

Per bullet:

1. Validate task ID matches `^[A-Z]{2,10}-[0-9]{4}(-[A-Za-z0-9]+)*$`. Invalid → preserve in operational file with manual-migration marker.
2. **Explicit-pointer dispatch:** if bullet body contains `→ documentation/archive/{path}.md`, prefer that path as canonical; otherwise fall back to `prefix_to_area()` (TUNE-0076 mapping) → `documentation/archive/{area}/archive-{ID}.md`.
3. Path-traversal safety: canonical path MUST stay under `documentation/archive/`; violation rejects explicit pointer and falls back to `prefix_to_area`. If fallback also escapes → preserve, warn.
4. **Verified case** — canonical archive exists with `{ID}` literal inside → strip bullet from operational file.
5. **Missing case** — canonical absent at computed path → defensive `find documentation/archive/ -name "archive-{ID}.md"` (depth ≤ 3) checks every area subdir; if found with ID literal, strip bullet with warning `archive at unexpected area`. Otherwise synthesise stub with frontmatter (`id`, `title`, `status`, `{status}_at`, `source: synthesised from operational-file by datarim-doctor.sh Pass 6`, `original_block_sha`) + body = original bullet content; strip bullet.
6. **Collision case** — canonical archive exists but does NOT contain `{ID}` literal → invoke `resolve_conflict()` (`--no-prompt` defaults to skip in non-TTY); on skip, preserve bullet in operational file with `<!-- bullets pending manual migration … -->` marker; on overwrite, synthesise stub.

**Headerless fallback:** operational files without any archive section header are processed line-by-line. Bullets parseable via S1–S4 are candidates; bullets with explicit non-terminal status (`in_progress`, `not_started`, `pending`, `blocked`, `approved`, `review`, `active`) are passed through as active content. Other parseable bullets follow the same dispatch as the headered branch (explicit pointer → defensive find → synthesise). Non-parseable lines (one-liner thin-index entries, headers, frontmatter) pass through unchanged.

Unparseable bullets (no shape match) → preserve with warning `Pass 6: unparseable archive bullet`. Operator fixes manually.

After per-file processing, Doctor logs a one-line summary: `Pass 6 {file}: parsed={N} stripped={M} synthesised={K} skipped={L}`. Distributed users see exactly what migrated; tarball backup (TUNE-0077) covers rollback.

**Idempotent:** files without any archive header early-return; second `--fix` on a migrated tree produces zero changes.

<!-- security:counter-example -->
*Counter-example — what Doctor MUST NOT do (Approach D, rejected by QA TUNE-0085):* add a whitelist exception that preserves archive sections by design. This would legalise non-compliant pattern, accumulate token-bloat in operational files (12-18 KB on typical installations × 10-30 reads per session = 120-540 KB lost tokens), and contradict the canonical contract `datarim-system.md § activeContext.md thin contract` («one section only», v1.19.1). Migration, not preservation, is the correct enforcement.
<!-- /security:counter-example -->

### Pass 5 — Post-fix re-scan

19. After `--fix` finishes the four mutating passes, the script composes the existing scan dispatch in dry-run mode and re-validates the tree.
20. Asserts: post-fix zero findings, `.pre-v2.bak` sidecar present (when Pass 4 ran), and an immediate second `--fix` is a no-op (idempotency).
21. Any failure here is treated as a Pass-4 regression and triggers the safety contract's restore path.

### Idempotency Guard

Before Pass 1: if every operational file is already in canonical shape — zero `### TASK-ID:` headings in `tasks.md` / `backlog.md`, no legacy `backlog-archive.md` (or only the `.pre-v2.bak` sidecar remains), `progress.md` does not exist, no `## Последние завершённые` section in `activeContext.md`, and every bullet line matches the canonical regex — exit 0 immediately. Cheap probe used by `/dr-init` self-heal.

## Data-Loss Safety Contract

Defence-in-depth around `--fix` mode. Every `--fix` invocation MUST satisfy all four rails; violation of any rail aborts the run with state preserved.

- **Pre-write tarball backup.** Before any mutation, the script writes a `umask 077` tarball of the entire `datarim/` root to `${DATARIM_DOCTOR_BACKUP_DIR:-/tmp}/datarim-backup-{TS}.tgz`. Path is surfaced in the success summary so the operator can locate it for manual rollback.
- **Sidecar copy.** Every legacy file mutated by Pass 4 also gets a `.pre-v2.bak` sidecar in-tree alongside the original (operator-visible, survives normal git workflows). Pass 5 asserts the sidecar exists.
- **Count invariant.** Doctor counts task entries before mutation (`PARSED_COUNT`) and after rewrite (`EMITTED_COUNT`). Invariant: `EMITTED_COUNT ≥ PARSED_COUNT`. Violation triggers `restore_backup_and_die()`: removes mutated state in-place, `tar -xzf` the pre-write tarball back over the tree, and exits 2 with `emitted=N < parsed=M (data loss detected)`.
- **Symlink-default uniformity.** Under the symlink-default install (v1.17.0+), `~/.claude/scripts/datarim-doctor.sh` is a directory-symlink target of the canonical Datarim repo path. Divergence between runtime and repo is impossible by construction; rogue v2 binaries cannot be silently dropped on top of the runtime.

The contract is a hard precondition for any future `--fix` change: new mutating passes MUST plug into the same `PARSED_COUNT` / `EMITTED_COUNT` accounting and respect the tarball restore path.

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

### Pass 4 archive-file conflicts

Resolved by `--conflict-policy`:
- `prompt` (default in TTY) — interactive choice per conflicting `archive-{TASK-ID}.md`.
- `keep` — preserve existing archive file untouched, log skip.
- `overwrite` — replace existing archive file with synthesised stub, original moved to `.bak-{TS}`.
- `skip` — same as `keep` but quiet (default in non-TTY; `--no-prompt` alias).
- `abort` — fail the migration on first conflict; safety contract restores the tree.

### Path traversal in legacy entries

`scripts/lib/canonicalise.sh` rejects any path that resolves outside `$DATARIM_ROOT` (lexical canonicalisation, no I/O). Tool exits 4. Operator inspects the entry manually.

## Edge Cases

- **Bash 3.2 (macOS default)** — tool uses two-pass grep+awk parser, NOT NUL-delimited reads. Verified across bash 3.2 / 4.4 / 5.x.
- **Empty `datarim/tasks.md`** — exit 0; nothing to do.
- **Title with `→` character** — escaped or rejected (regex disallows). Operator must rename.
- **Non-UTF-8 file** — tool refuses; operator must convert (`iconv`).
- **Concurrent invocation** — `flock $DATARIM_ROOT/.dr-doctor.lock`. Second instance exits 3.
- **Read-only filesystem** — exit 2 on first write attempt; partial state preserved (atomic per file). Tarball restore covers the partial mutation.
- **Missing `tasks/` subdirectory** — created with `mkdir -p` before any description file write.
- **Missing `documentation/archive/{area}/`** — created with `mkdir -p` during Pass 4 dispatch.

## CLI Surface (reference)

```
scripts/datarim-doctor.sh [OPTIONS]

OPTIONS:
  --fix                       Apply fixes (default: dry-run)
  --scope=<scope>             One of: tasks|backlog|active|backlog-archive|progress|descriptions|all
                              (default: all)
  --root=<path>               Datarim root (default: walk up from $PWD)
  --quiet                     Exit-code only (used by /dr-init self-heal)
  --no-prompt                 Skip Pass 4 conflicts (alias for --conflict-policy=skip)
  --conflict-policy=<policy>  One of: prompt|keep|overwrite|skip|abort
                              (default: prompt; auto-skip in non-TTY)
  --help

ENVIRONMENT:
  DATARIM_DOCTOR_BACKUP_DIR   Override pre-write tarball directory (default: /tmp)

EXIT CODES:
  0   Compliant (or --fix succeeded)
  1   Non-compliant findings (dry-run)
  2   Migration error (--fix aborted; tarball restored, state preserved)
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
- `tests/datarim-doctor.bats` — covers compliance detection, 5-pass migration, safety contract (tarball + invariant + restore), conflict policies, regex compliance, CLI/UX.
- `skills/datarim-system.md` — broader Datarim file layout and path resolution.
