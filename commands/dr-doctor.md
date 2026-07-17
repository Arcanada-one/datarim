---
name: dr-doctor
description: Diagnose and repair Datarim operational files — migrate to thin one-liner schema, externalize task descriptions, abolish progress.md.
---

# /dr-doctor — Datarim Structural Doctor

**Role**: Planner Agent (compact)
**Source**: `$HOME/.claude/agents/planner.md`
**Tool**: `scripts/datarim-doctor.sh`

## When to Run

- **Manually** — when `tasks.md` / `backlog.md` / `progress.md` grow huge or mix block-style entries with thin one-liners.
- **Auto-suggested by `/dr-init` Step 2.4** — when structural compliance probe (`datarim-doctor.sh --quiet`) returns exit 1.
- **After upgrading to Datarim v1.19.0+** — first run migrates legacy block-style tasks to the canonical thin schema.
- **Before `/dr-archive`** — `pre-archive-check.sh` line-format gate may direct here on non-compliant operational files.

Not a periodic cleanup. Idempotent: a second run on a compliant tree is a no-op.

## Instructions

1. **LOAD**: Read `$HOME/.claude/agents/planner.md` and adopt that persona.
2. **RESOLVE PATH**: Walk up from cwd to find `datarim/`. If not found anywhere → tell user to run `/dr-init`. Do NOT create. See `$HOME/.claude/skills/datarim-system/SKILL.md` § Path Resolution Rule.
3. **LOAD SKILL**: Read `$HOME/.claude/skills/datarim-doctor/SKILL.md` for schema spec, conflict resolution, and edge-case handling.
4. **PARSE ARGS** (passed by user or by `/dr-init` Step 2.4):
    - `--fix` — apply migration. Default: dry-run (report findings only).
    - `--scope=<scope>` — `tasks|backlog|active|progress|descriptions|all`. Default `all`.
    - `--task-id=<id>` — limit to one task ID (debug).
    - `--quiet` — exit-code only output (used by `/dr-init` self-heal probe).
    - `--no-color` — plain output.
5. **DRY-RUN FIRST**: Always run `scripts/datarim-doctor.sh --root="$DATARIM_ROOT"` (without `--fix`) before applying. Capture finding counts:
    - Legacy block-style `### TASK-ID:` headings
    - Legacy bold-id `- **TASK-ID** ...` entries
    - Non-compliant bullet lines (any `- TASK-XXXX` not matching the canonical regex)
    - `progress.md` existence (slated for deletion)
6. **PRESENT REPORT**: Surface a 5-row count table to the operator:
    ```
    | Category                                       | Count |
    |------------------------------------------------|-------|
    | Legacy block-style (### ID:)                   | N     |
    | Legacy bold-id (- **ID** ...)                  | N     |
    | Non-compliant bullet                           | N     |
    | progress.md exists                             | 0/1   |
    | Terminal backlog entries (prunable / surfaced) | P / S |
    ```
    If all zeros and P=0 / S=0 → `datarim/` is compliant; exit 0 silently (no migration to perform).
7. **CONFIRMATION GATE** (interactive sessions only — `[ -t 0 ]`):
    - If invoked **without** `--fix` and findings > 0: prompt «Run `/dr-doctor --fix` to apply migration? [Y/n]» — default Y.
    - Y → re-invoke `scripts/datarim-doctor.sh --root="$DATARIM_ROOT" --fix`.
    - n → print warning and exit 0.
    - Non-tty (`! [ -t 0 ]`) → never prompt; if invoked without `--fix`, just exit 1 with finding count.
    - **`/dr-init` Step 2.4 path**: caller passes `--quiet`; this command must not prompt — it just runs the probe and reports exit code.
8. **APPLY** (when `--fix` is set):
    - Execute `scripts/datarim-doctor.sh --root="$DATARIM_ROOT" --fix`.
    - Tool acquires `flock` on `$DATARIM_ROOT/.dr-doctor.lock` (exit 3 if concurrent run).
    - Path-traversal guard via `lib/canonicalise.sh` (exit 4 on violation).
    - On migration error → tool exits 2; **state preserved** (writes are atomic per file). Surface error to operator.
