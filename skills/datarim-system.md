---
name: datarim-system
description: Core Datarim rules. Load this entry first, then only the fragment needed for paths, storage, numbering, backlog, routing, or archive behavior.
runtime: [claude, codex]
current_aal: 1
target_aal: 2
---

# Datarim System Rules

> **Core system rules for Datarim (датарим). Always load this entry first.**
> "Datarim" and "датарим" are the same framework. Recognize both forms in any language context.

## Always-Apply Rules

- All Datarim workflow state lives in `datarim/` at the project root.
- Resolve the correct `datarim/` path before any read/write operation.
- Never create `datarim/` outside `/dr-init`.
- Use task IDs in `{PREFIX}-{NNNN}` format across the whole lifecycle.
- Keep `datarim/` for local workflow state and `documentation/archive/` for committed long-term archives.
- Never create `documentation/tasks/`.
- Use `$HOME/.claude/` or project-relative paths, not absolute machine-specific paths.
- **Operational files are thin indexes**: `tasks.md`, `backlog.md`, `activeContext.md` carry one-liner-per-task pointers — never full task content. Descriptions live in `tasks/{TASK-ID}-task-description.md`. `progress.md` is **abolished**. See § Operational File Schema below.

## Operational File Schema (v1.19.0+)

Operational files are **indexes**, not content. Each line answers: which task, what state, where the description lives. Detailed contract: `skills/datarim-doctor.md`.

### `tasks.md` and `backlog.md` line format

Canonical regex (anchored, single-line):

```
^- ([A-Z]{2,10}-[0-9]{4}) · (STATUS) · P[0-3] · L[1-4] · (.{1,80}) → tasks/\1-task-description\.md$
```

`STATUS` ∈
- `tasks.md`: `in_progress|blocked|not_started`
- `backlog.md`: `pending|blocked-pending|cancelled`

Separator: `·` (U+00B7 MIDDLE DOT). Arrow: `→` (U+2192). Title: 1–80 chars, single-line, no `→`.

Example:
<!-- gate:history-allowed -->
```
- <TASK-ID> · in_progress · P1 · L3 · <Title> → tasks/<TASK-ID>-task-description.md
```
<!-- /gate:history-allowed -->

Section headers (`## Active`, `## Pending`) and blank lines allowed; only `- {PREFIX}-{NNNN}` bullets are validated.

### `activeContext.md` thin contract (v2 — ≤30 lines)

One section only — strict mirror of `tasks.md` § Active:

```markdown
# Active Context

## Active Tasks
<!-- strict mirror of tasks.md § Active — identical lines, identical order -->
- {ID} · {status} · P{n} · L{n} · {title} → tasks/{ID}-task-description.md
```

**Removed in v1.19.1:** `## Последние завершённые` and `## Last Updated`
sections. Recency hint is now a runtime computation in `/dr-status --recent N`
that mtime-sorts `documentation/archive/**/archive-*.md`. Single source of
truth for completion history = `documentation/archive/`.

### `progress.md`

**Abolished as of v1.19.0.** `/dr-doctor --fix` deletes the file. Per-task
progress notes belong in `tasks/{TASK-ID}-task-description.md` § Implementation
Notes or in the archive doc.

### `backlog-archive.md`

**Abolished as of v1.19.1.** `/dr-doctor --fix` migrates each
entry to `documentation/archive/{area or cancelled}/archive-{ID}.md` with
per-task content-presence assertion, then deletes the file. `pre-archive-check.sh`
blocks when the file exists.

### Init-Task File Contract

`datarim/tasks/{TASK-ID}-init-task.md` is the verbatim record of the operator's
original `/dr-init` prompt. Sibling to the description file (same `{TASK-ID}`),
but answers a different question:

- **Description** (agent-authored) — what the agent plans to do.
- **Init-task** (operator-authored, captured at `/dr-init`) — what the operator
  literally asked for. Append-only by convention; readable by every pipeline
  command per `skills/init-task-persistence.md`.

Required frontmatter (8 fields, closed schema):

```yaml
---
task_id: <TASK-ID>           # ^[A-Z]{2,10}-[0-9]{4}$
artifact: init-task          # literal
schema_version: 1            # integer
captured_at: <YYYY-MM-DD>
captured_by: /dr-init        # literal
operator: <name>
status: canonical            # canonical | amended
source: /dr-init             # /dr-init | backlog
---
```

Two mandatory body headings: `## Operator brief (verbatim)`, `## Append-log
(operator amendments)`. Validator: `dev-tools/check-init-task-presence.sh
--task <ID>`. Multi-task scan with soft 30-day window:
`... --all`. Full contract: `skills/init-task-persistence.md`.

### Description File Contract

`datarim/tasks/{TASK-ID}-task-description.md` is the **only** place for task content. Required 12-key YAML frontmatter (closed schema):

