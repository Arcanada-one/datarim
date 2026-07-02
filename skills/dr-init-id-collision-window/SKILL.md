---
name: dr-init-id-collision-window
description: |
  Detect and resolve task-ID collisions in the workspace TOCTOU window between
  /dr-init reservation and /dr-archive completion. Covers grep across all
  archive subdirs, sed-batch rename across artifact files, git mv coordination,
  and chmod restore for verify audit logs that were already locked.
applicability: framework
loaded_by:
  - commands/dr-init.md (probe step)
  - commands/dr-archive.md (collision-detection branch)
<!-- gate:history-allowed -->
source: TUNE-0280 reflection § Class A P1
<!-- /gate:history-allowed -->
---

# Task-ID Collision Window — Detection & Rename Procedure

## When this skill is needed

Two parallel agent sessions on the same shared workspace can reserve the same
`TASK-PREFIX-NNNN` value during the TOCTOU window between `/dr-init` Step 2.5
(probe) and `/dr-archive` (commit). The collision is invisible until one of the
sessions writes an artifact whose path or content already exists. By that point
the loser usually has a non-trivial chain of derived artifacts (PRD, plan,
verify audit logs, reflection, snapshot) all stamped with the colliding ID and
some of them already chmod a-w by post-stage hardening.

This skill is invoked by:

- `/dr-init` Phase 1 probe — extended scope per source proposal, to catch the
  collision before any artifact is written;
- `/dr-archive` Step 0.x detection branch — when archive doc already exists at
  the target path under a different task title (parallel session got there
  first);
- **Hot-fix branch naming (no `/dr-init`).** When an operator-initiated hot-fix
  bypasses `/dr-init` and the agent picks a candidate `TASK-PREFIX-NNNN` for
  the branch + commit message + PR title, the candidate MUST be probed against
  the full canonical set in § Detection BEFORE running
  `git checkout -b <candidate>-...`. If any artifact or backlog entry exists
  for the candidate ID, the candidate is reserved — pick the next free ID
  (highest existing ID in workspace + 1, skipping reserved sentinel values) and proceed.
  Catches the false-free case where the ID looks unused in the agent's
  conversation context but is actually already filed in `backlog.md` as a
  follow-up from a sibling task.

## Detection — probe scope

Run from the workspace root (the dir containing `datarim/` and
`documentation/`):

```sh
# 1. probe active state
grep -E "^- ${TASK_ID} " datarim/tasks.md datarim/backlog.md
grep "^${TASK_ID}\b" datarim/activeContext.md

# 2. probe per-task artifact files (full canonical set)
ls datarim/tasks/${TASK_ID}-*.md \
   datarim/prd/PRD-${TASK_ID}.md \
   datarim/plans/${TASK_ID}-plan.md \
   datarim/qa/*${TASK_ID}*.md \
   datarim/reports/*${TASK_ID}*.md \
   datarim/reflection/reflection-${TASK_ID}.md \
   datarim/snapshots/${TASK_ID}.snapshot.md \
   2>/dev/null

# 3. probe archive across ALL subdirs (collision-on-archive case)
ls documentation/archive/*/archive-${TASK_ID}.md \
   documentation/archive/*/snapshots/${TASK_ID}-final-stage.md \
   2>/dev/null
```

Any hit in step 2 or 3 outside the calling session's own scope = collision.
Distinguish «my own forgotten earlier session» from «parallel session» via
frontmatter `operator:` / `captured_at:` / commit author, not by file presence
alone.

### External-ID-authority probe (tracker-owned prefixes)

The workspace probe above is **structurally blind** to numbers assigned by an
external tracker. When the task prefix is owned by an external ID authority —
e.g. an issue tracker's custom field auto-numbers tasks on creation (check the
project's memory/registry for a statement like «the board owns the id») — a
locally-free number can still collide with a tracker-assigned one, and the
collision surfaces only later in commit messages, MRs, and cross-links.

Rule for tracker-owned prefixes:

1. **Do not invent the number locally.** Create the tracker task first (or
   locate the existing one) and adopt the id the tracker assigns.
2. If a candidate id must be probed anyway (offline work, tracker unreachable),
   query the tracker for that id BEFORE reserving it — a read-only search over
   the id custom field / title. Tracker unreachable ⇒ treat the candidate as
   UNCONFIRMED and re-verify before the first push/publish that embeds the id.
3. On a discovered collision, the local session is ALWAYS the losing session
   (the tracker is the authority) — apply § Resolution below, and also sweep
   non-workspace surfaces the id leaked into: source-file comments, README
   sections, commit messages not yet pushed.

