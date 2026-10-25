---
name: dr-finalize
description: Complete an archived task's delivery, safe cleanup, tracker, and final report
---

**Language preferences:** Resolve the consuming project's reply and artifact languages using `${DATARIM_RUNTIME:?}/skills/datarim-system/language-preferences.md` before reporting.

# /dr-finalize — Complete a task

Before any mutation, apply the `EXECUTION HOST` section of `${DATARIM_RUNTIME:?}/commands/dr-archive.md` and the stage header rule. An off-host binding dispatches under that contract; a failed host probe stops mutation.

Resolve the project and exact task ID using the normal Datarim path and task rules. Read the init-task, current snapshot, archive, project `AGENTS.md`, and the task-owned ledger at `datarim/finalize/{TASK-ID}.json`. Create the ledger when the task begins and append entries as the task creates worktrees, branches, temporary paths, processes, and containers. Its schema is `{"schema":1,"owned":{"paths":[],"worktrees":[],"branches":[],"processes":[],"containers":[]}}`. Never infer ownership from a prefix or glob. Record each step in `datarim/finalize/{TASK-ID}.status.md` as `done`, `skipped: <reason>`, `failed: <reason>`, or `not measured`; retain past results and verify them on rerun. A failed step blocks its dependents, while independent steps continue.

1. **Archive.** Run `/dr-archive` or verify a current archive for this task and revision. Record its path and evidence. A stale archive is rerun, never silently reused.
2. **Documentation.** Publish or push task-owned documentation through the project's normal documented route; record destination and revision. If there is no publication route, say `skipped: <reason>`.
3. **Commit and push.** Inventory each repository this task touched. Commit and push only task-owned files, following that repository's signing, secret scan, pull/rebase, PR/MR and review rules. Report foreign dirty files without staging them. Record branch, commit and remote URL; do not claim merge from push.
4. **Return checkouts.** Read each repository's observed default branch. Switch only from clean trees after verifying no local changes can be lost. A dirty checkout is `skipped` with exact paths.
5. **Worktrees.** Remove only exact task-created worktrees recorded in the ledger and clean after step 3. Check no process uses them. Preserve any worktree absent from the ledger.
6. **Branches.** Fetch the default and task branch refs, then run `python3 "${DATARIM_RUNTIME:?}/dev-tools/finalize-safety.py" branch --ledger datarim/finalize/{TASK-ID}.json --repo REPO --target BRANCH` before each local or remote deletion. It checks exact ownership, clean state, observed default branch, ancestry or exact tree equality for a squash merge. Delete only on `allowed`; never force-delete. If later default-branch commits prevent proving the squash by exact tree, keep the branch and report the proof gap.
7. **Temporary artifacts.** For each exact path run `finalize-safety.py path --ledger ... --workspace ROOT --target ABSOLUTE_PATH` before removal. Also verify process/container identity and creation details against the ledger and live state before stopping anything. Preserve tracked, foreign, unknown, or symlinked items. Jev and host safety rules still apply.
8. **Tracker.** Read the project's configured integration and final-status mapping. Probe with `finalize-safety.py tracker --config datarim/config/tracker.json`. If absent or unreachable, record `not applied: <reason>`. If configured, use that integration once to set final status and required fields and post one completion comment with work, method, archive, documentation, PR/merge/release URLs. On rerun, find the existing task/comment first and update only missing fields; do not duplicate.
9. **Final report.** Give one human outcome report with all nine step statuses, links, remaining work and reasons. `done` means observed completion; missing evidence is `not measured`. Include release and deployment only when separately verified.

The command coordinates these operations; `/dr-archive` remains the knowledge-record command. Do not delete unmerged branches, uncommitted work, untracked foreign paths, or an entire directory merely because its name resembles this task. A ledger entry is necessary but does not override the clean, merge, or host safety checks.
