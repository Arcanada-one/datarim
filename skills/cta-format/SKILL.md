---
name: cta-format
description: Canonical CTA "Next Step" block format for every /dr-* command and pipeline agent. Load when generating slash-command output or finishing a phase.
current_aal: 1
target_aal: 2
---

# CTA Format — Canonical Specification

This skill is the **single source of truth** for the "Next Step" Call-to-Action block (the numbered Next-Step menu at the end of every pipeline command, one entry marked recommended) produced by every `/dr-*` command and every pipeline agent (`planner`, `architect`, `developer`, `reviewer`, `compliance`).

It exists because free-form Next-Step prose forces operators to mentally map task IDs to commands, especially when two or more tasks are active. The fix: every command output ends with a structured, predictable CTA block ([definition](../cta-format/SKILL.md)) with explicit task IDs and one marked primary action.

## When to Apply

- Any `/dr-*` command finishing its work — at the very end of the response.
- Any agent (planner / architect / developer / reviewer / compliance) returning control to the operator.
- After a phase boundary in `/dr-prd`, `/dr-plan`, `/dr-design`, `/dr-do`.
- After a QA / Compliance verdict (PASS, CONDITIONAL_PASS, BLOCKED, NON-COMPLIANT) — see § FAIL-Routing.

If a command intentionally produces no actionable next step (for example `/dr-help`, `/dr-status` in read-only mode), it MUST still emit a CTA block listing pipeline-entry commands.

## Stage Header (canonical for /dr-* responses)

Every task-scoped `/dr-*` command and CTA-emitting agent MUST begin its operator-visible response with a one-line **Stage Header** (the `**{TASK-ID} · {title}**` banner emitted at the start of every pipeline command) so the operator can immediately tell which task the output belongs to. The header sits at the *opposite* end of the response from the CTA block: CTA = footer (what to do next), Stage Header = banner (what we are working on right now). Operators may run 40+ concurrent tasks; without the header, multi-task context is ambiguous.

### Format

```
**{TASK-ID} · {title}**
```

| Element | Rule |
|---------|------|
<!-- gate:history-allowed -->
| `{TASK-ID}` | Full prefix-number form, for example `ARCA-0001`, `TUNE-0262`. Never a short form, never paraphrased. |
<!-- /gate:history-allowed -->
| Separator | U+00B7 MIDDLE DOT `·` (the same character used in `tasks.md` one-liners). Surround it with single ASCII spaces. |
| `{title}` | Title verbatim from the `tasks.md` one-liner — the substring between `L{N} · ` and ` → tasks/`. No truncation, no paraphrase. Schema cap ≤80 chars. |
| Markdown | Bold inline (`**…**`) — matches the CTA footer convention (`**Next step — {ID}**`). No additional formatting, no headers, no surrounding blockquote. |

### Placement

- **First line** of the operator-visible response — before any tool-call narration, summary, or prose.
- Emitted exactly **once per command invocation**. Do not repeat the header in subsequent tool responses, follow-ups, or after each phase boundary inside the same invocation.
- If the command produces purely silent tool execution with no text output, the header MAY be skipped — there is nothing to label.

### Exception List

The following commands and contexts MUST NOT emit a Stage Header:

| Command | Rationale | Handling |
|---------|-----------|----------|
| `/dr-help` | No single-task context. | Skip the header entirely. |
| `/dr-status` | Multi-task list; the command itself prints every ID. | Skip the header entirely. |
| `/dr-doctor` | Framework operation, not task-scoped. | Skip the header entirely. |
| `/dr-init` (Steps 1-3, pre-ID) | TASK-ID is not yet assigned. | Emit the header on the first line *after* Step 4 completes (once the TASK-ID has been determined). |
| `/dr-quick` (Step 1, pre-ID) | TASK-ID is not yet assigned (3-surface collision probe in Step 2 must complete first). | Emit the header on the first line *after* Step 2's probe completes (once the TASK-ID has been determined). |

### Edge Cases

- **Empty title** — impossible per schema; `tasks.md` one-liners always carry a title.
- **Title > 80 chars** — the schema cap upstream prevents this; total header length is ≤ ~99 chars in the worst case.
- **TASK-ID assignment mid-execution** — `/dr-init` and `/dr-quick` are in this state; every other command has a pre-bound ID before it emits any text. For both, the header is deferred until the TASK-ID is known (after the probe completes).
- **Multi-step / multi-message commands** — emit the header once, in the very first message; do not re-emit per phase.

### Enforcement