Provenance: a workspace-only probe passed on a locally-free `DEV-NNNN` while
the tracker had already assigned that number to another person's task; the
rename had to touch the whole derived artifact chain plus both copies of a
shipped script.

## Resolution — retroactive rename

The losing session (lower commit-time or operator-assigned) renames its task
ID. Procedure:

1. **Choose new ID.** Pick the next free `TASK-PREFIX-NNNN` per
   `skills/datarim-system/SKILL.md` § Unified Task Numbering — confirm via the same
   probe in detection step 1–3 with the new ID.

2. **sed-batch rename across artifact bodies.** All artifact files reference
   the old ID in frontmatter (`task_id:`), headings, cross-links, and audit log
   entries. Drive every reference through a single batched sed:

   ```sh
   OLD=TUNE-XXXX_old
   NEW=TUNE-YYYY_new
   FILES=(
     datarim/tasks/${OLD}-init-task.md
     datarim/tasks/${OLD}-task-description.md
     datarim/prd/PRD-${OLD}.md
     datarim/plans/${OLD}-plan.md
     datarim/qa/verify-${OLD}-do-1.md
     datarim/qa/verify-${OLD}-do-2.md
     datarim/qa/verify-${OLD}-do-3.md
     datarim/qa/operator-probe-${OLD}.md
     datarim/reports/qa-report-${OLD}.md
     datarim/reflection/reflection-${OLD}.md
   )
   for f in "${FILES[@]}"; do
     [ -f "$f" ] || continue
     [ -w "$f" ] || chmod u+w "$f"
     sed -i.bak "s/${OLD}/${NEW}/g" "$f"
   done
   ```

   Inspect every `.bak` diff before discarding to catch false-positive
   replacements (e.g. an audit log quoting the old ID as historical evidence —
   keep that as-is). The `chmod u+w` line is required when the file was
   already locked post-stage; restore the original mode after rename
   (Step 5).

3. **git mv per filename.** Rename the files themselves:

   ```sh
   for f in "${FILES[@]}"; do
     [ -f "$f" ] || continue
     new_path="${f//${OLD}/${NEW}}"
     git mv "$f" "$new_path"
   done
   ```

4. **Update thin-index files.** Replace the one-liner in `datarim/tasks.md`
   and `datarim/activeContext.md`; replace the entry in `datarim/backlog.md`
   if present. Use exact-prefix anchor `^- ${OLD} ·`.

5. **Restore chmod a-w on hardened audit logs.** Verify-audit logs are written
   chmod a-w by `/dr-verify`; the rename pass had to temporarily lift the
   write bit. Restore:

   ```sh
   for f in datarim/qa/verify-${NEW}-do-*.md \
            datarim/qa/operator-probe-${NEW}.md; do
     [ -f "$f" ] && chmod a-w "$f"
   done
   ```

6. **Drop the `.bak` siblings.** `rm datarim/{tasks,prd,plans,qa,reports,reflection}/*.bak`
   after Step 2 diffs were inspected.

7. **Record the rename.** Append one line to the new ID's
   `tasks/${NEW}-init-task.md § Append-log`:

   ```
   - <ISO-ts> · collision-rename · old_id=${OLD} → new_id=${NEW}; reason: parallel session reserved same ID; ref: see /dr-init Step 2.5 probe
   ```

## Verification — collision closed

- `grep -rn "${OLD}" datarim/ documentation/` returns only historical-evidence
  hits (audit log quotations and the Append-log line from Step 7);
- both probes from § Detection return empty for `${NEW}` outside the calling
  session's artifact set;
- bats regression for whatever pipeline the rename touched still passes (this
  rename is a pure ID relabel — no behavioural change).

## Anti-patterns

- **Do not** rename mid-`/dr-do`. The rename window opens at `/dr-init`
  detection and closes at the next stage commit. Mid-execution rename leaves
  stale references in temporary state (snapshot frontmatter, work-in-progress
  qa drafts).
- **Do not** rename only the file paths via `git mv` without sed-batch
  updating the bodies. Frontmatter `task_id:` keys would mismatch the filename
  and break thin-index validators.
- **Do not** silently delete the losing session's artifacts. The collision is a
  bookkeeping issue, not a content issue — content is salvageable under the
  new ID.

## Provenance

<!-- gate:history-allowed -->
TUNE-0280 (`/dr-continue` + stage-snapshot replay verification) hit this exact
<!-- /gate:history-allowed -->
<!-- gate:history-allowed -->
collision on its `/dr-archive` step — parallel session had reserved TUNE-0269
<!-- /gate:history-allowed -->
and committed first. Resolution required renaming the whole derived chain
mid-archive, which is what this skill codifies as a standard procedure.
