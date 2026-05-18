---
name: dr-archive
description: Archive completed task with comprehensive documentation and Datarim updates
---

# /dr-archive — Archive Task

> **Contract.** Archival performs irreversible workspace mutations — schema-gate validation of the thin-index files, staged-diff audit of foreign task-ID hunks, blob-swap recipe for non-interactive shells, prefix → archive-subdir routing, and the mandatory Operator Handoff section in the archive document. All of these protections are enforced in code (`pre-archive-check.sh`, `datarim-doctor.sh`, and the steps below), independent of how the command is invoked. Prefer the canonical slash form (`/dr-archive {TASK-ID}`) over manually staging archive files: the slash command threads through every guard described in this file; ad-hoc paths skip them.

Complete and archive current task.

## Path Resolution
**RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.

## Steps

0. **TASK RESOLUTION**: Apply Task Resolution Rule from `$HOME/.claude/skills/datarim-system.md` § Task Resolution Rule. Resolve which task is being archived (from argument or disambiguation). Use the resolved task ID for all subsequent steps.

0.05. **READ INIT-TASK** (mandatory per `$HOME/.claude/skills/init-task-persistence.md`): Open `datarim/tasks/{TASK-ID}-init-task.md` if present. Read the full `## Operator brief (verbatim)` section AND every `## Append-log` entry. The archive document MUST include a `## Выполнение ожиданий оператора` section (F6 of init-task contract) that reflects how each operator-stated expectation was met. Missing init-task is non-blocking on archive — note its absence under § Legacy and continue.

