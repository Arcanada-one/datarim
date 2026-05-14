---
name: init-task-persistence
description: Init-task artifact contract — verbatim operator brief + append-log, mandatory read by every pipeline command. Source of truth for operator intent across the task lifecycle.
runtime: [claude, codex]
current_aal: 1
target_aal: 2
---

# Init-Task Persistence

> **Why this exists.** The operator's original prompt to `/dr-init` is the only
> place where intent is captured before the pipeline translates it into PRDs,
> plans, designs and code. Every later artefact paraphrases that intent. Without
> a verbatim, append-only record agents lose track of what the operator
> actually asked for; the only evidence of drift becomes the operator's memory.
>
> The init-task file is that record. It is created at `/dr-init` time and read
> by **every** subsequent pipeline command. Operators may extend it with an
> append-log; agents must read the whole log, not just the verbatim brief.

## File location and naming

```
datarim/tasks/{TASK-ID}-init-task.md
```

One file per task. Same `{TASK-ID}` as the corresponding
`{TASK-ID}-task-description.md`. The two files are siblings: description is
the agent's interpretation, init-task is the operator's untouched source.

## Artifact schema

Required YAML frontmatter (closed schema):

```yaml
---
task_id: <TASK-ID>            # ^[A-Z]{2,10}-[0-9]{4}$ — required
artifact: init-task           # literal — required
schema_version: 1             # integer — required
captured_at: <YYYY-MM-DD>     # date `/dr-init` ran — required
captured_by: /dr-init         # literal — required
operator: <name>              # operator identifier — required
status: canonical             # canonical | amended — required (transitions on first append)
source: /dr-init              # /dr-init | backlog — recommended
source_backlog_ref: <ref>     # only when source: backlog (e.g. backlog.md#TUNE-0042)
---
```

Optional fields (used by later phases — F4 browser QA, etc.):

```yaml
qa_browser_mode: headed       # headed | headless — F4 reference
```

## Body shape

Two mandatory headings, in this order, separated by the operator's verbatim
text:

```markdown
# {TASK-ID} — Init-Task (canonical operator brief)

> Контракт: оператор может на любом этапе работы дополнять файл; каждый этап
> pipeline ОБЯЗАН сверяться с ним и фиксировать в своём выходе любые
> расхождения.

## Source command

```
/dr-init «<the exact slash-command invocation>»
```

## Operator brief (verbatim)

<exact text the operator typed into `/dr-init`, verbatim, no edits>

## Append-log (operator amendments)

> Дополнения добавляются хронологически; каждое — отдельная подпись.
> Агенты должны читать **весь** append-log, не только верхний блок.

_(пусто на момент создания)_
```

## Append-log contract

- **Append-only by convention.** Operators may delete or edit prior entries;
  the validator does not enforce that. The convention exists so reviewers can
  trust the log as a chronological record.
- **One entry per amendment.** Each block starts with `### <ISO-8601 timestamp>
  — amendment by <author>` and lists the changes as plain prose or a
  short bullet list. No tables.
- **Reading order.** Agents read the verbatim brief first, then every
  append-log block in order. A divergence between any block and the agent's
  current plan MUST be surfaced in the agent's own output.
- **Status transition.** First operator amendment flips `status: canonical` to
  `status: amended` in the frontmatter.

## Mandatory read by pipeline commands

The following commands MUST read the init-task file at the start of their
execution and reconcile any divergence in their output document:

| Command | What it reads | Where divergence is recorded |
|--------|---------------|------------------------------|
| `/dr-prd` | verbatim brief + every append-log block | PRD § Discovery / Constraints |
| `/dr-plan` | verbatim brief + every append-log block | plan § Notes / Risks |
| `/dr-design` | verbatim brief + every append-log block | design doc § Decisions |
| `/dr-do` | verbatim brief + every append-log block | task-description § Implementation Notes |
| `/dr-qa` | verbatim brief + every append-log block | QA report § Expectations / Plain-language summary |
| `/dr-compliance` | verbatim brief + every append-log block | compliance report § Plain-language summary |
| `/dr-archive` | verbatim brief + every append-log block | archive doc § Выполнение ожиданий оператора |

`/dr-doctor` reads init-task **presence** (via `dev-tools/check-init-task-presence.sh
--all`) but not content; absent init-task on a non-archived task surfaces as a
finding scaled by per-task soft window.

## Backwards-compatibility window

- **Per-task 30-day rolling soft window.** Each task is protected from
  blocker-level findings for 30 days after its `created` date. After 30 days,
  missing init-task surfaces as a `warn` finding; never a blocker.
- **Archive immunity.** Tasks with `status: archived | completed | cancelled`
  in their description frontmatter are never flagged.
- **Legacy marker.** Operators MAY set `legacy: true` in a description's
  frontmatter to suppress findings indefinitely (e.g. tasks created before
  the contract existed).
- **No retroactive enforcement.** Pre-existing in-progress tasks at v2.8.0
  cutover are NOT auto-backfilled; they finish in legacy mode.

## Validation

`dev-tools/check-init-task-presence.sh` is the canonical validator.

- `--task <ID>`: validate one file. Exit 0 = OK, 1 = malformed/missing, 2 = usage.
- `--all`: scan all task-descriptions for missing init-tasks. Always exit 0;
  findings printed as `<severity>: <ID> <reason>` lines. Severity ladder is
  `info` (< 30 days) → `warn` (>= 30 days). Never escalates to blocker.

## /dr-init behaviour (Step 2.6)

After path resolution and task-description scaffolding, `/dr-init` writes
the init-task file. Two source flows:

1. **From operator prompt:** verbatim text passed via `ARGUMENTS` becomes the
   body of `## Operator brief (verbatim)`. Frontmatter `source: /dr-init`.
2. **From backlog selection:** the matched backlog item's description block
   is copied verbatim as `## Operator brief (verbatim)`. Frontmatter
   `source: backlog`, `source_backlog_ref: backlog.md#<ID>`.

Empty `## Append-log` placeholder is always written.

After writing, `/dr-init` invokes
`dev-tools/check-init-task-presence.sh --task <ID>` and surfaces non-zero
exit as a warning (the description and operational-file work still
continues — operator may fix the init-task manually).

## Dogfooding

The first task to use this contract is the task that defines it. Its own
init-task lives at `datarim/tasks/{TASK-ID}-init-task.md` of the framework
workspace; downstream stages of that task verify the contract against
itself before the rest of the framework picks it up.