<!-- gate:history-allowed -->
Programmatic enforcement is opt-in via a Claude Code Stop hook (TUNE-0264) at `dev-tools/hooks/dr-output-stop.sh`. When registered in `~/.claude/settings.json § hooks.Stop[]`, the hook checks the first non-empty line of every assistant response against `^\*\*[A-Z]{2,10}-\d{4} · .+\*\*$` (Exception List above honoured: `/dr-help`, `/dr-status`, `/dr-doctor`, plus `/dr-init` until Step 4 emits the TASK-ID, plus `/dr-quick` until Step 2's probe emits the TASK-ID). Missing header on first occurrence → stdout JSON `{"decision":"block","reason":"..."}`; retry (`stop_hook_active=true`) degrades to stderr advisory (retry budget = 1). The same hook also enforces `human-summary.md § Output contract` when the user invoked `/dr-archive`, `/dr-compliance`, or `/dr-qa`. Opt-in instructions and the canonical `settings.json` snippet live in `docs/how-to/dr-output-hook.md`.
<!-- /gate:history-allowed -->

## Canonical Block — Single Active Task

The literal rendered shape (Russian header words are part of the canonical operator-visible output — the operator sees this exact text in production):

<!-- allow-non-ascii-block: canonical-russian-cta-block-rendered-verbatim-in-operator-output -->

```markdown
---

**Следующий шаг — {TASK-ID}** (L{N}, {status})

1. `/dr-{command} {TASK-ID}` — **рекомендуется** — {one-line purpose}
2. `/dr-{command} {TASK-ID}` — альтернатива — {one-line purpose}
3. `/dr-{command}` — {one-line purpose}

---
```

<!-- /allow-non-ascii-block -->

### Field rules

| Field | Rule |
|-------|------|
| Top/bottom separator | Markdown HR `---` (CommonMark, confirmed working in the Claude Code renderer). |
| Header | Exactly `**Следующий шаг — {TASK-ID}** (L{N}, {status})`. `{TASK-ID}` MUST resolve to one currently-active task. | <!-- allow-non-ascii: literal-russian-cta-header-token-required-by-canonical-format -->
| Number of options | Min 1, recommended 3, hard ceiling 5 (Miller / Hick / Chernev 2015). |
| Option syntax | `N. \`{command + args}\` — **рекомендуется** / альтернатива / {plain text} — {purpose}`. | <!-- allow-non-ascii: literal-russian-cta-marker-tokens-required-by-canonical-format -->
| Primary marker | Exactly one `**рекомендуется**` per block. Never zero, never two. | <!-- allow-non-ascii: literal-russian-cta-marker-token-required-by-canonical-format -->
| Purpose clause | One sentence, ≤80 chars. Describe outcome, not mechanics. |
| Task ID inclusion | Every command that operates on a specific task MUST include the `{TASK-ID}` argument inline. Pipeline-entry commands (`/dr-status`, `/dr-help`, `/dr-init`) MAY omit it. |

## Canonical Block — Multiple Active Tasks (Variant B)

When `## Active Tasks` in `datarim/activeContext.md` lists more than one task, append an "Другие активные задачи" (other active tasks) section: <!-- allow-non-ascii: literal-russian-section-name-token-required-by-canonical-format -->

<!-- allow-non-ascii-block: canonical-russian-cta-block-variant-b-rendered-verbatim-in-operator-output -->

```markdown
---

**Следующий шаг — {CURRENT-TASK-ID}** (L{N}, {status})

1. `/dr-{command} {CURRENT-TASK-ID}` — **рекомендуется** — {purpose}
2. `/dr-{command} {CURRENT-TASK-ID}` — альтернатива — {purpose}
3. `/dr-status` — посмотреть весь backlog

**Другие активные задачи:**
- {OTHER-TASK-ID-1} (L{N}) — `/dr-{recommended-command} {OTHER-TASK-ID-1}` — {1-3 word context}
- {OTHER-TASK-ID-2} (L{N}) — `/dr-{recommended-command} {OTHER-TASK-ID-2}` — {1-3 word context}

---
```

<!-- /allow-non-ascii-block -->

Rules:
- "Другие активные задачи" appears only when more than one task is active. Skip the section entirely with 0 or 1 active tasks. <!-- allow-non-ascii: literal-russian-section-name-token-required-by-canonical-format -->
- Each "other" entry shows the recommended next command for that task (deduced from its own pipeline state), not a menu of alternatives.
- Order entries by priority then complexity (P0 first; ties broken by L4 > L3 > L2 > L1).

## Canonical Block — FAIL-Routing

When `/dr-qa` returns BLOCKED or `/dr-compliance` returns NON-COMPLIANT, emit a FAIL-routing CTA. The header changes; the structure stays:

<!-- allow-non-ascii-block: canonical-russian-fail-routing-cta-rendered-verbatim-in-operator-output -->

```markdown
---

**QA failed для {TASK-ID} — earliest failed layer: Layer {N} ({Layer name})**

1. `/dr-{return-command} {TASK-ID}` — **рекомендуется** — {what to fix}
2. `/dr-{alternative-command} {TASK-ID}` — если {condition}
3. Эскалация — после 3 same-layer fails (loop guard)

---
```

<!-- /allow-non-ascii-block -->

Layer-to-command map (mirrors `skills/datarim-system/backlog-and-routing.md` § FAIL Return Routing):

| Failed Layer | Return Command |
|--------------|----------------|
| Layer 1 (PRD) | `/dr-prd {TASK-ID}` |
| Layer 2 (Design) | `/dr-design {TASK-ID}` |
| Layer 3 (Plan) | `/dr-plan {TASK-ID}` |
| Layer 3b (Expectations) | `/dr-do {TASK-ID} --focus-items <wish_id_1,...,N>` (the focus arg lists only the wish_ids flagged BLOCKED by `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-expectations-checklist.sh" --verify`) |
| Layer 4 (Code) | `/dr-do {TASK-ID}` |
| Compliance NON-COMPLIANT | `/dr-do {TASK-ID}` (default) or an earlier stage if a PRD / plan gap is identified |

### Expectations-FAIL CTA shape

When `/dr-qa` Layer 3b or `/dr-compliance` reports `BLOCKED` against the expectations checklist (the operator wishlist at `tasks/{TASK-ID}-expectations.md`, verified at `/dr-qa` and `/dr-compliance`), the FAIL-Routing CTA's primary line MUST carry the `--focus-items` argument verbatim from the validator's `Next step:` line. The header changes to `**Expectations BLOCKED для {TASK-ID} — N wish-item(s) missed/partial без override**` and the primary option shows the focus list inline: <!-- allow-non-ascii: literal-russian-paraphrase-warnings-required-by-canonical-format -->

<!-- allow-non-ascii-block: canonical-russian-expectations-fail-cta-rendered-verbatim-in-operator-output -->

```markdown
---

**Expectations BLOCKED для {TASK-ID} — 2 wish-item(s) missed/partial без override**

1. `/dr-do {TASK-ID} --focus-items item-two,item-three` — **рекомендуется** — закрыть ожидания оператора (см. § Expectations в QA-отчёте)
2. Дописать `override:` в `tasks/{TASK-ID}-expectations.md` если оператор принял частичное выполнение — затем повторить `/dr-qa {TASK-ID}`
3. Эскалация — после 3 same-layer fails (loop guard)

---
```

<!-- /allow-non-ascii-block -->

The header digit "N" MUST match the count of blocking wish-ids in the focus list — never paraphrase as "несколько" or "some". The order of wish-ids in the focus argument matches the validator's emission order (file order). Authors MUST NOT regroup or rename wish-ids in the CTA — the operator needs to be able to copy-paste the primary line directly into the shell. <!-- allow-non-ascii: literal-russian-paraphrase-warnings-required-by-canonical-format -->

## Authoring Rules for Agents

When an agent generates the CTA block:

1. **Resolve the task ID first.** Read `## Active Tasks` from `datarim/activeContext.md`. If 0 → suggest `/dr-init`. If 1 → use it. If more than one → use the task explicitly being worked on; surface the rest in the "Другие активные задачи" section. <!-- allow-non-ascii: literal-russian-section-name-token-required-by-canonical-format -->
2. **Choose the primary by complexity rules.** Per `backlog-and-routing.md`:
   - L1 after `/dr-do` → primary is `/dr-archive {ID}` (docs / deploy / maintenance tasks: in-loop verification — curl smoke / diff check / unit-level test — already ran in `/dr-do`; a separate QA pass adds no evidence).
   - L2 after `/dr-do` → primary is `/dr-archive {ID}`.
   - L3-4 after `/dr-plan` → primary is `/dr-design {ID}`.
   - L3-4 after `/dr-do` → primary is `/dr-qa {ID}`.
   - L3-4 after `/dr-qa` PASS → primary is `/dr-compliance {ID}`.
   - On any failure verdict → primary is the layer-return command per the FAIL-Routing table.
3. **List 2-3 reasonable alternatives** (not absurd ones). Prefer escape hatches (`/dr-status`) over off-pipeline commands.
4. **Render literally.** The block is markdown emitted as final output, not a prompt to the user — no surrounding prose.

## Anti-Patterns (DO NOT)

| Anti-pattern | Why bad | Correct form |
|--------------|---------|--------------|
| `Run /dr-prd or maybe /dr-plan, depends on what you want` | No primary, no task ID, prose burying the action. | Numbered list with one `**рекомендуется**` plus the task ID. | <!-- allow-non-ascii: literal-russian-paraphrase-required-as-anti-pattern-example -->
| `Next steps: → continue implementation` | Generic, not actionable. | `/dr-do {TASK-ID}` with an explicit ID. |
| 7+ numbered options | Choice paralysis (Miller / Chernev 2015). | Cap at 5; sweet spot 3. |
| `─── Следующий шаг ───` (box-drawing) | Mojibake on Windows (Claude Code issue #34247). | `---` Markdown HR. | <!-- allow-non-ascii: literal-russian-anti-pattern-example-from-rendered-output -->
| `## Следующий шаг` (header) | All headers render identical bold in the CC terminal — no hierarchy distinction. | Bold inline `**Следующий шаг — {ID}**`. | <!-- allow-non-ascii: literal-russian-anti-pattern-example-from-rendered-output -->
| Two `**рекомендуется**` markers | Defeats the primary-CTA hierarchy. | Exactly one. | <!-- allow-non-ascii: literal-russian-cta-marker-token-required-by-canonical-format -->
| Missing task ID in an actionable command | Re-introduces the original bug this format is designed to prevent. | Always include `{TASK-ID}` for task-scoped commands. |

## Examples

<!-- gate:history-allowed -->
The illustrative task IDs in the examples below (`ARCA-0001`, `TUNE-0031`, `TUNE-0032`, `AUTH-0001`, etc.) are placeholders for the rendered shape — substitute with the actual current task ID when emitting a real CTA block.

<!-- allow-non-ascii-block: canonical-russian-cta-block-examples-rendered-verbatim-in-operator-output -->

### Example 1 — `/dr-init` for a new L4 task (single active task)

```markdown
---

**Следующий шаг — ARCA-0001** (L4, in_progress)

1. `/dr-prd ARCA-0001` — **рекомендуется** — PRD обязателен для L4 (10 подзадач в backlog)
2. `/dr-design ARCA-0001` — если предпочитаешь начать с архитектуры
3. `/dr-status` — посмотреть подзадачи (ARCA-0004…ARCA-0013)

---
```

### Example 2 — `/dr-plan` complete, multiple active tasks

```markdown
---

**Следующий шаг — TUNE-0032** (L3, in_progress)

1. `/dr-design TUNE-0032` — **рекомендуется** — auto-transition после plan для L3
2. `/dr-do TUNE-0032` — если creative-phase не нужен
3. `/dr-status` — backlog overview

**Другие активные задачи:**
- TUNE-0031 (L1) — `/dr-do TUNE-0031` — update.sh implementation
- AUTH-0001 (L4) — `/dr-plan AUTH-0001` — PRD approved, 36 backlog items

---
```

### Example 3 — `/dr-qa` BLOCKED at Layer 3

```markdown
---

**QA failed для TUNE-0032 — earliest failed layer: Layer 3 (Plan)**

1. `/dr-plan TUNE-0032` — **рекомендуется** — пересмотреть план (missing rollback strategy)
2. `/dr-prd TUNE-0032` — если нужно ревизовать scope
3. Эскалация — после 3 same-layer fails (loop guard)

---
```

<!-- /allow-non-ascii-block -->

<!-- /gate:history-allowed -->

## Loading

Loaded by the following agents (declared in their `Context Loading` section):

- `agents/planner.md` — emits the CTA after `/dr-init`, `/dr-plan`.
- `agents/architect.md` — emits the CTA after `/dr-prd`, `/dr-design`.
- `agents/developer.md` — emits the CTA after `/dr-do`.
- `agents/reviewer.md` — emits the CTA after `/dr-qa` (PASS, CONDITIONAL_PASS, BLOCKED).
- `agents/compliance.md` — emits the CTA after `/dr-compliance` (COMPLIANT, NON-COMPLIANT).

Referenced from all 15 `/dr-*` command files in `commands/dr-*.md`.

## Templates

- `${DATARIM_RUNTIME:-$HOME/.claude}/templates/cta-template.md` — fill-in-the-blank Markdown snippet with placeholder tables for the three CTA shapes (Single Active Task, Multiple Active Tasks, FAIL-Routing). Use it when generating a CTA block in agent / command output; copy the appropriate snippet and substitute placeholders. Update both files together if the format changes.

## Snapshot Emission

**Terminal step (mandatory).** After emitting the CTA block, every `/dr-*` command MUST persist the final operator-visible response (Summary + Gate Results + CTA block) to `datarim/snapshots/{TASK-ID}.snapshot.md` via the runtime-resolved wrapper `${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/snapshot-writer-wrapper.sh`. The wrapper forces bash execution; a direct `source scripts/lib/snapshot-writer.sh && write_stage_snapshot` invocation fails silently under zsh-parent shells (`BASH_SOURCE[0]: parameter not set`) — agents invoking via the Bash tool inherit the user's login shell. The runtime-prefixed path is mandatory: a bare relative `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/snapshot-writer-wrapper.sh"` resolves against the agent's cwd, which is frequently the consumer workspace root (for example `~/arcanada/`) where the wrapper is absent — invocation then fails closed with a misleading "not found in repo" warning. Contract: `skills/stage-snapshot-writer/SKILL.md`. The snapshot serves as primary context for `/dr-next` and `/dr-orchestrate` after `/clear` or terminal close.

The stage value and the command literal are bound by the invoking command file (not inferred by the agent) — see each `commands/dr-*.md` § Stage Snapshot Emission for the literal stage / command pair.

Executable recipe (shellcheck-clean):

```bash
# After CTA emission, compose the rendered response once into a tempfile
# and call the writer once. The writer overwrites any prior snapshot for
# this TASK-ID (overwrite-not-append; old stage state is no longer current).
# Fill-ins bound by the invoking command: $STAGE is one of
# init prd plan design do qa compliance auto; $COMMAND is the slash-command
# literal (e.g. /dr-plan); $TASK_ID and $CTA_PRIMARY are likewise set by the caller.
REPO_ROOT="$(git rev-parse --show-toplevel)"
BODY_TMP="$(mktemp)"; OPTIONS_TMP="$(mktemp)"
trap 'rm -f "$BODY_TMP" "$OPTIONS_TMP"' EXIT
# … render the CTA block into "$BODY_TMP"; one option per line into "$OPTIONS_TMP" …
bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/snapshot-writer-wrapper.sh" \
    --root "$REPO_ROOT" \
    --task "$TASK_ID" \
    --stage "$STAGE" \
    --command "$COMMAND" \
    --captured-by agent \
    --recommended-next "$CTA_PRIMARY" \
    --options-file "$OPTIONS_TMP" \
    --body-file "$BODY_TMP" \
  || echo "warn: snapshot-writer-wrapper failed for $TASK_ID (continuing per V-AC-7)" >&2
```

Fail-closed semantics: a non-zero wrapper exit MUST surface a single stderr warning line; do not silently swallow, do not abort the surrounding command. Kill switch — env `DATARIM_DISABLE_SNAPSHOT=1` makes the writer a no-op (documented in `docs/how-to/stage-snapshots.md`); the warning line is suppressed under the kill switch.

**Harness journal side-effect.** When `/tmp/datarim-test-{TASK-ID}/` exists (created by `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/datarim-stage-probe-init.sh"`), the writer additionally appends one journal line per call to `/tmp/datarim-test-{TASK-ID}/journal.md` in the contract format `<stage> · <ISO-ts> · header-present:<y|n> · snapshot-written:y · cta-footer:<y|n> · snapshot-sha:<12-hex>`. Auto-detection is by directory presence; an absent harness directory is a no-op. See `docs/how-to/datarim-harness.md` for end-to-end harness usage.

Consumer side: `commands/dr-next.md` § Step 2.5 "Snapshot-First Read" and `commands/dr-orchestrate.md` § Snapshot-First Resume read the file before falling through to task-description / init-task / activeContext. The replay-prompt template lives in `skills/dr-next-snapshot-replay/SKILL.md` § Replay-prompt template.

## Versioning

Introduced in Datarim v1.16.0. See `docs/evolution-log.md` for provenance and source research.

The stage-snapshot terminal step was added in v2.13.0 — see § Snapshot Emission above.

Future changes to this format MUST update the golden fixtures in `tests/cta-format/` and `evolution-log.md`.