0.1. **PRE-ARCHIVE CLEAN-GIT CHECK** (MANDATORY):

   **Contract:** this gate runs `git status --porcelain` per every git repository touched by the task. On a dirty tree the operator picks one of three branches: **Commit now** (land the changes), **Accept pending state** (record in the archive doc's "Known Outstanding State" section), or **Abort** (return to /dr-do). Do not archive over a dirty working tree silently — STOP if no branch is chosen.

   **0.1.1 Repo classification.** Every git repository touched by this task is one of:
   - **Workspace repo** (shared, e.g. a workflow-state directory shared by multiple parallel agent sessions): foreign-task-ID hunks are NOT a blocker; only this task's own forgotten hunks (or unattributed hunks) block.
   - **Conditional-shared repo:** a repo containing a `.datarim-shared` marker file at its root. Treated as workspace-shared automatically when `pre-archive-check.sh` is invoked with `--task-id` (no explicit `--shared` flag needed). Used by framework repos that are touched by multiple parallel agent sessions but were historically classified as project repos.
   - **Project repo** (single-agent, e.g. a project's source tree): foreign-task-ID hunks are impossible by construction; treat any uncommitted change as a STOP.

   | Repo type | Marker / flag | Classification |
   |-----------|---------------|----------------|
   | Workspace | invoked with `--shared <path>` | shared |
   | Conditional-shared | `.datarim-shared` marker at repo root + `--task-id` | shared (auto-detect) |
   | Project | neither | single-agent (legacy) |

   Default the framework's own state directory and any cross-task workflow store to *workspace*. Default product source trees to *project*. Mark a repo as *conditional-shared* by committing `.datarim-shared` to its root with an explanatory comment. When in doubt, ask the user.

   **0.1.2 Workspace repo check** (per repo classified as shared OR conditional-shared):
   Run either invocation form:
   - Explicit shared: `scripts/pre-archive-check.sh --task-id <CURRENT-TASK-ID> --shared <repo-path>`.
   - Conditional-shared (auto-detect): `scripts/pre-archive-check.sh --task-id <CURRENT-TASK-ID> <repo-path>` — the script auto-routes to shared mode when `<repo-path>/.datarim-shared` exists. The script classifies each modified file's hunks by task ID:
   - `own` — only the current task's ID appears → MUST be committed before archive.
   - `foreign` — only other task IDs (parallel sessions) → leave untouched, NOT a blocker.
   - `mixed` — current + other IDs in the same diff → stage selectively (own only).
   - `unattributed` — no task ID present → require explicit user disposition (default-deny).
   - `whitelisted` — basename is a known version-bump file (`VERSION`, `CHANGELOG.md`, `package.json`, `Cargo.toml`, `pyproject.toml`, `.gitignore`) AND `--task-id` is set → bypass default-deny (operator-supplied disposition is the attribution). Pass `--no-whitelist` to restore strict behaviour. **Project-specific extension:** set `DATARIM_PRE_ARCHIVE_WHITELIST=<basename>[:<basename>...]` (colon-separated, PATH-style) to extend the whitelist with project-specific version-bump basenames (e.g., `config.php` for a public-surface site) without modifying the framework. Path components are rejected (basename match only). `--no-whitelist` overrides both the hardcoded list and the env-var.
   - `mine-by-elimination` — file body carries foreign historical task IDs but the actual diff lines (additions/removals) added by this session contain ZERO task IDs AND `--task-id` is set → attribute to the current task (operator-supplied disposition; nothing else to attribute it to). Closes the false-`foreign` misclassification of doc edits like CLAUDE.md/README.md/architectural docs where the committed body references many historical tasks but the current edit (e.g., a version bump) introduces none. Untracked files (no diff at all) skip this branch and fall through to `foreign` per safety guard.

   Exit 0 means archive may proceed. Exit 1 means apply recipe 0.1.3 below; STOP if the user declines.

   **0.1.3 Apply recipe — patch staging.** Two equivalent paths:

   <!-- gate:example-only -->
   *Preferred (interactive shell with TTY):*
   ```
   git -C <repo> add -p <workflow-file>
   ```
   Accept only hunks containing the current task ID. Reject foreign hunks.

   *Fallback (non-interactive shell, e.g. AI agent without TTY):* blob-swap recipe.
   ```
   git -C <repo> show HEAD:<file> > /tmp/<file>-mine
   $EDITOR /tmp/<file>-mine                       # apply only your hunk on top of HEAD
   BLOB=$(git -C <repo> hash-object -w /tmp/<file>-mine)
   git -C <repo> update-index --cacheinfo 100644,$BLOB,<file>
   git -C <repo> diff --staged <file>             # verify only your edit staged
   ```

   *Also use blob-swap when:* the in-tree edit tool (mtime-checking `Edit`)
   refuses the change because a parallel session wrote to the same shared
   workflow file between your `Read` and `Edit`. Re-Read+retry is itself
   race-prone in shared workspaces; blob-swap operates on the HEAD blob (not
   the working tree) so the mtime check is bypassed entirely. Apply only when
   the desired change is mechanical (e.g. removing your own task-ID one-liner
   from an index file) so the target blob can be constructed deterministically
   from HEAD.

   *Pre-commit retry-tolerant re-verify* (mandatory before `git commit` in either path):
   ```
   git -C <repo> diff --staged --numstat          # verify file-set + line counts
   git -C <repo> log -1 --format=%H               # capture HEAD SHA
   ```
   If file-set / line counts differ from expected delta, or HEAD SHA shifted (parallel session committed in between), rebuild the blob from the new HEAD and re-stage. Do not commit partial state.
   <!-- /gate:example-only -->

   **0.1.4 Cross-task leakage staged-diff audit:**
   After `git add` and before `git commit`, run `git diff --staged --stat` and verify the file-list matches the commit-message scope. Reject the commit if files unrelated to the message scope appear in the staged set; restage selectively. Past incidents have shown unrelated files leak into a commit when the staged diff is not inspected before commit.

   **0.1.5 Project repo check** (per repo classified as single-agent — i.e., no `.datarim-shared` marker):
   Run `scripts/pre-archive-check.sh <project-repo-path>` (legacy mode). Exit 1 → STOP and present the 3-way prompt (Commit now / Accept pending / Abort). Applied ≠ committed ≠ canonical.

0.2. **VERSION CONSISTENCY CHECK** (framework repo only, MANDATORY when `VERSION` changed):

   When the framework repo's `VERSION` file changed in HEAD->working-tree, all consumer files (CLAUDE.md, README.md, docs/) must reference the new version. Catches the recurring class «VERSION bumped but README/CLAUDE.md left stale».

   Run: `bash scripts/version-consistency-check.sh <framework-repo-path>`

   Exit codes:
   - **0** — `VERSION` unchanged, OR all consumers aligned. Proceed.
   - **1** — `VERSION` bumped + at least one consumer cites old version. STOP and either update the lagging files or re-run with `--allow-version-lag` if the lag is intentional (rare; most cases are unintentional drift).
   - **2** — usage error (path not a git repo). Investigate.

   Scope: only `CLAUDE.md` and `README.md` (current-state surfaces). `docs/` is excluded by design — `evolution-log.md` / `release-notes.md` / `changelog.md` are append-only historical ledgers that reference past versions on purpose. This step is skipped automatically when `VERSION` is unchanged — most archives don't bump, so the check is a fast no-op outside framework releases.

0.3. **NETWORK EXPOSURE VALIDATION GATE** (MANDATORY when the task touched any networking surface):

   Touched surfaces include: docker-compose `ports`/`expose`, `redis.conf`,
   `postgresql.conf`, systemd `.socket`, firewall/UFW rules, runtime bind
   arguments. If none of these were touched in the task's commits across all
   repos, skip this step.

   **0.3.1 Verifier replay.** Run the verifier against the final state of every
   touched config:
   ```bash
   dev-tools/network-exposure-check.sh \
       --compose <final-compose>... \
       --redis-conf <final-redis>... \
       --postgres-conf <final-postgres>... \
       --systemd-socket <final-socket>...
   ```
   Exit code `1` ⇒ STOP archive. Drive the verifier to exit 0 (fix bind, add
   justified Tier 3 with `x-exposure-justification` + `x-exposure-expires`
   ≤ 90 d, or open a follow-up task and return to `/dr-do`). Quote the verifier
   command and exit code in the archive doc § Verification.

   **0.3.2 Tiered-gate verdict in archive doc.** Capture the gate decision so
   reviewers can replay it later:
   ```bash
   decision=$(dev-tools/network-exposure-gate.sh \
       --task-description datarim/tasks/{TASK-ID}-task-description.md \
       --network-diff --quiet)
   ```
   Record `decision` (one of `hard_block` / `advisory_warn` / `skip`) in the
   archive doc.

   **0.3.3 External proof for Tier 3 binds.** For every Tier 3 listener that
   ends up in production, the archive doc MUST include ONE of:
   -   external port-scan output (e.g. `nmap` run from outside the host)
       confirming the listener is reachable as designed and that no
       unintended ports are exposed on the same host;
   -   a reference to a separate INFRA-* / SEC-* audit task that owns the
       external verification and is itself archived;
   -   an explicit waiver paragraph stating who accepted the residual risk,
       its expiry date (≤ 90 days), and the follow-up task ID that will
       perform the post-hoc audit.

   **0.3.4 Failed gate ⇒ explicit operator handoff.** If the gate verdict was
   `hard_block` and the verifier still returns 1 at archive time (e.g. the
   operator chose «Accept pending state» at Step 0.1), the archive doc § Known
   Outstanding State / Operator Handoff MUST list each unjustified bind, the
   blast-radius, and the remediation owner + ETA. «DoD met» framing is
   forbidden when the network gate is red.

0.5. **REFLECT** (MANDATORY, non-skippable):
   - Load `$HOME/.claude/skills/reflecting.md`.
   - Execute the reflect workflow per that skill:
     a. Create `datarim/reflection/reflection-[task_id].md`.
     b. Generate evolution proposals (categories: skill-update, agent-update, claude-md-update, new-template, new-skill).
     c. Classify Class A / Class B per `skills/evolution.md`.
     d. Present Class A for approval; hold Class B (require PRD update before apply).
     e. Apply approved Class A to runtime (stack-agnostic gate MUST PASS per `$HOME/.claude/skills/evolution/stack-agnostic-gate.md`; gate FAIL → reject the proposal and ask user to either reword stack-neutral or relocate to project's `CLAUDE.md`); log applied changes in `datarim/docs/evolution-log.md`. **Recommended invocation for shared-history files** (`docs/evolution-log.md`, README, changelog and any file that already carries pre-existing baseline matches): `scripts/stack-agnostic-gate.sh --diff-only <path>` — scans only lines added by the current task (`git diff HEAD -- <path>`), ignoring legacy baseline content. Default full-file mode remains correct for newly-touched skills/agents/commands/templates. **Doc-reference advisory (non-blocking)**: when the task touched any markdown under `code/datarim/{CLAUDE.md,skills,agents,commands,templates,docs}/`, run `scripts/check-doc-refs.sh --root code/datarim/` to detect broken markdown links and bare-path mentions against the `.docrefignore` baseline (orphans → exit 1; clean → exit 0). Advisory-only at this step.
     f. Run health-metrics check; suggest `/dr-optimize` if thresholds exceeded (no auto-run).
     g. Note follow-up tasks for Step 4 consumption.
   - Step CANNOT be skipped. No `--no-reflect` flag exists.
   - On failure (skill load error / user rejects Class A): STOP archive; do NOT proceed to Step 1. Archive is idempotent — re-running re-enters Step 0.5.
   - Historical: prior to Datarim v1.10.0, this ran as a separate `/dr-reflect` command; consolidated here because an "optional mandatory gate" is the defect.

1. **DETERMINE ARCHIVE AREA**:
   - Extract prefix from task ID (everything before the first `-`)
   - Map prefix to area subdirectory using `$HOME/.claude/skills/datarim-system.md` § Archive Area Mapping
   - If prefix not in mapping → use `general/`
   - Create `documentation/archive/{area}/` directory if it doesn't exist
2. Create archive document with:
   - **Frontmatter from canonical template** `templates/archive-template.md` — copy YAML schema (`id`, `title`, `status`, `completed_date`, `complexity`, `type`, `project`, `related`, `archive_doc`, `verification_outcome`). Schema is closed; do not add custom keys.
   - **`verification_outcome` block — MANDATORY at archive time.** Triage the audit log under `datarim/qa/verify-{TASK-ID}-*.md` (if `/dr-verify` ran) and fill the four counters + `dogfood_window` per template comment block:
     - `caught_by_verify` — high/medium gaps that `/dr-verify` surfaced and the operator fixed BEFORE this archive.
     - `missed_by_verify` — initially `0`; updated retroactively if a post-archive follow-up reveals a gap that should have been caught.
     - `false_positive` — `/dr-verify` findings the operator triaged as not real.
     - `n_a: true` — when `/dr-verify` was not invoked (L1 trivial fix or pre-tri-layer task).
     - `dogfood_window` — operator-supplied window-id grouping key consumed by `dev-tools/measure-prospective-rate.sh`.
   - Task summary
   - Implementation details
   - Reflection insights
   - **`## Выполнение ожиданий оператора` section (MANDATORY when `datarim/tasks/{TASK-ID}-expectations.md` exists, per F6 of the init-task contract):**
     - Read `datarim/tasks/{TASK-ID}-expectations.md` and render every item from `## Ожидания` in its original order.
     - Each rendered bullet: bold operator-words formulation, followed by the final `/dr-qa` status word (one of «выполнено», «частично», «не выполнено», «неприменимо» — never the schema enum `met`/`partial`/`missed`/`n-a`) and one or two plain-language sentences of comment sourced from the item's most recent `#### История статусов` line (`reason: …`).
     - **No tables in this section.** Bullet list only (single-level allowed; nested bullets forbidden).
     - **No anglicisms** — apply the banlist rules from `skills/human-summary.md` to the comment text (Russian prose only; ASCII tokens of length ≥3 from `skills/human-summary/banlist.txt` MUST NOT appear unless wrapped in the per-paragraph escape-hatch fence). The two-paragraph fenced budget from `human-summary.md` § Per-paragraph escape hatch applies here as well.
     - Placement: between `## Final Acceptance Criteria` and `## Known Outstanding State / Operator Handoff` (see `templates/archive-template.md`).
     - Missing expectations file ⇒ render a single line «Чек-лист ожиданий не заводился» under the heading and proceed; do not skip the heading entirely (the section is part of the archive's canonical shape).
   - **Known Loss Verification Gate (MANDATORY when archive will include any "Known Loss" / "Unrecoverable" / "Content lost" statement):**
     Before recording that any file, section, decision, or piece of work is permanently lost, run the Disaster Recovery Checklist from `$HOME/.claude/skills/evolution.md` § Disaster Recovery for Lost Runtime Files. Record in the archive document which channels were checked (grep reflections by filename, compacted session context, cross-references, git history of consumer projects, external backups) and what each returned. If the checklist takes >30 minutes, defer the archive, open a follow-up recovery task, do not record the loss yet. Only after all 5 channels are exhausted may a loss claim enter the archive. Rationale: an archive that records files as "text reconstruction is not possible" after 0 minutes of discovery has historically been recovered 100% in <30 minutes using channels 1-3. Always run the checklist first.
3. **BACKLOG UPDATE** (if task existed in backlog):
   - Use the resolved task ID from Step 0
   - If the same ID exists in `datarim/backlog.md` (as `in_progress` or `pending`):
     a. **Remove** that entry from `datarim/backlog.md`
     b. **Add** entry to `datarim/backlog-archive.md` under `## Completed` with status `completed`, completion date, and link to archive doc — keeping the same ID
     c. Update Archive Statistics count in `backlog-archive.md`
   - If the task ID does not appear in `backlog.md`: skip this step (task was ad hoc, not from backlog)
4. **FOLLOW-UP TASKS** (from reflection):
   - Read `datarim/reflection/reflection-[task_id].md` for "Next Steps" section
   - If follow-up items exist, ask user: "Add these as new backlog items?"
   - If yes: add each as new `{PREFIX}-XXXX` entry in `datarim/backlog.md` with status `pending`. Choose prefix per Unified Task Numbering (`$HOME/.claude/skills/datarim-system.md`) — project or area prefix relevant to the follow-up item
5. **REMOVE FROM tasks.md** (thin-index schema):
   - Delete the one-liner for `{TASK-ID}` from `## Active` in `datarim/tasks.md`. Match by exact `^- {TASK-ID} ·` prefix.
   - Keep all other active task one-liners intact.
   - If a plan file exists at `datarim/plans/{TASK-ID}-plan.md`, delete it. The archive doc is the permanent record.
   - Description file `datarim/tasks/{TASK-ID}-task-description.md` MAY be kept (frontmatter `status: completed`) or deleted at operator discretion — archive supersedes it.
6. **UPDATE activeContext.md** (thin-index schema, v1.19.1):
   - **Remove** the archived task's one-liner from `## Active Tasks` (keep all others).
   - The Active section is **strict mirror** of `tasks.md § Active` — after removal, both files share the same line set.
   - Do NOT write any `## Последние завершённые` / `## Last Completed` /
     `## Last Updated` section: those were retired in v1.19.1.
     Recency is computed runtime by `/dr-status --recent N` from
     `documentation/archive/**/archive-*.md` mtime-sort.
7. **NO `progress.md` / `backlog-archive.md` UPDATE:**
   - `progress.md` is abolished (v1.19.0). `backlog-archive.md` is abolished
     (v1.19.1). Both are blocked by `pre-archive-check.sh`.
   - Cancelled tasks: write `documentation/archive/cancelled/archive-{ID}.md`
     directly; remove from `backlog.md`.
   - Legacy state (any of those files present): `/dr-doctor --fix` migrates and
     deletes; `/dr-init` Step 2.4 self-heal probe surfaces this on next session.
8. **HUMAN SUMMARY**:
   - Load `$HOME/.claude/skills/human-summary.md`.
   - Emit the `## Отчёт оператору` (RU) / `## Operator summary` (EN) section, with the four mandated sub-sections, between the archive-mutation block and the CTA block. Language follows the most recent operator message.
   - Source material: the just-written archive document (§ Overview / § Outcome / § Known Outstanding State / § Выполнение ожиданий оператора) plus the reflection file from Step 0.5.
   - Do NOT mutate the archive document or the reflection file — the summary is chat-only; the archive remains the permanent record.
   - The summary MUST honour the banlist + whitelist + per-paragraph escape-hatch contract from the skill (`<!-- gate:literal -->` … `<!-- /gate:literal -->` for verbatim quoted blocks only; max two fenced paragraphs per summary).
   - Length budget: 150–400 words **total across the four sub-sections** (not per sub-section). Hard upper bound. If sources are bigger, compress.

## Read
- `datarim/tasks.md` (thin index — one-liner for the archived task)
- `datarim/tasks/{TASK-ID}-task-description.md` (full task content, ACs, constraints)
- `datarim/reflection/reflection-[task_id].md` (written by Step 0.5)
- `datarim/creative/*.md` (Level 3-4)
- `datarim/plans/{TASK-ID}-plan.md` (L3-4)
- `datarim/backlog.md` (to find and remove completed/cancelled item)
- `datarim/activeContext.md` (Active Tasks list — strict mirror of tasks.md)
- `$HOME/.claude/skills/datarim-system.md` (Operational File Schema, Archive Area Mapping)
- `$HOME/.claude/skills/reflecting.md` (loaded by Step 0.5)
- `$HOME/.claude/skills/evolution.md` (loaded by Step 0.5 for Class A/B gate)

## Write
- `documentation/archive/[area]/archive-[task_id].md` (NEW — permanent record)
- `datarim/backlog.md` (remove `in_progress`/`pending` entry if present)
- `documentation/archive/cancelled/archive-{ID}.md` (NEW — for cancellation flow)
- `datarim/tasks.md` (remove archived one-liner; preserve other active one-liners)
- `datarim/activeContext.md` (remove from Active Tasks — strict mirror of tasks.md)
- `datarim/plans/{TASK-ID}-plan.md` (DELETE if exists — archive supersedes)
- **Never write `datarim/progress.md`** (abolished as of v1.19.0).

## Cancellation Mode

If user says "cancel task" or "cancel {TASK-ID}":
1. Resolve task ID using Task Resolution Rule (argument or disambiguation).
2. **Remove** the entry from `datarim/backlog.md` (if present)
3. **Add** entry to `datarim/backlog-archive.md` under `## Cancelled` with status `cancelled`, date, and reason — keeping the same ID
4. **Remove** the cancelled task from `## Active Tasks` in `activeContext.md` (keep other active tasks)
5. Clear task from `tasks.md`
6. Do NOT create archive document (task was not completed)

## Next Steps (CTA)

After archive, the planner agent MUST emit a CTA block per `$HOME/.claude/skills/cta-format.md`. After archiving, the just-archived task is removed from `## Active Tasks`; CTA reflects the new state of activeContext.

**Routing logic for `/dr-archive`:**

- Archive completed, other active tasks remain → primary `/dr-continue` (resume the next active task) + alternative `/dr-status`
- Archive completed, no other active tasks → primary `/dr-init` (start new work) + alternative "pick from backlog"
- Knowledge base grew >5 docs since last maintenance → alternative `/dr-dream` (housekeeping)
- Always include `/dr-status` as escape hatch

The CTA block MUST follow the canonical format. If multiple tasks remain active after this archive, render Variant B menu (`**Другие активные задачи:**`).