9. **POST-MIGRATION VERIFY**:
    - Re-run `datarim-doctor.sh --root="$DATARIM_ROOT"` (no `--fix`) — must exit 0.
    - Spot-check: list newly created `datarim/tasks/{TASK-ID}-task-description.md` files (count matches block-style legacy count).
    - Confirm `progress.md` is gone (if it existed before).
    - Confirm `tasks.md` and `backlog.md` line count shrank to one-liner-per-task.
10. **BACKLOG TERMINAL-TASK CLEANUP** (orthogonal pass, separate from schema migration):
    - Invoke `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/prune-backlog-terminal.sh" --root "$DATARIM_ROOT" --check`.
    - The tool reports `prunable: P  surfaced: S  kept: K`:
      - `prunable` — terminal entries (`done`/`archived`/`completed`, or `cancelled` with an archive doc) that can be safely removed.
      - `surfaced` — terminal entries WITHOUT a corresponding `documentation/archive/{area}/archive-{ID}.md`; these are **never silently dropped** — preserved in `backlog.md` and reported here for operator attention. Route each surfaced ID as a `MAINT-*` follow-up to create the missing archive doc.
      - `kept` — non-terminal entries (`pending`, `blocked-pending`, or transient `cancelled`) left untouched.
    - **Dry-run only** (no `--fix`): report the counts in the 5-row table row; do NOT apply changes yet.
    - **When `--fix` is set** (Step 8 apply path or user explicitly passes `--fix`): also invoke with `--fix` to atomically rewrite `backlog.md`, removing only the prunable entries. Surfaced entries are preserved; the tool emits one `surfaced: {ID}` line per preserved entry.
    - The cleanup is kept **orthogonal** to `scripts/datarim-doctor.sh` (schema migrator) per CLAUDE.md § Validation Discipline — do NOT add prune logic inside `datarim-doctor.sh`.

11. **REPORT**: Produce a migration summary:
    - Files rewritten: `tasks.md`, `backlog.md`, `activeContext.md` (if touched).
    - Description files created: count.
    - `progress.md`: deleted (if existed) — last-completed entries promoted to `activeContext.md` § «Последние завершённые». <!-- allow-non-ascii: literal-russian-active-context-section-name-cited-from-canonical-schema -->
    - Terminal backlog entries pruned / surfaced counts from step 10.
    - Idempotency confirmed (second dry-run exit 0).

12. **INIT-TASK PRESENCE ADVISORY** (orthogonal content validator, MUST run after the migration summary; never blocks):
    - Invoke `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-init-task-presence.sh" --all --root "$DATARIM_ROOT"`.
    - Stream the findings list to the operator. Each line carries the severity prefix and the task ID:
      - `info: <ID> init-task missing (task age <30d; rolling 30d soft window)` — fresh task without init-task, soft-window protected.
      - `warn: <ID> init-task missing (task age ≥30d; rolling 30d soft window)` — stale task without init-task, operator may retro-backfill.
    - `--all` mode is **advisory-only** — exit code is always 0; never block `/dr-init` Step 2.4 self-heal or `/dr-doctor` itself.
    - The validator is the canonical Init-Task Presence pass per `skills/init-task-persistence/SKILL.md` § Validation. Kept orthogonal to `scripts/datarim-doctor.sh` per CLAUDE.md § Validation Discipline (operational-file migration ↔ content validation are separate concerns).

