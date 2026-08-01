---
name: dr-init
description: Initialize a new Datarim task or scaffold a new project. Auto-detects intent from prompt context.
---

# /dr-init — Initialize New Task or Project

> **Contract.** Initialisation is the only command that may create `datarim/`, wires prefix → archive-subdir mapping, and selects task IDs that propagate through the rest of the pipeline. The structural compliance probe (Step 2.4 — `datarim-doctor.sh --quiet`), the workspace cross-task hygiene check (Step 2.5), and the PRD-waiver gate are enforced in code, independent of how the command is invoked. Prefer the canonical slash form (`/dr-init {DESCRIPTION}`) over manually creating `datarim/` artefacts: the slash command threads through every guard described in this file; ad-hoc paths skip them.

**Role**: Planner Agent (Initial)
**Source**: `$HOME/.claude/agents/planner.md`

## Instructions
0.  **INTENT DETECTION** — Determine whether the user wants to create a **project** or a **task**:
    - Scan the user's input for project creation signals:
      - English keywords: "create project", "new project", "init project", "scaffold project", "setup project"
      - Russian keywords: "создай проект", "новый проект", "инициализируй проект", "создать проект" <!-- allow-non-ascii: russian-trigger-phrases-detected-by-the-intent-classifier -->
      - Pattern: `/dr-init create project "Name"`
      - Pattern: `/dr-init new project for <description>`
    - **If project intent detected:**
      a. Load `$HOME/.claude/skills/project-init/SKILL.md` and follow its scaffolding flow.
      a1. **Secrecy signal:** if the brief carries a `secrecy: <domain>` annotation or a secret-core keyword (secret/proprietary algorithm, encoding scheme, compression mechanism), the skill scaffolds in **secrecy-aware mode** — mechanism-free `[REDACTED]` reference stubs + a `## Secrecy` gate emitted into CLAUDE.md at scaffold time (SKILL Step 4.5).
      b. **EXIT** — do not continue to the task flow below.
    - **If NO project intent detected:**
      → Continue to Step 1 (standard task flow, unchanged).

1.  **LOAD**: Read `$HOME/.claude/agents/planner.md` and adopt that persona.
2.  **RESOLVE PATH**: This is the ONLY command that may create `datarim/`. Resolve the correct location:
    - Find the **top-level git root** (`git rev-parse --show-toplevel`).
    - If the project uses submodules, use the **outermost** repo root (e.g., `local-env/`, not `aio-v2/`).
    - Create `datarim/` there ONLY if it does not already exist.
    - If creating for the first time:
      a. Create `backlog.md` from the template at `${DATARIM_RUNTIME:-$HOME/.claude}/templates/backlog-template.md`. (Create ONLY `backlog.md` — the separate completed/cancelled archive index was retired in v1.19.1; completed/cancelled prose now lives in `documentation/archive/{area|cancelled}/archive-{ID}.md`, and `backlog.md` carries only live items.)
      b. Create `documentation/archive/` directory (for long-term task archives).
      c. If `.gitignore` exists and does not contain `datarim/` → append `datarim/` to it.
      d. If `.gitignore` does not exist → ask user: "Create `.gitignore` with `datarim/`? (recommended — keeps workflow state local)"

### EXECUTION HOST

1. Source the resolver: `source "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/lib/execution-host.sh"`.
2. Call `eh_decision <workspace-root> <execution-hosts-map-path>` (default map: `~/.claude/local/config/execution-hosts.yml`).
3. On **off-host** (exit code 10), AUTO-DISPATCH -- do NOT stop and hand the command back for the operator to type. The `required_host` binding IS the operator's standing authorization to run there, and dispatch (spawning a remote tmux session) is a reversible transport action; every irreversible step (prod deploy, secret rotation, force-push, public message) stays hard-gated on the remote agent downstream. Contract:
   a. **RUN vs INSPECT.** Auto-dispatch only when intent is to RUN the task (operator asked to run/execute/go, autonomous-mode marker active, or reached via `/dr-auto`). On INSPECT/read-only intent, do NOT dispatch: proceed locally read-only and surface the dispatch directive as information, not a blocking question.
   b. **Before dispatch, probe for an existing session for this task** on the required host. If one exists and is live: DO NOT relaunch -- attach and monitor. If it exists but is dead/stale: report it and ask before resuming (resuming a partially-done mutating task is not unconditionally reversible). If absent: dispatch.
   c. **Target integrity (fail-closed).** Before the SSH, the target host key MUST match a pinned `known_hosts` entry and the map MUST be the operator-local gitignored file. Host-key mismatch, missing pin, or any probe failure -> STOP and report; NEVER run the stage locally (that violates the binding) and NEVER dispatch to an unverified host. Pass `<TASK-ID>`/`<root>` as single non-evaluated argv elements; the dispatch payload is the bare task-id only -- never forward an autonomy/confirm-suppression flag to the remote.
   d. **Exit 10 has exactly two outcomes: successful remote dispatch, or STOP-and-report.** Local execution of the stage is never an outcome of exit 10 (a corrupted/unreadable map under exit 10 is fail-CLOSED, not fail-open).
   e. **After dispatch/attach, act only as a READ-ONLY MONITOR.** Poll the task runtime status file (`datarim/runtime/<TASK-ID>.status`) and classify the remote pane (`dev-tools/classify-pane.sh`). Wait up to ~90s for the first status write; if none, re-send the bare task-id ONCE into the existing pane and wait once more; still none = FAILED-LAUNCH -> durable local log line + escalate + STOP (never silent re-dispatch). Steady-state supervise; when the remote agent hits a hard-gate, relay the question+options to the operator and pass back their choice as an option index -- NEVER answer a hard-gate yourself and never proceed on silence. Write one identifier-free local audit line per dispatch attempt.
