---
name: dr-quick
description: Lightweight fast-lane for trivial fixes or quick lookups — assign QCK-XXXX, weak-model KB scan, apply the change, short archive. Skips the heavy init→prd→plan pipeline.
---

# /dr-quick — Fast-Lane for Trivial Fixes & Lookups

**Role**: Developer Agent (lightweight)
**Source**: `$HOME/.claude/agents/developer.md`

Use this command for tiny, self-contained edits or quick information lookups that do not merit the full heavyweight pipeline. It deliberately bypasses PRD, planning, design, QA, and compliance stages to minimize overhead.

## Usage

```text
/dr-quick "<short task title>"
```

Note: title defaults to English unless the operator's configured content language is otherwise.

## What happens, step by step

1. Resolve `datarim/` via standard path resolution (walk up; if absent, STOP and tell user to run `/dr-init` — only `/dr-init` creates `datarim/`).

### EXECUTION HOST

1. Source the resolver: `source "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/lib/execution-host.sh"`.
2. Call `eh_decision <workspace-root> <execution-hosts-map-path>` (default map: `~/.claude/local/config/execution-hosts.yml`).
3. On **off-host** (exit code 10), the routing decision depends on this QCK's intent -- and for the fast-lane that intent is only settled at Step 5 (apply-a-fix vs report-a-lookup), which runs AFTER this block. The dispatch decision is therefore **deferred and re-evaluated once intent is known at Step 5**; the two fixed outcomes are:
   - **READ-ONLY QCK** (a lookup / "where is X" / "does Y exist" -- Step 5 only *reports* the located item: touches no files, switches no branch, writes no archive): proceed LOCALLY in read-only mode -- do NOT dispatch (dispatching an observational command to the very host the laptop is meant to monitor buys nothing). Surface the delegation directive (`dev-tools/datarim-dispatch.sh --workspace <root> --task <TASK-ID>`) as information only, never as a blocking question.
   - **MUTATING QCK** (Step 5 applies the fix / edits files / switches branches / writes the archive): AUTO-DISPATCH to `required_host` -- do NOT run the mutation locally. This mirrors the `commands/dr-do.md` § EXECUTION HOST AUTO-DISPATCH contract; apply that contract's sub-points a–e in full and do not weaken its fail-closed guards:
     a. **RUN vs INSPECT.** Auto-dispatch only when the intent is to RUN the fix (apply/edit/branch/archive). Pure-lookup intent stays local per the READ-ONLY branch above -- do not dispatch a report-only QCK.
     b. **Has-session: attach, don't relaunch.** Before dispatch, probe for an existing session for this task on the required host. Live → attach and monitor, do NOT relaunch. Dead/stale → report and ask before resuming (resuming a partially-done mutating QCK is not unconditionally reversible). Absent → dispatch.
     c. **Target integrity (fail-closed).** The target host key MUST match a pinned `known_hosts` entry and the map MUST be the operator-local gitignored file. Host-key mismatch, missing pin, or any probe failure → STOP and report; NEVER run the QCK locally and NEVER dispatch to an unverified host. Pass `<TASK-ID>`/`<root>` as single non-evaluated argv elements; the dispatch payload is the bare task-id only -- never forward an autonomy/confirm-suppression flag.
     d. **Exit 10 has exactly two outcomes: successful remote dispatch, or STOP-and-report.** Local execution of a mutating QCK is never an outcome of exit 10 (a corrupted/unreadable map under exit 10 is fail-CLOSED, not fail-open).
     e. **Read-only monitor.** After dispatch/attach, act only as a READ-ONLY MONITOR: poll `datarim/runtime/<TASK-ID>.status` and classify the remote pane (`dev-tools/classify-pane.sh`); wait up to ~90s for the first status write, re-send the bare task-id ONCE if none, then FAILED-LAUNCH → durable local log line + escalate + STOP (never silent re-dispatch). Relay any remote hard-gate to the operator as an option index; never answer it yourself and never proceed on silence.
   - **Intent-flip guard (deferred re-evaluation).** A QCK that STARTS as a lookup but, at Step 5, turns into a mutating edit MUST take the MUTATING branch **before** any local mutation -- dispatch first. If the agent has already committed to local execution when the mutating intent emerges, STOP and report (recommend dispatched re-entry) rather than mutate locally on an off-host machine. Never let a mutating edit slip through locally on the "it started as read-only" technicality.