13. **DOCS-MIGRATION SELF-HEAL** (orthogonal pass, 2.49.0+; offers `docs/` → `documentation/` migration for a consumer repo that has not yet adopted the renamed canon):
    - **Why:** as of 2.49.0 the canonical documentation root is `documentation/`, and the `/dr-optimize` drift detector hard-flips — a repo still on legacy `docs/` is flagged as drift. This pass is the remediation path so the operator is not merely told they "drift".
    - **Boundary:** this is a SEPARATE concern from the `datarim/` operational-file migration above. It operates on the repo's product-docs (`<repo>/docs/`), which lives OUTSIDE `$DATARIM_ROOT`. Per CLAUDE.md § Validation Discipline it MUST stay a sibling executor — it is NOT a `--scope` of `scripts/datarim-doctor.sh`.
    - Invoke the detector (dry-run): `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/docs-migrate.sh" --repo "<repo-root>" --check --quiet`.
      - exit 0 → `documentation/` already canonical (or no docs) — no-op, say nothing.
      - exit 1 → legacy `docs/` found. Report it in the findings table (`docs-migration: legacy docs/ → documentation/ available`).
      - exit 2 → BOTH `docs/` and `documentation/` present — manual review required; report, do NOT offer auto-fix.
    - **CONFIRMATION GATE** (interactive sessions only — `[ -t 0 ]`): on exit 1, prompt «Migrate `docs/` → `documentation/` now? (git mv + Diátaxis-split + reference rewrite, rollback-safe) [Y/n]» — default Y. On Y → re-invoke with `--fix`. On `n` or non-tty → report only, never mutate.
    - **Idempotent + rollback-safe:** `--fix` tarball-backs-up before any write and restores on a reference-check failure (exit 2); a second `--fix` on a migrated repo is a no-op. Contract + fixtures: `tests/test-docs-migrate.bats`.
    - Kept orthogonal to `scripts/datarim-doctor.sh` per CLAUDE.md § Validation Discipline.

## Read

- `datarim/tasks.md`, `datarim/backlog.md`, `datarim/progress.md`, `datarim/activeContext.md`
- Existing `datarim/tasks/*.md` description files (to skip overwrites if already canonical).

## Write

- Rewrites `datarim/tasks.md`, `datarim/backlog.md`, `datarim/activeContext.md` to thin one-liner schema.
- Creates `datarim/tasks/{TASK-ID}-task-description.md` per legacy block-style entry (YAML frontmatter + body sections).
- Deletes `datarim/progress.md` after preserving last-completed entries into `activeContext.md`.
- Atomically rewrites `datarim/backlog.md` (via `prune-backlog-terminal.sh --fix`) to remove terminal entries whose archive doc exists. Terminal entries without an archive doc are preserved.
- Writes `datarim/.dr-doctor.lock` (transient, auto-released).

Never touches `documentation/archive/`, `datarim/prd/`, `datarim/plans/`, `datarim/creative/`, `datarim/reflection/`. Never touches anything outside `$DATARIM_ROOT`.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Compliant (or `--fix` succeeded) |
| 1 | Non-compliant findings (dry-run) |
| 2 | Migration error (`--fix` aborted; state preserved) |
| 3 | Concurrent invocation (lock held) |
| 4 | Path traversal / security violation |
| 64 | Usage error |

## Failure Modes

- **Lock held (exit 3)** → another `/dr-doctor` or `/dr-init` Step 2.4 probe is running. Wait, then retry.
- **Migration error (exit 2)** → tool aborted mid-flight; partial writes are atomic per file. Inspect `git status -s datarim/`, `git restore datarim/{file}.md` to roll back individual files, then re-run.
- **Path traversal (exit 4)** → `tasks.md` or similar contains a relative path that resolves outside `$DATARIM_ROOT`. Inspect the offending entry manually before re-running.
- **All zeros, but `/dr-archive` still blocks** → file may have a non-compliant line that doctor's regex doesn't classify (e.g. comment line). Run `pre-archive-check.sh --no-schema-check` to surface the exact line.

## Next Steps (CTA)

After `/dr-doctor` finishes, emit a CTA block ([definition](../skills/cta-format/SKILL.md)) per `$HOME/.claude/skills/cta-format/SKILL.md`.

**Routing logic for `/dr-doctor`:**

- Migration applied successfully → primary `/dr-status` (verify thin index renders correctly) + alternative resume of any active task `/dr-do {TASK-ID}`.
- Dry-run only, findings > 0 → primary `/dr-doctor --fix` (apply migration) + alternative `/dr-status` (review state first).
- Already compliant (exit 0, no findings) → primary `/dr-status` + reminder that `/dr-doctor` is idempotent.
- Migration error (exit 2) → primary `/dr-status` (inspect partial state) + alternative `/dr-doctor` (retry after cleanup).
- Always include `/dr-status` as escape hatch.

The CTA block MUST follow the canonical format (numbered list, one primary recommendation marker, `---` HR). Variant-B menu of other active tasks when more than one is active. Exact marker tokens live in `cta-format.md`.
