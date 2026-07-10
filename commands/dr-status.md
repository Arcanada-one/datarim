---
name: dr-status
description: Check current Datarim task status, progress, and Backlog summary
---

# /dr-status - Check Status

Show current task and Backlog status.

Two modes: the default **push-mode** dashboard (all active tasks + backlog + recent archives, Sections 1-4 below) and the **pull-mode oracle** — a TASK-ID plus a free-form question (`what's next?`) answered with a stage-derived next-step recommendation (see § Pull-mode Oracle).

## Path Resolution
**RESOLVE PATH**: Before any read from `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, tell user to run `/dr-init`. See `$HOME/.claude/skills/datarim-system/SKILL.md` § Path Resolution Rule.

## Display (thin-index schema)
1. **All active tasks** — parse one-liner format from `## Active Tasks` in `activeContext.md` (or `## Active` in `tasks.md`):
   - Regex: `^- ([A-Z]{2,10}-[0-9]{4}) · (status) · (P[0-3]) · (L[1-4]) · (.+) → tasks/\1-task-description\.md$`
   - Render numbered list: `{N}. {ID} · {status} · {P}/{L} · {title}`. Max 80-char title (already capped by schema).
   - If no active tasks → say so explicitly.
2. **Backlog summary** — count one-liners by status in `backlog.md`:
   - `pending`: N items
   - `blocked-pending`: N items
   - `cancelled`: N items
3. **Recently completed (`--recent N`, default N=5)** — runtime
   computation, NOT a stored section. List `documentation/archive/**/archive-*.md`
   sorted by mtime descending, take first N. For each: derive `{ID}` from
   filename (strip `archive-` prefix and `.md` suffix); read first matching
   `^# Archive — {ID}` heading or first `^# ` line for `{title}`; date = mtime
   formatted `YYYY-MM-DD`. Render `{date · ID · title}`. The legacy
   `activeContext.md § Recently completed` (legacy Russian section name «Последние завершённые») was retired in v1.19.1 — single <!-- allow-non-ascii: russian-legacy-section-name-cited-from-prior-schema -->
   source of truth = `documentation/archive/`.

   POSIX recipe (illustrative):
   ```sh
   ls -t documentation/archive/**/archive-*.md 2>/dev/null | head -"${N:-5}"
   ```
4. **Next steps suggestion** — pick highest-priority active task, suggest its current pipeline phase.

For full task content, agent reads `datarim/tasks/{TASK-ID}-task-description.md` on demand. Operational files stay thin.

## Flags

- `--recent N` (default N=5) — number of recently-completed entries to display
  in Section 3. Operator override; values 1..50 acceptable.


## Pull-mode Oracle — "what's next?" on a TASK-ID

Beyond the default push-mode dashboard (Sections 1-4 above), `/dr-status`
supports a **pull-mode oracle**: the operator passes a **TASK-ID plus a
free-form question** and the command answers *what to do next on that specific
task*, deriving the recommendation from the task's current stage/snapshot
rather than re-printing the whole board.

### Trigger

Pull-mode activates when the invocation carries **both**:

1. A `{TASK-ID}` token matching `^[A-Z]{2,10}-[0-9]{4,5}$`, and
2. A free-form natural-language question (e.g. `what's next?`, `where am I?`,
   `what should I run now?`, `is this ready to archive?`).

Examples that activate pull-mode:

```
/dr-status <TASK-ID> what's next?
/dr-status "what should I do next on <TASK-ID>?"
/dr-status <TASK-ID> is this ready to archive?
```

If a TASK-ID is present but no free-form question follows, fall back to the
default push-mode dashboard scoped to that task (Sections 1-4, filtered to the
one task). If neither a TASK-ID nor a question is present, run the standard
board. This is a routing extension, not a replacement — push-mode remains the
default.

### Resolution (snapshot-first, stage-fallback)

The oracle resolves the task's current stage using the **same snapshot contract
consumed by `/dr-next`** ([consumer contract](../skills/dr-next-snapshot-replay/SKILL.md)),
so the answer stays consistent with what a resume would replay:

```
1. Resolve {TASK-ID} per the Path Resolution Rule and the Task Resolution Rule.
2. snapshot_path = "$REPO_ROOT/datarim/snapshots/{TASK-ID}.snapshot.md"
3. if `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-stage-snapshot-on-exit.sh" \
        --validate-frontmatter --task {TASK-ID}` exits 0:
       read the snapshot frontmatter (stage, command, recommended_next, options)
       → PRIMARY SOURCE. The oracle's recommendation is the snapshot's
         `recommended_next`, expanded with one purpose line via the CTA heuristic.
   else (snapshot absent OR validator exit != 0):
       silent fallback (no warning noise, per the replay skill § Contract):
       derive the stage from the task's one-liner status/phase in tasks.md /
       activeContext.md, then map stage → next command via the Stage→Command
       table below.