4. On **unconfigured** (exit code 0, binding absent): proceed unchanged (fail-open).
5. On **on-host** (exit code 0, binding present): proceed normally.

Note: the machine-local PreToolUse guard remains the hard floor; this Step-0 check is the cooperative soft layer sharing the same resolver library.
2. **Assign the next free `QCK-XXXX` id — probe-before-emit (MANDATORY):**
   - Run the canonical helper (do NOT compute `max+1` mentally):
     `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/next-free-id.sh" QCK "$DATARIM_ROOT"`
     where `$DATARIM_ROOT` is the workspace root (parent of `datarim/`). The helper applies the canonical formula
     `max(claimed across documentation/archive ∪ datarim/tasks.md ∪ datarim/backlog.md) + 1`
     over all three claim surfaces and auto-bumps on a parallel-session race, printing the chosen `QCK-NNNN` to stdout.
     **Documented fallback** (helper unavailable in this runtime): compute the same formula by hand.
   - **Do not emit or announce the chosen task ID — in reply text or in any artefact — until the helper has returned (its grep IS the 3-surface collision probe).**
   - If the computed candidate is already claimed (a parallel-session race on the agent's own new ID), the helper auto-bumps to the next free ID and emits a warning — no operator prompt.
   - `QCK` is a universal area-prefix; its archive subdirectory is `quick/`.

## Stage Header (mandatory)

After Step 2's probe completes and the task ID is known, emit `**{TASK-ID} · {title}**` as the first line of the post-Step-2 message block, per `$HOME/.claude/skills/cta-format/SKILL.md` § Stage Header. Do NOT emit the header before the ID is known (before the probe completes). Single occurrence per command invocation.
3. Append a thin one-liner task line to `tasks.md` and mirror it into `activeContext.md` § Active Tasks. Short English title. `status in_progress`, `priority P3`, `complexity L1` by convention (the fast-lane is for L1-sized work; if the work turns out larger, STOP and recommend `/dr-init` for the full pipeline).
4. Quick KB scan for context: spawn ONE subagent via the Agent tool, using the runtime's CHEAPEST / WEAKEST reasoning tier (vendor-neutral — each runtime resolves its own cheap tier). The subagent does a fast, shallow read of the knowledge base / codebase to locate where the change belongs (or to find what was asked). It returns only the relevant files/context, not a full analysis. This keeps the main (strong) context free and avoids the multi-hour full-analysis path.
5. Apply the fix (for a fix task) or report the located item (for a search task). The actual edit runs in the main context.
6. Write a SHORT archive: `documentation/archive/quick/archive-QCK-XXXX.md` — what was done (1-3 sentences) + files touched + a diff/commit reference. NO reflection, NO evolution proposals, NO compliance report. Flip the `tasks.md` one-liner to status `done`.

## When to use / When not to use

- **Use:** one-file or few-line fixes, typo/config tweaks, quick "where is X / does Y exist" lookups.
- **Not:** anything needing design, multiple files with shared state, security-sensitive logic, or architectural decisions — those go through `/dr-init` and the full pipeline.

## Boundaries

- Skips PRD, plan, design, QA, compliance, and reflection stages.
- QCK archive is intentionally minimal.
- If scope grows mid-task, escalate to `/dr-init`.

## Next Steps (CTA)

After the short archive, emit a CTA block per the cta-format skill. Primary recommendation: the task is done. Alternative: `/dr-init {TASK-ID-or-new}` if it turned out non-trivial. Always include `/dr-status`.

## Stage Snapshot Emission (Mandatory Terminal Step)

After the CTA block, perform snapshot emission per `$HOME/.claude/skills/cta-format/SKILL.md` § Snapshot Emission, bound for this command: `stage: quick`, `command: /dr-quick`, `captured-by: agent`, `recommended-next` = primary CTA option. Fail-closed: on non-zero writer exit, emit a single stderr warning line and continue. Kill switch `DATARIM_DISABLE_SNAPSHOT=1` is handled inside the library.