4. On **unconfigured** (exit code 0, binding absent): proceed unchanged (fail-open).
5. On **on-host** (exit code 0, binding present): proceed normally.

Note: the machine-local PreToolUse guard remains the hard floor; this Step-0 check is the cooperative soft layer sharing the same resolver library.


2.4. **STRUCTURAL COMPLIANCE CHECK** (runs only when `datarim/` already exists — skip on first-time creation in Step 2):
    - Probe: `scripts/datarim-doctor.sh --quiet --root="$DATARIM_ROOT"` (exit code only).
    - **exit 0** → silent, continue to Step 2.5.
    - **exit 1** (non-compliant findings):
      - Print summary: `"datarim/ structure non-compliant: {N} findings"` (re-run without `--quiet` to surface counts).
      - Interactive (TTY, `[ -t 0 ]`) → prompt: `"Run /dr-doctor --fix? [Y/n]"`. Default Y.
        - Y → invoke `/dr-doctor --fix` (or directly `scripts/datarim-doctor.sh --fix --root="$DATARIM_ROOT"`), then continue.
        - n → print warning, continue with non-compliance (operator's call; `/dr-archive` schema gate will block later).
      - Non-tty (`! [ -t 0 ]`) → skip prompt, print warning, continue.
    - **exit 2** (migration error from a prior run) → print error, ABORT `/dr-init`. Operator inspects state manually.
    - **exit 3** (concurrent invocation, lock held) → wait briefly and retry once; if still held → ABORT.
    - **exit 4** (path-traversal violation in operational files) → print error, ABORT — security violation, do NOT continue.
    - This check is the self-heal entry point for the thin-index schema. See `skills/datarim-doctor/SKILL.md` for the canonical contract.

2.5. **WORKSPACE CROSS-TASK HYGIENE CHECK** (advisory, non-blocking):
    - After path resolution, run `git status --porcelain datarim/tasks.md datarim/activeContext.md datarim/backlog.md datarim/progress.md` (those that exist).
    - Grep their pending diffs for foreign task IDs (anything matching `[A-Z]+-[0-9]{4}` other than the new task being initialised).
    - If foreign IDs are found, emit a single-line advisory: `"Workspace datarim/* carries pending state for {N} other tasks: {ID1, ID2, ...}. Consider /dr-archive or commit before /dr-init."`
    - **Non-blocking** — operator proceeds at will. Skip silently if the workspace is clean or no `datarim/*.md` exist yet.
    - The staged-diff audit at `/dr-archive` already catches the tangle but only after the carry-over has already cost a session; surfacing it at `/dr-init` lets the operator clean state proactively.

2.5b. **TOPIC OVERLAP ADVISORY** (advisory, non-blocking; framework v2.7.0+):
    - Catches topic-overlap with **pending backlog items** — orthogonal to Step 2.5, which catches foreign task IDs in pending diffs. Recurrence motivating this gate: two backlog IDs spawned for one deliverable when an earlier pending item escaped notice during fresh `/dr-init`.
    - Skip silently when any of the following holds:
      - `datarim/backlog.md` absent or empty of `pending` items.
      - `python3` not on `PATH` (echo single-line `"python3 not available — topic-overlap check skipped"` and continue; framework dependency floor stays Bash-only).
      - The runtime root is missing `dev-tools/check-topic-overlap.py` (older install, advisory deferred until upgrade).
    - Otherwise invoke:
      ```bash
      printf '%s\n' "$USER_TASK_DESCRIPTION" | \
        python3 "$DATARIM_RUNTIME/dev-tools/check-topic-overlap.py" \
          --task-description - \
          --backlog "$DATARIM_ROOT/datarim/backlog.md" \
          --top-n 5 --min-overlap 2
      ```
      `$DATARIM_RUNTIME` is the framework code root (`code/datarim` in the framework repo, `~/.claude` after install). `$DATARIM_ROOT` is the workspace root (the parent of `datarim/`), so the backlog resolves to `$DATARIM_ROOT/datarim/backlog.md` — same semantic the ID-assign helper and the doctor `--root` contract use.
    - Stream stdout straight to the operator. The script is **exit 0 by contract** — exit code is ignored even on parse anomalies.
    - In non-tty / CI runs (`DATARIM_NONINTERACTIVE=1` or `! [ -t 0 ]`): capture stdout into the step report, never prompt.
    - When the advisory surfaces matches, operator chooses: `duplicate` (abort + `/dr-init {EXISTING-ID}`), `refine-scope` (narrow new task to avoid collision), or `orthogonal` (continue — overlap is incidental). Default on no operator input: continue.
    - Performance contract: completes ≤300 ms on a 500-item backlog (regression-gated by `tests/dr-init-topic-overlap-latency.bats`); false-positive rate <10% on a 30-item orthogonal corpus (`tests/dr-init-topic-overlap-fp-budget.bats`).

2.5c. **MISPLACED-DATARIM ADVISORY** (advisory, non-blocking; framework v2.19.0+):
    - Detects fragmented KB: more than one `datarim/` directory visible in the parent chain below the git-root, where the extra ones lack their own `.git/` boundary (i.e. they belong to the same repo as the canonical KB but live in a sub-path — a misplaced KB written by a parallel session that walked upward to the wrong anchor).
    - Skip silently when:
      - `pwd` is outside any git repository (no toplevel to anchor against).
      - The git toplevel has no `datarim/` (resolver falls back to walk-upward; no canonical anchor to compare against).
    - Otherwise run:
      ```bash
      DR_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
      if [ -n "$DR_ROOT" ] && [ -d "$DR_ROOT/datarim" ]; then
          MISPLACED=$(find "$DR_ROOT" -mindepth 2 -type d -name datarim \
              -not -path '*/.git/*' -not -path '*/code/datarim*' 2>/dev/null \
              | while read -r dir; do
                  parent_root=$(cd "$dir/.." && git rev-parse --show-toplevel 2>/dev/null)
                  [ "$parent_root" = "$DR_ROOT" ] && printf '%s\n' "$dir"
              done)
          if [ -n "$MISPLACED" ]; then
              printf 'ADVISORY: misplaced datarim/ detected under %s (canonical is %s/datarim):\n%s\nConsider consolidating — see skills/datarim-system/path-and-storage.md § Path Resolution Rule.\n' \
                  "$DR_ROOT" "$DR_ROOT" "$MISPLACED" >&2
          fi
      fi
      ```
    - **Non-blocking** — operator proceeds at will. The advisory exists so misplaced KB directories are noticed at `/dr-init` rather than discovered after parallel sessions have already accumulated artefacts in the wrong place.
    - Excludes `code/datarim` paths (framework source-tree, not KB) and any sub-directory that is itself a git toplevel (legitimate sub-repo with its own canonical KB).

2.5d. **KB-PUSH SENTINEL AGE ADVISORY** (advisory, non-blocking; framework v2.40.0+):
    - Surfaces cross-host sync drift: when the workspace carries a `datarim/.kb-last-push` sentinel, print its age so the operator sees at a glance whether the local KB is freshly synced or stale. A frequent root cause of "the artefacts disappeared" is a Mac↔VM sync lag; one read-only line saves a diagnostic round-trip.
    - Skip silently when `datarim/.kb-last-push` does not exist (most installs have no sentinel; absence is not an error).
    - Otherwise run (GNU `stat -c` first, BSD `stat -f` fallback — the binary differs by platform):
      ```bash
      if [ -f datarim/.kb-last-push ]; then
          mtime=$(stat -c %Y datarim/.kb-last-push 2>/dev/null || stat -f %m datarim/.kb-last-push 2>/dev/null)
          if [ -n "$mtime" ]; then
              printf 'KB-push sentinel age: %ss (datarim/.kb-last-push)\n' "$(( $(date +%s) - mtime ))"
          fi
      fi
      ```
    - **Non-blocking** — purely informational; the operator proceeds at will. No threshold, no failure mode: a large age is context, not a gate.

2.5e. **SYMPTOM-FRESHNESS RE-PROBE** (advisory-but-actionable; framework v2.54.0+):
    - Detects a stale ops-fire item: the symptom that motivated the task may already have been fixed in production between discovery and this `/dr-init` invocation, which would otherwise route it into the full `/dr-plan` pipeline for nothing.
    - Triggers when the task description / backlog one-liner matches either signal:
      - Live-fire wording — English keywords: "restart loop", "PROD fire", "prod fire", "active fire", "production down", "service down". Russian keywords: "рестарт-луп", "прод горит", "продакшн горит", "активный пожар" <!-- allow-non-ascii: russian-trigger-phrases-detected-by-the-intent-classifier -->
      - A `Source:` / `Spawned from:` reference pointing at an ecosystem pre-flight/ops-fire task (same reference convention `/dr-plan`'s Architectural-superseding probe reads at its Step 4 first sub-step).
    - Skip silently when neither signal matches — this step is scoped narrowly to ops-fire-shaped intake; ordinary feature/bugfix tasks are unaffected.
    - **When triggered, BEFORE continuing to Step 3**: re-probe live container/service state per the project's own deploy/health-check convention — e.g. an orchestrator status query, a health-endpoint curl, or equivalent. Stack-agnostic by design — this step names no specific tool; use whatever the project's own runbook or CI already defines as its liveness check.
    - **Probe shows the symptom already resolved** (fix landed in production between discovery and now): do NOT route to `/dr-plan`. Recommend closing the task as superseded/stale instead, and record the probe output as evidence in the task's Overview section.
    - **Probe shows the symptom still live, or the probe cannot be run** (no deploy access, no runtime reachable from this session): continue to Step 3 unchanged — this step never blocks, it only redirects an already-fixed item away from the planning pipeline.
    - Cost: one shell probe. Saving: avoids routing an already-fixed ops-fire item through the full `/dr-init` → `/dr-plan` pipeline. Source: a prior reflection proposal — that task lost 5h29m to staleness because the fix landed in production between discovery and `/dr-init` time, but `/dr-init` routed the task to `/dr-plan` as if the symptom were still live.

3.  **CHECK BACKLOG**: If `datarim/backlog.md` exists and contains pending items:
    - Display pending items as a numbered list (ID, title, priority, complexity).
    - **If user provided a `BACKLOG-XXXX` ID**: Select that item directly.
    - **If user said "pick from backlog"** or gave no task description: Show list and ask which to start.
    - **When selecting a backlog item**:
      a. Change its status from `pending` to `in_progress` in `backlog.md`.
      b. Use its description, priority, complexity, and acceptance criteria as starting context.
      c. **Use the backlog item's existing ID as the task ID** (do NOT create a new one). The ID stays the same across lifecycle per Unified Task Numbering.
    - **If backlog is empty** or user provided a new task description: Proceed to step 4.

3.5. **ARCHITECTURAL-SUPERSEDING PROBE** (mandatory when triggered; runs before any `tasks.md`/`activeContext.md` write):
    - **Trigger**: the description in scope for this invocation — the operator's freshly-typed prompt (direct-prompt flow) or, when Step 3 selected a backlog item, that item's stored description (backlog flow) — contains a `Source:` or `Spawned from:` keyword pointing at another task: an archive under `documentation/archive/*/archive-<ID>.md`, or an in-flight sibling still listed in `datarim/tasks.md` / `datarim/activeContext.md`.
    - Skip silently when no such reference is present, or the reference points only at a PRD (PRD ancestry is ordinary decomposition, not a supersession risk).
    - **Action**: read the referenced archive(s) or in-flight sibling task-description(s) in full and answer one question — *has the architectural problem this new task addresses already been resolved by the referenced sibling?*
        - **Yes, already resolved** → STOP before Step 4 creates `tasks.md`/`activeContext.md` entries. Present the operator a recommendation: cancel (do not create the task), reframe (narrow scope to whatever residual gap remains), or proceed anyway (operator confirms the sibling did not fully cover this problem). Do not write `datarim/tasks.md`, `datarim/activeContext.md`, or the init-task file until the operator resolves this prompt. Non-tty/CI (`! [ -t 0 ]` or `DATARIM_NONINTERACTIVE=1`): default to "proceed" and record the auto-decision in the init-task Append-log once Step 4.6 writes the file.
        - **No, not resolved / orthogonal** → continue to Step 4; note the consulted archive(s) inline so `/dr-plan` can reuse the finding instead of re-grepping.
    - Cost: one grep + skim of the referenced archive(s). Saving: avoids the full init → task-description → activeContext-entry cycle for a task later cancelled as redundant — catches supersession before any artefact exists, not after `/dr-plan` Phase 4 has already run.
    - This is the same probe `/dr-plan` Phase 4 used to run as its mandatory first sub-step; running it here catches redundancy earlier. `/dr-plan` now re-runs only a narrow fallback for archives that land after this step already passed — see `/dr-plan` Phase 4.

4.  **ACTION**:
    - Analyze the user request (or backlog item context from step 3).
    - Determine complexity level (1-4). If from backlog, use the item's complexity as starting estimate.
    - **Determine Task ID** (if NOT from backlog): select prefix per Unified Task Numbering (`$HOME/.claude/skills/datarim-system/SKILL.md`) — project prefix first, then area prefix, `TASK` as fallback. Then assign the next free ID by **running the canonical helper** (do NOT compute `max+1` mentally):
      `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/next-free-id.sh" {PREFIX} "$DATARIM_ROOT"`
      where `$DATARIM_ROOT` is the workspace root (the parent of `datarim/`). The helper applies the canonical formula `max(claimed across archive/datarim filenames ∪ line-leading index rows in datarim/tasks.md and datarim/backlog.md) + 1` and auto-bumps on a parallel-session race, printing the chosen `PREFIX-NNNN` to stdout. Note the deliberate asymmetry between its two internal probes: the CEILING above counts only structural positions (filenames, line-leading rows, held init-lock markers), because a number lifted from prose would walk the allocator out of the 4-digit space; the helper's separate COLLISION probe is far wider — prose mentions, live tmux session names and git worktree/branch names all count as claims, because over-claiming wastes one ID while under-claiming hands two agents the same one. The helper exits non-zero rather than emit an out-of-range ID. **Documented fallback** (helper unavailable in this runtime): compute the same formula by hand, and probe the wider surface before trusting the result.
    - **Atomic ID claim (MANDATORY — run this immediately after the helper prints the ID, before ANY artefact write):** `next-free-id.sh` is best-effort: two sessions can compute the same `max+1` candidate and both pass every read-only probe before either writes `tasks.md`. Close that TOCTOU window by claiming the ID atomically:
      `bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/dr-init-id-lock.sh" acquire {TASK-ID} "$DATARIM_ROOT"`
      - **exit 0** — you own `{TASK-ID}` for the write window. Proceed.
      - **exit 1** (`COLLISION: … claimed by a live session`) — a concurrent `/dr-init` holds it. Re-run `next-free-id.sh` (it reads held markers as claim surface 4, so it yields a different ID) and `acquire` again. Repeat until exit 0; never announce or write a `{TASK-ID}` whose `acquire` did not return 0.
      - **exit 2** — usage/validation error: fix the argument, do not proceed.
      Release the marker once `tasks.md` and the init-task file exist (end of Step 4.6), or on abort:
      `bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/dr-init-id-lock.sh" release {TASK-ID} "$DATARIM_ROOT"`
      A marker abandoned by a crashed session is reclaimed automatically after `DR_INIT_LOCK_TTL` (default 900s), so a crash bounds the ID's unavailability instead of wedging it. Skip silently when the helper is absent (older install) — the read-only probes below still apply.
    - **ID-collision probe (MANDATORY)**: **Do not emit or announce the chosen task ID — in reply text or in any artefact — until this collision probe completes.** The helper's grep IS the full claim-surface collision probe for the agent's own new ID. Additionally probe for foreign entries: `grep -lE "^- {TASK-ID} ·" datarim/backlog.md datarim/tasks.md 2>/dev/null` AND `ls documentation/archive/*/archive-{TASK-ID}.md 2>/dev/null`.
      - **Agent's OWN new-ID (parallel-session race):** The helper auto-bumps when the computed `max(...)+1` candidate is already claimed — it emits a warning to stderr and prints the next free ID. No operator prompt. This is the automated, self-targeted instance of reassignment.
      - **Race-window reservation.** The three claim surfaces only become visible once an artifact is written, leaving a TOCTOU window between ID selection and that first write in which two parallel sessions could pick the same ID. To close it, `next-free-id.sh` **atomically reserves** the selected ID via a `mkdir` mutex under `datarim/.id-reservations/{TASK-ID}` *before* it prints the ID — spanning the whole probe → first-write sequence (`mkdir` is atomic on POSIX incl. macOS APFS, so of two concurrent sessions exactly one wins and the other auto-bumps). A fresh reservation is a 4th claim surface. **Reversible:** the marker self-expires after `DATARIM_ID_RESERVATION_TTL` seconds (default 1800 — a crashed session never permanently burns an ID; stale markers are GC'd on the next selection), can be released explicitly with `next-free-id.sh --release {TASK-ID} "$DATARIM_ROOT"` (harmless once the real surface claims the ID), or removed manually via `rm -rf datarim/.id-reservations/{TASK-ID}`. The reservation store is gitignored runtime state.
      - **FOREIGN entry (someone else's queued work):** If ANY match appears for a FOREIGN entry — STOP and present a 3-way prompt to the operator: **(a) reassign the prior backlog/queued entry to the next free ID** (update both occurrence + any cross-references; recommended when the prior entry is `pending` and lower-priority — follow the retroactive-rename procedure in `$HOME/.claude/skills/dr-init-id-collision-window/SKILL.md` § Resolution — retroactive rename: sed-batch rename across artifact bodies, `git mv` per filename, thin-index updates, chmod restore on hardened audit logs; do not do a bare inline rename); **(b) cancel the prior entry** (delete from backlog with a one-line rationale); **(c) operator picks a different ID for the new task**. Do not proceed with `{TASK-ID}` until the collision is closed. Rationale: backlog ID-uniqueness ≠ tasks.md ID-uniqueness — gates downstream `/dr-archive` Step 3 against silent overwrite of an unrelated queued unit of work.
      - **CROSS-INSTANCE (advisory, non-blocking):** the two probes above scan only the single resolved instance. A fleet can hold several `datarim/` instances (a workspace root plus nested `Projects/*/datarim/` instances), and universal area prefixes span them all — so the same ID may already be claimed in a *sibling* instance for unrelated work, which single-instance scans never see. After the ID is chosen, run `bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/scan-id-across-instances.sh" {TASK-ID} "$DATARIM_ROOT" "$DATARIM_ROOT/datarim"` — a bounded, read-only scan of sibling `backlog.md`/`tasks.md` under `$DATARIM_ROOT` (pruning `.git`, `node_modules`, `.worktrees`, and framework `*/code/datarim/*` template trees; excluding the current instance, already covered above; matching only anchored entry lines, so prose mentions are ignored). Any `path:lineno:line` printed on **stdout** is a same-ID entry in another instance: surface it as a single advisory line (e.g. `"ID {TASK-ID} is also claimed in {N} sibling datarim instance(s): … — reconcile before it propagates downstream"`) and let the operator decide. **Do NOT block or auto-bump on it** — cross-instance duplication is a drift/confusion risk, not a silent-overwrite risk within this instance's `/dr-archive` (which writes only the resolved instance). The helper is **exit 0 by contract** (advisory; never gates `/dr-init`) and writes its scan-root + files-scanned scope banner to **stderr** for transparency about the bound. Default scan root `$DATARIM_ROOT` sees every instance nested beneath it (the dominant topology); when `/dr-init` is invoked from inside a nested instance, pass a broader workspace root as the second argument. Skip silently when the helper is absent (older install).
    - **Context Gathering**: For complex tasks, ensure context is gathered (via `/dr-prd`) before planning.
    - **PRD Waiver Check** (Level 3-4 only): If no PRD exists for this task (check `datarim/prd/PRD-{task-id}*.md` and parent PRD within 30 days), prompt: "No PRD found for this L3+ task. Options: (a) Run `/dr-prd` first, (b) State waiver reason (will be recorded as `**PRD waived:**` in tasks.md)." If user chooses (b), record the waiver in the task's Overview section. Retroactive-only enforcement is insufficient — the prompt at `/dr-init` is the canonical gate.
    - **If new project/service**: Load `$HOME/.claude/skills/tech-stack/SKILL.md` and identify the starting-point stack from the Default Recommendation column. For non-routine cases (cross-domain, stack-migration, operator-request), generate a Stack Proposal with 2-3 candidates with trade-offs per the Trigger Classifier; the operator chooses and the choice is recorded as a decision note in the plan.
    - Create/Update `datarim/tasks.md` with new task.
    - **Append** new task to `## Active Tasks` in `datarim/activeContext.md`. Do NOT remove existing active tasks. If `activeContext.md` uses legacy format (`**Current Task:**` single line), convert to `## Active Tasks` list first. See `$HOME/.claude/skills/datarim-system/SKILL.md` § activeContext.md Write Rules.
    - **Stage Header (header after Step 4)**: From this point onward in the response (after the TASK-ID has been determined), emit `**{TASK-ID} · {title}**` as the first line of the post-Step-4 message block per `$HOME/.claude/skills/cta-format/SKILL.md` § Stage Header. Do NOT emit the header during Steps 0-3 (TASK-ID is not yet known). Single occurrence per command invocation.
4.6. **WRITE INIT-TASK FILE** (mandatory, F1 contract — see `$HOME/.claude/skills/init-task-persistence/SKILL.md`):
    - Compute `INIT_TASK_FILE="datarim/tasks/{TASK-ID}-init-task.md"`.
    - Determine the source flow:
      - **Operator prompt flow** (default): the `ARGUMENTS` variable (the text the operator typed after `/dr-init`) becomes the body of `## Operator brief (verbatim)`. Frontmatter `source: /dr-init`.
      - **Backlog selection flow** (the task was picked from `backlog.md` in Step 3): copy the matched backlog item's description block verbatim into `## Operator brief (verbatim)`. Frontmatter `source: backlog`, `source_backlog_ref: backlog.md#{TASK-ID}`.
    - Write the file with the canonical 8-field frontmatter (`task_id`, `artifact: init-task`, `schema_version: 1`, `captured_at`, `captured_by: /dr-init`, `operator`, `status: canonical`, `source`) + two mandatory headings: `## Operator brief (verbatim)` and `## Append-log (operator amendments)` (empty placeholder `_(пусто на момент создания)_`). Optional `## Source command` block above the brief is recommended when the exact invocation differs from `ARGUMENTS` raw text. <!-- allow-non-ascii: russian-literal-template-placeholder-text-cited-verbatim -->
    - Probe: `bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-init-task-presence.sh" --task {TASK-ID} --root "$DATARIM_ROOT"` (where `$DATARIM_ROOT` is the parent of `datarim/` and `$DATARIM_RUNTIME` is the installed runtime root; falls back to `~/.claude` for default-symlinked installs that include `dev-tools/` in `INSTALL_SCOPES`). Exit 0 = OK; non-zero = print warning and continue (operator may amend manually).
    - Skip silently when re-running `/dr-init` on an existing backlog ID whose init-task already exists — preserve the verbatim history.
    - **License auto-sync**: when the Q&A round-trip (`skills/init-task-persistence/SKILL.md` § Q&A round-trip contract) records an operator license decision for this project, update the project's root `README.md` — replace the "License" section's "TBD" placeholder with the chosen license (name + SPDX identifier where applicable). Skip silently when `README.md` has no "License" section, or the section already names a concrete license (idempotent — never overwrite an operator-set value).

4.65. **CAPTURE FRAMEWORK VERSION BASELINE** (mandatory when the resolved
    implementation repository is the Datarim framework repository: it contains
    `VERSION`, `commands/`, and `skills/`):
    - Immediately after the canonical init-task passes its structural probe,
      before PRD/plan creation or framework edits, invoke:
      ```bash
      "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/capture-framework-version-baseline.sh" \
        --task {TASK-ID} --workspace "$DATARIM_ROOT" --repo <framework-repo>
      ```
    - The helper exclusively captures the current commit/tree and binds it to
      the task, repository identity, and raw init-task digest. Do not pass a
      caller-selected base SHA. A byte-identical re-entry is idempotent.
    - Exit 1 or exit 2 is a hard INIT failure for a framework task. Do not
      continue to PRD/plan and do not recapture later from `/dr-do`.

4.7. **WRITE EXPECTATIONS SKELETON** (mandatory for all complexity levels L1-L4 — see `$HOME/.claude/skills/expectations-checklist/SKILL.md` § When the file is created):
    - Compute `EXPECTATIONS_FILE="datarim/tasks/{TASK-ID}-expectations.md"`.
    - Skip silently when `EXPECTATIONS_FILE` already exists (re-run `/dr-init` on backlog ID, or operator-amended skeleton from a prior cycle) — preserve operator edits.
    - Else: extract N wishes from `## Operator brief (verbatim)` in the init-task.md file just written by Step 4.6:
      - **L1:** 1 wish — the primary operator goal (single most prominent intent).
      - **L2-L4:** 2-5 wishes — distinct operator intents enumerated separately.
      - Extraction approach: LLM extraction via the agent's own model context (consistent with `/dr-prd` Step 5.5b pattern). Quote operator wording where possible; default `evidence_type: empirical` per wish (operator corrects via amendment if `static` or `measurement` is more appropriate).
      - Hallucination mitigation: wish title MUST trace back to a phrase or paraphrasable concept in the brief; do NOT invent goals the operator did not state. Vague brief → use the fallback skeleton below.
    - Write the file from `${DATARIM_RUNTIME:-$HOME/.claude}/templates/expectations-template.md` with:
      - **Frontmatter (canonical):** `task_id`, `artifact: expectations`, `schema_version: 2`, `captured_at`, `captured_by: /dr-init`, `agent: planner`, `status: canonical`, `parent_init_task: {TASK-ID}-init-task.md`.
      - **Per-wish item:** title (plain Russian, ending with «.»), `wish_id` (kebab-slug, cyrillic allowed), `Что хочу проверить:` (1-2 sentences), `Как проверить (success criterion):` (concrete signal — file path, command, visible behaviour), `Связанный AC из PRD: «—»` (no PRD yet), `evidence_type: empirical` (default), `#### История статусов` one initial line `<ISO> / <local> · /dr-init · pending → pending · reason: пункт создан при инициализации задачи`, `#### Текущий статус` followed by a single bullet line carrying the value (`pending` on first write). <!-- allow-non-ascii: russian-expectations-field-names-and-status-history-cited-from-canonical-schema -->
      - **Schema (mandatory).** Items MUST use the canonical bullet-list shape from `skills/expectations-checklist/SKILL.md` § Body shape — i.e. one top-level bullet per wish (`- **<N>. <Title>**`) with **nested bullets** (`  - wish_id:`, `  - Что хочу проверить:`, …) and a two-line `Текущий статус` block (`  - #### Текущий статус` followed by `    - <value>`). Do **NOT** use heading-style items (`### N. Title`) or single-line «inline» status (`#### Текущий статус: pending`) — the validator parses only the bullet-list shape, and heading-style files are rejected on the very next pipeline step (see `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-expectations-checklist.sh" --task {TASK-ID} --report` for the exact errors emitted on schema drift). <!-- allow-non-ascii: russian-expectations-field-names-cited-from-canonical-schema -->
    - Probe: `bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-expectations-checklist.sh" --task {TASK-ID} --root "$DATARIM_ROOT"`. Exit 0 = OK; non-zero = print warning + continue (fail-soft — operator may amend manually).
    - **Fallback (empty / diffuse brief or LLM extraction failure):** write 1-wish skeleton with title «Цель задачи — TBD (оператор уточняет).», `wish_id: tsel-zadachi-tbd`, `evidence_type: empirical`, and an inline HTML comment `<!-- TODO: operator fills concrete wish at next /dr-prd or /dr-plan amendment -->`. This satisfies the L1+ mandate floor and surfaces the gap to the operator at the next pipeline step. <!-- allow-non-ascii: russian-fallback-skeleton-title-cited-from-template -->
    - This step applies to **all complexity levels L1-L4** (mandate scope — operator decision: «жёсткое требование без исключений»). <!-- allow-non-ascii: russian-operator-quoted-policy-cited-verbatim -->

5.  **SUBTASK BACKLOG** (Level 3-4 only):
    - If analysis reveals distinct subtasks or phases, present them to user:
      "This task has N identifiable subtasks. Add them to backlog for independent tracking?"
    - If approved: create entries in `datarim/backlog.md` using appropriate project/area prefix per Unified Task Numbering (NOT `BACKLOG-XXXX`). Subtasks of a project task typically share its project prefix.
6.  **OUTPUT**: Initialized task structure (including tech stack if applicable).

## Reusable Templates

- `${DATARIM_RUNTIME:-$HOME/.claude}/templates/task-template.md` — minimal Implementation-Plan scaffold (`Overview` / `Architecture Impact` / `Implementation Steps` / `Test Plan` / `Rollback Strategy` / `Validation Checklist`). Use when bootstrapping `datarim/tasks/{TASK-ID}-task-description.md` for L1-L2 tasks where the heavier `prd-template.md` would be overkill.

## /dr-auto Mode (when `DATARIM_AUTO_MODE=1`)

When auto-mode is active (env var `DATARIM_AUTO_MODE=1` AND the matching per-task marker — resolved via `dev-tools/auto-mode-marker.sh resolve --root <workspace> --task-id <TASK-ID>`, per-task `datarim/.auto/<TASK-ID>.mode` with legacy `datarim/.auto-mode-active` fallback — containing this TASK-ID), this command:

1. Consults `${DATARIM_RUNTIME:-$HOME/.claude}/skills/autonomous-mode/SKILL.md` § Question Suppression Ladder ([definition](../skills/autonomous-mode/SKILL.md)) before any `AskUserQuestion` or equivalent operator prompt at this stage.
2. Stage-specific suppression hooks:
   - Step 3 backlog item selection prompt — resolve via Ladder L1 (grep backlog by description match) before AskUserQuestion.
   - Step 3.5 Architectural-superseding probe — cancel/reframe/proceed decision resolved through Ladder L1-L2 (read the referenced sibling archive(s)); non-tty/CI default remains "proceed", logged once the init-task file exists.
   - Step 4 PRD waiver gate (L3-4) — resolve via Ladder L3 (operator-preference lookup in MEMORY.md feedback).
3. Discovered gaps → apply L1 Inline Resolution Rule ([definition](../skills/autonomous-mode/SKILL.md)) per `skills/autonomous-mode/SKILL.md`; log in `datarim/tasks/{TASK-ID}-auto-inline-log.md` if applied inline.
4. Hard-gated actions → escalate to operator through Ladder L5; log via `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh" --decided-by operator` per `skills/init-task-persistence/SKILL.md` § Q&A round-trip.
5. Mismatch (env var set, marker absent OR marker contains different TASK-ID) → emit single-line warning, treat as non-auto (fail-safe per `skills/autonomous-mode/SKILL.md` § When this skill is active).

## Next Steps (CTA)

After completing initialization, the planner agent MUST emit a CTA block ([definition](../skills/cta-format/SKILL.md)) per `$HOME/.claude/skills/cta-format/SKILL.md`.

**Routing logic for `/dr-init`:**

- New L1 task → primary `/dr-do {TASK-ID}` (single-file fix, ≤50 LoC)
- New L2 task → primary `/dr-plan {TASK-ID}` (planning before code)
- New L3-4 task without PRD → primary `/dr-prd {TASK-ID}` (PRD obligatory unless waiver)
- New L3-4 task with parent PRD <30 days → alternative `/dr-plan {TASK-ID}` (waiver path)
- Backlog had pending items shown → alternative `/dr-init {BACKLOG-ID}` for any other listed item
- Always include `/dr-status` as escape hatch

The CTA block MUST: (a) include resolved task ID, (b) mark exactly one primary recommendation marker per `cta-format.md`, (c) list ≤5 numbered options, (d) be wrapped in `---` HR. If >1 active tasks in `datarim/activeContext.md`, append the variant-B menu of other active tasks per `cta-format.md`.

## Stage Snapshot Emission (Mandatory Terminal Step)

After the `## Next Steps (CTA)` block above, the agent MUST perform snapshot emission ([definition](../skills/stage-snapshot-writer/SKILL.md)) per `$HOME/.claude/skills/cta-format/SKILL.md` § Snapshot Emission. Parameters bound for this command:

- `stage`: `init`
- `command`: `/dr-init`
- `captured-by`: `agent`
- `recommended-next`: primary CTA option (slash-prefixed `/dr-*` form)

Fail-closed: on non-zero writer exit, emit a single stderr warning line and continue (V-AC-7 contract). Kill switch `DATARIM_DISABLE_SNAPSHOT=1` is handled inside the library; under the switch the writer is a no-op without warning.