```yaml
---
id: <TASK-ID>                 # ^[A-Z]{2,10}-[0-9]{4}$
title: <string>               # ≤ 80 chars
status: <enum>                # in_progress|blocked|not_started|pending|blocked-pending|cancelled
priority: <enum>              # P0|P1|P2|P3
complexity: <enum>            # L1|L2|L3|L4
type: <string>                # free-form (framework, infra, content, …)
project: <string>             # free-form (Datarim, Arcanada, Verdicus, …)
started: <date>               # YYYY-MM-DD
parent: <TASK-ID|null>
related: <list[TASK-ID]>      # empty list ok
prd: <relpath|null>           # e.g. prd/PRD-{ID}.md
plan: <relpath|null>          # e.g. plans/{ID}-plan.md
---
```

Body sections (markdown, ≤ 250 lines): `## Overview`, `## Acceptance Criteria`, `## Constraints`, `## Out of Scope`, `## Related`. Optional `## Implementation Notes`, `## Decisions`. Anything beyond ~250 lines → split into PRD/design doc.

### activeContext.md Write Rules

When mutating `## Active Tasks`:
- **Append** new task as a one-liner; do NOT remove other active tasks.
- **Remove** archived task on `/dr-archive`, keep other active tasks intact.
- **Convert** any legacy `**Current Task:** {ID}` line into the thin list before appending. (Self-heal via `/dr-doctor`.)

### Self-Heal Entry Points

- `/dr-init` Step 2.4 — probes `scripts/datarim-doctor.sh --quiet`; offers `/dr-doctor --fix` on non-compliance.
- `/dr-archive` pre-archive gate — `pre-archive-check.sh` validates line format; bypass with `--no-schema-check` only during in-flight migration.

## Fragment Routing

Load only the fragment needed for the current sub-problem:

- `skills/datarim-system/path-and-storage.md`
  Use for path resolution, core file locations, report storage, and archive/documentation boundaries.
- `skills/datarim-system/task-identity-and-context.md`
  Use for task numbering, active task tracking, prefix rules, and rename policy.
- `skills/datarim-system/model-assignment.md`
  Use for `model` / `effort` frontmatter rules and agent-skill assignment policy.
- `skills/datarim-system/backlog-and-routing.md`
  Use for backlog architecture, complexity levels, date handling, and mode transitions.
- `skills/datarim-system/command-and-archive-rules.md`
  Use for `/dr-` namespace rules, archive area mapping, project setup, and critical invariants.

## Quick Path Resolution Rule

Before writing any file to `datarim/`:

1. Check whether `datarim/` exists in the current working directory.
2. If not, walk up the directory tree until a parent containing `datarim/` is found.
3. If no such directory exists, stop and instruct the user to run `/dr-init`.

## Large-Plan Read Strategy (L3+ tasks)

When `/dr-do` enters an L3+ task whose plan, PRD, and supporting INSIGHTS read
together exceed ~600 lines, the default first move SHOULD be a single
external-context delegation rather than a sequential read of every artefact:

1. **Delegate the bulk read.** Issue one `coworker ask` call (or the project's
   equivalent external-context channel — see CLAUDE.md § Coworker Delegation /
   the runtime's external-LLM contract) against PRD + plan + INSIGHTS, with a
   question that asks for per-step / per-V-AC / per-file structured output.
2. **Read the structured summary, not the raw artefacts.** Apply the summary
   to drive implementation order, file paths, V-AC ↔ step mapping, and MOD
   touchpoints. Re-enter the raw artefacts only when the summary is
   ambiguous on a specific point.
3. **Re-use the same summary at `/dr-qa` and `/dr-compliance`.** The QA and
   compliance layers should reuse the structured spec — re-delegating
   produces drift between the implementation summary and the verification
   summary.

**When NOT to apply:** plans under 600 lines (direct read is cheaper);
tasks where exact line numbers and code-block fidelity matter more than
structure (literal `Edit` operations against the plan-quoted code).

**Rationale.** A 1.6k-line plan + PRD + INSIGHTS read costs ~50% of a
working context window if loaded raw, and forces re-reads at every
verification stage. One delegated call returns a stable specification that
anchors every subsequent decision and survives session compaction. This
pattern was canonicalised in v2 of the orchestrator plan (775-line plan, 436-line PRD,
431-line INSIGHTS) shipped end-to-end without ever reading the plan body
into the main context, with zero V-AC misses.

## Runtime / Canonical Identity (symlink-default)

Under the default install (v1.17.0+ symlink mode), `$HOME/.claude/{skills,agents,commands,templates}/{name}.md` and the corresponding `code/datarim/<scope>/{name}.md` in the cloned framework repo are **the same file** — same inode, same content, same writes. Verify with `stat -f %i <runtime-path> <repo-path>` (macOS) or `stat -c %i` (GNU); identical inode numbers confirm symlink-mode.

Implications when editing a runtime artefact:

- A single `Edit`/`Write` to either path is the entire change. No `cp` / `rsync` / "sync runtime" step exists by construction; copy-mode reflexes from pre-v1.17 do not apply.
- `git diff` in the canonical repo immediately shows the change — that is the single source of truth for review and commit.
- A double-write (edit runtime, then `cp` to repo) is a no-op at best and an inode-detaching footgun at worst. If `cp` reports `are identical (not copied)`, the install is symlinked and the cp was unnecessary.

Copy-mode installs (`./install.sh --copy`, Windows / FAT) keep the legacy two-file topology; in that mode the curate-runtime / check-drift dance still applies. Detect copy-mode by `stat`-ing the inodes: divergent inode numbers = copy-mode = manual sync needed.

## Loading Order (v1.17.0+)

Skills, agents, commands, and templates load from two layers:

1. **Framework layer:** `$HOME/.claude/{skills,agents,commands,templates}/{name}.md`.
   In symlink-mode (default since v1.17.0) this resolves to the
   cloned datarim repo. In copy-mode it resolves to local copies.
2. **Local overlay:** `$HOME/.claude/local/{skills,agents,commands,templates}/{name}.md`.
   User-private. Gitignored. Created empty by `install.sh`.

**Conflict resolution:** if a name collides between layer 1 and layer 2, the
local overlay wins. `validate.sh` emits a WARN line per detected override.

**Critical-skill blocklist (security contract).** Six skills carry the framework's
security and workflow invariants and MUST NOT be shadowed from `local/`:

- `skills/security.md`
- `skills/security-baseline.md`
- `skills/compliance.md`
- `skills/datarim-system.md`
- `skills/ai-quality.md`
- `skills/evolution.md`

If `$HOME/.claude/local/skills/<name>.md` matches any of the above, `validate.sh`
emits `ERROR: critical skill ... cannot be overridden via local/ overlay
(security contract)` and exits **1**. The blocklist is path-scoped to `skills/`;
identically named files under `local/agents/`, `local/commands/`, or
`local/templates/` keep the standard WARN behaviour. To customise behaviour of
a critical skill, fork the framework or contribute upstream — silent local
shadowing is rejected by design.

**Convention:** prefix local files with a personal namespace
(`local/skills/my-org-style.md`) to avoid accidental overrides of framework
skills you actually wanted to keep tracking upstream.

## Skill Discovery

Skills push the agent out of default behavior into a disciplined process. They only help if loaded *before* you act.

**The Rule:** invoke relevant skills BEFORE any response or action — including clarifying questions. Even a 1% chance a skill applies means check first; an unfit skill can be dropped, but decisions made without one cannot be undone. Discovery: `$HOME/.claude/skills/` (or the runtime's skill tool); `/dr-help` lists `dr-*` commands.

**Instruction Priority** when skills, project memory, and default behavior conflict:
1. User's explicit instructions (`CLAUDE.md` / `AGENTS.md` / conversation) — highest. The user is in control.
2. Datarim skills and framework rules — override default behavior in their domain.
3. Default runtime behavior — lowest.

If `CLAUDE.md` says "don't use TDD" and a skill says "always use TDD", follow `CLAUDE.md`.

**Skill Priority** when multiple apply: process skills first (`brainstorming`, `systematic-debugging`, `writing-plans`) decide *how*; implementation skills (`frontend-ui`, `infra-automation`, `ai-quality`) execute under that process. "Let's build X" → brainstorming first; "Fix this bug" → systematic-debugging first.

**Skill Types:** rigid (TDD, debugging, security gates) — follow exactly, the discipline is the value. Flexible (patterns, heuristics) — adapt principles to context. The skill itself declares which.

**Red Flags — rationalizations that mean STOP and check for skills:**

| Thought | Reality |
|---------|---------|
| "Simple question / quick check / not really a task" | Questions and actions are tasks. Check for skills. |
| "I need more context / let me explore first" | Skills tell you HOW to gather context. Check first. |
| "I remember this / I know what that means" | Skills evolve. Knowing ≠ invoking. Read current version. |
| "Doesn't need a skill / overkill / one thing first" | If a skill exists, use it. Simple things become complex. |
| "This feels productive" | Undisciplined action wastes time. Skills prevent that. |

User instructions describe goal (*what*), not workflow (*how*). "Just commit this" still requires TDD / verification / commit-message discipline — unless explicitly waived.

## Task Disposition Patterns

When closing a task, choose the disposition that matches the actual outcome:

| Disposition | When | Action |
|---|---|---|
| `completed` | All ACs PASS, full archive done | Standard `/dr-archive` flow → `documentation/archive/{area}/archive-{ID}.md` + `backlog-archive.md` ## Completed |
| `cancelled` | User abandoned the task; no deliverable shipped | `backlog-archive.md` ## Cancelled with status `cancelled`, date, **reason**. No archive document. |
| `absorbed` | Scope and deliverable fully delivered **inside another task** | `backlog-archive.md` ## Completed with status `absorbed`, link to absorbing task ID, note `delivered as part of {OTHER-TASK}`. No separate archive document — reference the absorbing task's archive. |
| `superseded` | Replaced by a newer task with broader/different scope; no deliverable from this ID | `backlog-archive.md` ## Cancelled with status `superseded`, link to replacing task. |

Source: prior incident — an `update.sh` deliverable was shipped inside a different task's scope; `cancelled` was inaccurate (deliverable existed) and `completed` was inaccurate (no separate archive). `absorbed` captures the reality and preserves audit trail.

