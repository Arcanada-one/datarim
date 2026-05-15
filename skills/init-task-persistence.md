---
name: init-task-persistence
description: Init-task artefact: verbatim operator brief + append-log, mandatory read by every pipeline command. Source of truth for operator intent.
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
source_backlog_ref: <ref>     # only when source: backlog (e.g. backlog.md#<backlog-id>)
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
- **One entry per amendment.** Each block starts with `### <ISO 8601 timestamp>
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

## Q&A round-trip contract

The append-log captures two kinds of entries: operator-authored amendments
(see § Append-log contract above) and **agent-driven Q&A rounds** — every
question the agent asks the operator during a pipeline stage and its
matching answer. The mechanism makes the source-of-truth for operator
intent grow with the work; no clarification is ever lost between sessions.

### When a Q&A round MUST be appended

Six pipeline commands write Q&A blocks: `/dr-prd`, `/dr-plan`,
`/dr-design`, `/dr-do`, `/dr-qa`, `/dr-compliance`. Each command's step
"APPEND Q&A IF ANY" runs near the end of the stage. Every operator
clarification an agent obtained during the stage MUST end up in the file
before the stage emits its CTA. `/dr-init` (which creates the file) and
`/dr-archive` (read-only consumer for "operator expectations" recap) do
not write Q&A blocks.

### Block format (canonical)

Each round is a single Markdown block under § Append-log. The block
follows the `### <ISO> — amendment by …` convention but uses a distinct
marker so `grep` and the validator can tell the two apart.

```markdown
### <ISO 8601 timestamp> — Q&A by /dr-<stage> (round <N>)

**Question (verbatim, asked by <agent role>):**

<exact question text>

**Answer (verbatim, by <operator|agent>):**

<exact answer text>

**Decided by:** operator | agent

**Decision rationale:**

<≥ 50 characters; MANDATORY when Decided by: agent — must explain why
the agent picked this option (best-practice reference, prior archive,
FB-rules link)>

**Summary (how it changes initial conditions):**

<one or two lines>

**Conflict with existing wish:** none | <wish_id> — <description>
```

Six fixed subheadings are required on every block: `Question`,
`Answer`, `Decided by`, `Summary`, and `Conflict with existing wish`.
`Decision rationale` is required only when `Decided by: agent`; when
present, its body MUST contain at least 50 non-whitespace characters.

### Operator answer vs agent decision

- `Decided by: operator` — the operator responded; `Answer` carries the
  verbatim response. `Decision rationale` is not required.
- `Decided by: agent` — no operator answer was available in a reasonable
  window OR the question was non-critical; the agent chose the option by
  best practices. `Decision rationale` is mandatory and must reference
  the basis of the choice (FB-1..FB-5, archive precedent, framework
  contract). These autonomous decisions are verified at `/dr-qa`
  Layer 3b the same way operator answers are.

### Conflict handling

If a Q&A round contradicts a wish in `tasks/{TASK-ID}-expectations.md`
or a clause of the verbatim brief, set `Conflict with existing wish:
<wish_id> — <description>`. The agent MUST NOT silently overwrite the
prior wish; the stage's CTA must route work back to either
`/dr-do --focus-items <wish_id>` (when found during `/dr-qa` or
`/dr-compliance`) or back to `/dr-prd` (when found during planning /
design). A matching closure entry — operator amendment or follow-up Q&A
that resolves the conflict — is what the Layer 3b checker looks for.

### Utility — `dev-tools/append-init-task-qa.sh`

Pipeline commands do not write the block by hand. They invoke the
utility:

```
append-init-task-qa.sh \
    --root <path> \
    --task <ID> --stage <prd|plan|design|do|qa|compliance> --round <N> \
    --question-file <path> --answer-file <path> \
    --decided-by <operator|agent> \
    [--rationale-file <path>] \
    --summary "<one-line text>" \
    [--conflict-with <wish_id>] \
    [--conflict-detail-file <path>]
```

All textual inputs come via `--*-file <path>` (no literals on the CLI)
per Security Mandate § S1 — this prevents shell-injection through
operator answers that contain quotes, backticks, or `$(…)` constructs.
Exit codes: `0` appended OK, `1` validation/IO error, `2` usage error.
Writes are atomic: the utility takes a per-task `flock`
(`datarim/tasks/.{TASK-ID}.qa-lock`), prepares the new content in a
temp-file, then `mv`-s it into place.

### Validation extension

`dev-tools/check-init-task-presence.sh --task <ID>` extends the existing
structural validator with a Q&A pass. For every block whose heading
matches `^### .+ — Q&A by /dr-[a-z-]+ \(round [0-9]+\)$`, the validator
asserts:

1. All five mandatory subheadings present.
2. `Decided by:` value ∈ `{operator, agent}`.
3. When `Decided by: agent` — `Decision rationale:` subheading present
   and its body ≥ 50 non-whitespace characters.

Any violation raises exit 1 with a `Q&A block:` finding line.

### Legacy fallback

Tasks created before this contract shipped (2.9.0) do not require Q&A
blocks. The `/dr-doctor` rolling soft window from § Backwards-compatibility
window applies to the file's presence; **absence of Q&A blocks inside an
otherwise valid init-task is never a finding**. The agent falls back to
`tasks/{TASK-ID}-task-description.md` for intent.

## Dogfooding

The first task to use this contract is the task that defines it. Its own
init-task lives at `datarim/tasks/{TASK-ID}-init-task.md` of the framework
workspace; downstream stages of that task verify the contract against
itself before the rest of the framework picks it up.