4. This command is READ-ONLY: it never writes or refreshes the snapshot.
```

Because the oracle reuses `check-stage-snapshot-on-exit.sh` and the
`recommended_next` field, its answer matches the replay prompt `/dr-next` would
emit for the same task — no divergent second opinion.

### Stage → next-command mapping (snapshot-absent fallback)

When no valid snapshot exists, map the derived stage to the recommended next
`/dr-*` command. This mirrors the CTA authoring rules in
[cta-format](../skills/cta-format/SKILL.md) § Authoring Rules:

| Derived stage / status | Recommended next | Rationale |
|------------------------|------------------|-----------|
| just initialised (no PRD) | `/dr-prd {TASK-ID}` (L3+) or `/dr-plan {TASK-ID}` (L1/L2) | define scope before planning |
| PRD done, no plan | `/dr-plan {TASK-ID}` | turn requirements into phased plan |
| plan done, L3+ few verify passes | `/dr-verify {TASK-ID}` | cheap cross-check before implementation |
| plan done, verification saturated | `/dr-do {TASK-ID}` | enough evidence to implement |
| implementation done | `/dr-qa {TASK-ID}` then `/dr-compliance {TASK-ID}` | verify before hardening |
| QA + compliance green | `/dr-archive {TASK-ID}` | capture outcome, free activeContext |
| blocked / unknown | `/dr-next {TASK-ID}` | full context-aware resume |

The mapping is guidance, not a hard constraint — the operator may pick any
option. For L3+ tasks with few verification passes, prefer verification
(`/dr-verify`, `/dr-qa`, `/dr-design`) over `/dr-do`; when verification is
saturated, move to implementation or archiving. This is the same
marginal-quality-improvement heuristic documented in the replay skill's
§ CTA Selection heuristic.

### Answer shape

The oracle answers in three parts, then closes with the standard CTA block:

1. **Where the task stands** — one line naming the derived stage and its source
   (`snapshot` vs `stage-fallback`), e.g. `{TASK-ID} is at stage \`plan\`
   (source: snapshot).`
2. **Recommended next step** — the resolved command plus a one-line purpose,
   e.g. `Run \`/dr-do {TASK-ID}\` — the plan and tri-layer verify are green.`
3. **Why** — one sentence of rationale tied to the stage (the marginal-quality
   heuristic), so the operator can override with intent.

The closing CTA block ([definition](../skills/cta-format/SKILL.md)) makes the
recommended command the primary option (the primary-recommendation marker per
`cta-format.md`), lists the other plausible stage options as variants, and
always keeps `/dr-help` as the escape hatch.
Since `/dr-status` is read-only, the CTA is purely navigational — the operator
chooses whether to run the recommendation.

## Read
- `datarim/activeContext.md` (Active Tasks — strict mirror of tasks.md)
- `datarim/tasks.md` (one-liners only — no body to parse)
- `datarim/backlog.md` (one-liners; group by status)
- `documentation/archive/**/archive-*.md` (mtime-sorted, lazy via `ls -t`)
- `datarim/tasks/{TASK-ID}-task-description.md` — only when operator asks for task detail (lazy-load)
- `datarim/snapshots/{TASK-ID}.snapshot.md` — pull-mode oracle only; validated via `dev-tools/check-stage-snapshot-on-exit.sh`, read-only (never written)

## Write
None (read-only)

## Next Steps (CTA)

After printing status, MUST emit a CTA block ([definition](../skills/cta-format/SKILL.md)) per `$HOME/.claude/skills/cta-format/SKILL.md`. Since `/dr-status` is read-only, the CTA is purely navigational.

**Routing logic for `/dr-status`:**

- One active task → primary command for that task's current pipeline phase (resolved from `progress.md`/`tasks.md`)
- Multiple active tasks → CTA picks the highest-priority task as primary; surfaces all others in Variant B menu (`**Другие активные задачи:**`) <!-- allow-non-ascii: russian-canonical-cta-variant-b-menu-header-cited-from-cta-format-skill -->
- No active tasks, backlog has items → primary `/dr-init` (pick from backlog)
- No active tasks, empty backlog → primary `/dr-init "<description>"` (start new task)
- Pull-mode oracle (TASK-ID + free-form question) → primary is the resolved next-command for that task (see § Pull-mode Oracle); other stage options as variants
- Always include `/dr-help` as escape hatch (command reference)

The CTA block MUST follow the canonical format (numbered, one `**рекомендуется**`, `---` HR). Variant B is mandatory for `/dr-status` whenever ≥2 active tasks exist — `/dr-status` is the discovery surface for parallel work. <!-- allow-non-ascii: russian-canonical-cta-marker-tokens-cited-from-cta-format-skill -->
