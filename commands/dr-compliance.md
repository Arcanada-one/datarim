---
name: dr-compliance
description: Adaptive post-QA hardening. Detects task type and applies matching verification checklist. Final quality gate before archiving.
---

# /dr-compliance — Adaptive Post-QA Hardening

**Role**: Compliance Agent
**Source**: `$HOME/.claude/agents/compliance.md`

## Instructions

**Stage Header (mandatory)**: Emit `**{TASK-ID} · {title}**` as the first line of your response, before any tool-call narration. The title is the verbatim one-liner field from `tasks.md` (between `L{N} · ` and ` → tasks/`). Skip this header only for `/dr-help`, `/dr-status`, `/dr-doctor`, and `/dr-init` Steps 1-3 (which emit it immediately after Step 4). See `$HOME/.claude/skills/cta-format/SKILL.md` § Stage Header.
1.  **LOAD**: Read `$HOME/.claude/agents/compliance.md` and adopt that persona.
2.  **RESOLVE PATH**: Find `datarim/` using standard path resolution.
3.  **TASK RESOLUTION**: Apply Task Resolution Rule from `$HOME/.claude/skills/datarim-system/SKILL.md` § Task Resolution Rule. Use the resolved task ID for all subsequent steps.
4.  **LOAD SKILLS**:
    - `$HOME/.claude/skills/datarim-system/SKILL.md` (Always)
    - `$HOME/.claude/skills/compliance/SKILL.md` (Adaptive checklists)
5.  **DETECT TASK TYPE**: Read `datarim/tasks.md` (for the resolved task) and `datarim/activeContext.md`. Determine: code, documentation, research, legal, content, infrastructure, or mixed. Additionally, read `datarim/tasks/{TASK-ID}-init-task.md` if present (mandatory per `$HOME/.claude/skills/init-task-persistence/SKILL.md`): the verbatim operator brief + every append-log block. Any divergence between the operator's stated intent and the verified output MUST be surfaced in the compliance report § Plain-language summary. Missing init-task is non-blocking — flag as advisory and continue.
5b. **VERIFY EXPECTATIONS** (mandatory when `datarim/tasks/{TASK-ID}-expectations.md` exists per `$HOME/.claude/skills/expectations-checklist/SKILL.md`):
    -   Re-read the file. For each item under `## Ожидания`, run its `Как проверить (success criterion)` against the implementation and append one transition line to `#### История статусов` in the canonical format `<ISO> / <local> · /dr-compliance · <prior> → <new> · reason: <one-sentence plain ru>`. Update the item's `#### Текущий статус`. <!-- allow-non-ascii: russian-expectations-section-and-field-names-cited-from-canonical-schema -->
    -   Invoke the routing validator:
        ```bash
        "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-expectations-checklist.sh" --verify {TASK-ID}
        ```
        -   Exit 0 + stdout marker `PASS` ⇒ proceed.
        -   Exit 0 + stdout marker `CONDITIONAL_PASS` ⇒ proceed; record «conditional» disposition in the compliance report § Plain-language summary.
        -   Exit 1 + stdout marker `BLOCKED` ⇒ compliance verdict is **NON-COMPLIANT** regardless of the rest of the checklist. Capture the validator's `Focus items:` and `Next step:` lines verbatim into the report and surface them in the FAIL-Routing CTA.
    -   Missing expectations file on L3-L4: surface as advisory finding in the report; on L1-L2 within the 30-day soft window: non-blocking.
5c. **ANTI-DEFERRAL PROSE GATE (HARD)** per `$HOME/.claude/skills/expectations-checklist/SKILL.md`:
    -   Scan the QA report and the compliance report for self-deferral language — the failure mode where the agent labels its own incomplete work "out of scope / informational / not a blocker / will fix later" instead of finishing it. Unlike `/dr-qa` (advisory), at compliance this is a **hard** gate (mirrors the evidence-type advisory-at-QA / hard-at-compliance escalation):
        ```bash
        "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-deferral-prose.sh" \
            --file datarim/qa/qa-report-{TASK-ID}.md --task {TASK-ID} --root <repo-root>
        "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-deferral-prose.sh" \
            --file datarim/reports/compliance-report-{TASK-ID}.md --task {TASK-ID} --root <repo-root>
        ```
        (Skip the compliance-report scan on the first pass if the report is not yet written; run it after the report exists.)
    -   **Dual-repo tasks (workflow-state and touched code in different repos):** when the touched code lives in a repository nested under the workspace root (e.g. a framework task whose reports sit in the outer workspace repo while the code sits in a nested repo), add `--extra-repo <nested-repo-path>` to each scan so the touched-set covers the nested repo's `merge-base..HEAD`. Without it the scanner sees an empty touched-set from the outer root and fail-opens (advisory), making the gate a no-op for that class. `--extra-repo` is repeatable and additive; an unreadable path warns and is skipped (fail-open preserved).
    -   Exit 1 from either scan ⇒ compliance verdict is **NON-COMPLIANT**. The agent labelled self-inflicted incomplete work as deferrable without a verifiable follow-up/`blocked_by` artefact. Capture the findings verbatim into the report and route via the FAIL-Routing CTA to `/dr-do {TASK-ID} --focus-items <...>` — the gap MUST be finished in the same git branch and the same cycle, not absorbed into a self-filed backlog item. A legitimate deferral (time-dependent or hard external blocker) clears the gate only by citing a follow-up ID / `blocked_by` reference that exists in the KB.
    -   The scanner is fail-open on its own git-probe failure (warns, does not block) — an infrastructure hiccup never hard-blocks an otherwise-clean task.

6.  **APPLY CHECKLIST**: Execute the appropriate checklist(s) from the compliance skill:
    - **Code** → 7-step software checklist (lint, tests, coverage, CI/CD)
    - **Documentation** → completeness, accuracy, consistency, cross-references, audience
    - **Research** → methodology, citations, argument coherence, scope
    - **Legal** → jurisdiction, definitions, structure, rights/obligations
    - **Content** → factcheck, humanize, platform requirements, editorial standards
    - **Infrastructure** → configuration, rollback plan, monitoring, security
    - **Mixed** → apply relevant sections from each matching type
6.5. **APPEND Q&A IF ANY** (mandatory per `$HOME/.claude/skills/init-task-persistence/SKILL.md` § Q&A round-trip contract): for every operator clarification round captured during compliance verification — either operator answer or autonomous agent-decision under FB-1..FB-5 — invoke `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh"` to persist the round into `datarim/tasks/{TASK-ID}-init-task.md § Append-log` before emitting the report.
    -   Write the question, answer, and rationale (when applicable) to temp files first; free-form text MUST come via `--*-file <path>` per Security Mandate § S1.
    -   Required flags: `--root <repo-root> --task {TASK-ID} --stage compliance --round <N> --question-file <path> --answer-file <path> --decided-by <operator|agent> --summary "<one-line>"`.
    -   When `--decided-by agent`: `--rationale-file <path>` MUST contain ≥ 50 non-whitespace characters citing the compliance-standard rationale.
    -   On contradiction with an expectation: add `--conflict-with <wish_id>` (+ optional `--conflict-detail-file`); CTA MUST route back to `/dr-do --focus-items <wish_id>` for closure before the task can be archived.
    -   Skip if no clarification rounds occurred.
7.  **REPORT**: Output a compliance report file using the canonical structure from `${DATARIM_RUNTIME:-$HOME/.claude}/templates/compliance-report-template.md` (frontmatter `task_id`, `date`, `verdict`, optional `scope`; four top sections in strict order — «Начальная задача», «Как решили», «Артефакты задачи», «Следующие шаги» — followed by the audit addendum under `---` carrying `### Step-by-step verdicts`, `### Remaining risks`, `### Related`). <!-- allow-non-ascii: russian-archive-template-section-names-cited-from-template -->
    -   `## Начальная задача`: one Russian sentence sourced from `tasks/{TASK-ID}-init-task.md § Operator brief (verbatim)`, compressed to a single phrase. <!-- allow-non-ascii: russian-archive-template-section-name-cited-from-template -->
    -   `## Как решили`: single-level bullet list, one item per bullet in the operator brief (original order). Each bullet: bold operator-words quotation + Russian status word («выполнено» / «частично» / «не выполнено» / «неприменимо» — never the schema enum `met`/`partial`/`missed`/`n-a`) + one or two plain-language sentences. Expectations from `tasks/{TASK-ID}-expectations.md § Ожидания` are folded into the same list with marker `(уточнение брифа)` appended to the quotation. No tables in this section. <!-- allow-non-ascii: russian-archive-template-section-name-cited-from-template -->
    -   `## Артефакты задачи`: what was verified or hardened by this compliance pass (reports, modified files, refreshed contracts). Prose + bullets allowed; no verdict tables in this top section. <!-- allow-non-ascii: russian-archive-template-section-name-cited-from-template -->
    -   `## Следующие шаги`: either «всё закрыто» or concrete `/dr-*` commands / operator actions (including `/dr-archive`). <!-- allow-non-ascii: russian-archive-template-section-name-and-status-token-cited-from-template -->
    -   Audit addendum under `---`: `### Step-by-step verdicts` (the 7-step compliance table, wrapped in `<!-- gate:literal -->` fence to bypass the banlist on English column headings), `### Remaining risks`, `### Related`.
    -   Apply the banlist from `skills/human-summary/banlist.txt` to the prose in the top four sections; the audit addendum tables MAY use `<!-- gate:literal -->` fence when they include ASCII technical terms.
8.  **HUMAN SUMMARY**:
    - Load `$HOME/.claude/skills/human-summary/SKILL.md`.
    - Emit the `## Отчёт оператору` (RU) / `## Operator summary` (EN) section, with the four mandated sub-sections, between the verdict / report block and the CTA block ([definition](../skills/cta-format/SKILL.md)). Language follows the most recent operator message. <!-- allow-non-ascii: russian-operator-summary-section-name-cited-from-template -->
    - Source material: § Overview of the task description, per-step results from Step 6, and the verdict from Step 7.
    - Runs on every verdict (COMPLIANT, COMPLIANT_WITH_NOTES, NON-COMPLIANT). On NON-COMPLIANT the «Что не получилось» sub-section carries the failure detail in plain language and «Что дальше» paraphrases the FAIL-Routing CTA without command syntax. <!-- allow-non-ascii: russian-verdict-tokens-not-russian-but-line-flagged-for-utf8-quote -->
    - The summary MUST honour the banlist + whitelist + per-paragraph escape-hatch contract from the skill (`<!-- gate:literal -->` … `<!-- /gate:literal -->` for verbatim quoted blocks only; max two fenced paragraphs per summary).
    - Output: chat. If `datarim/reports/compliance-report-{task_id}.md` exists, append the same section at the end of that file.
    - Length budget: 150–400 words **total across the four sub-sections** (not per sub-section). Hard upper bound.

8.5. **REFLECT ON A PASSING VERDICT** (runs only when the Step 7 verdict is COMPLIANT or COMPLIANT_WITH_NOTES; skipped on NON-COMPLIANT):
    - Reflection now happens here, at the point of a successful compliance pass, rather than being deferred to `/dr-archive`. This makes `/dr-compliance` the stage that captures lessons-learned + evolution proposals, so they are not lost when a task is hardened but the operator does not archive immediately.
    - Load `$HOME/.claude/skills/reflecting/SKILL.md` and execute its workflow (single source of truth — do NOT inline the reflection steps here). It writes `datarim/reflection/reflection-{task_id}.md` and stamps `reflection_basis` from the just-written compliance report via `${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/reflection-freshness.sh --emit-basis datarim/reports/compliance-report-{task_id}.md`.
    - **Stamp last.** Compute and write `reflection_basis` as the FINAL action, after the report file is fully written — including the Step 8 human-summary section that gets appended to `compliance-report-{task_id}.md`. Any later append to the report changes its hash and makes the just-written reflection look stale at `/dr-archive`. If the report is edited after the basis is stamped, re-stamp from the final report.
    - Class A / Class B evolution gate applies exactly as in the skill (Class A → operator approval; Class B → hold for PRD update). If the operator rejects a Class A proposal, surface it but do NOT fail the compliance verdict — reflection rejection is not a compliance failure.
    - On NON-COMPLIANT this step does not run; `/dr-archive` Step 0.5 will force-generate reflection later (the file stays absent), preserving the mandatory-reflection guarantee.

## Output
- `datarim/reports/compliance-report-{task_id}.md` (if directory exists)
- Otherwise: report in chat

## Verdicts
- **COMPLIANT** — all checks pass
- **COMPLIANT_WITH_NOTES** — passes with minor observations
- **NON-COMPLIANT** — critical issues found, fix before archiving

## /dr-auto Mode (when `DATARIM_AUTO_MODE=1`)

When auto-mode is active (env var `DATARIM_AUTO_MODE=1` AND matching marker `datarim/.auto-mode-active` containing this TASK-ID), this command:

1. Consults `${DATARIM_RUNTIME:-$HOME/.claude}/skills/autonomous-mode/SKILL.md` § Question Suppression Ladder ([definition](../skills/autonomous-mode/SKILL.md)) before any `AskUserQuestion` or equivalent operator prompt at this stage.
2. Stage-specific suppression hooks:
   - Hardening decision points (apply Class A inline vs defer) — auto-apply L1 Class A per L1 Inline Rule; defer L2+/B with backlog item.
   - 7-step hardening readiness gates — proceed if Ladder L1-L2 confirm cleanliness; L5 only on contradictory signals.
3. Discovered gaps → apply L1 Inline Resolution Rule ([definition](../skills/autonomous-mode/SKILL.md)) per `skills/autonomous-mode/SKILL.md`; log in `datarim/tasks/{TASK-ID}-auto-inline-log.md` if applied inline.
4. Hard-gated actions → escalate to operator through Ladder L5; log via `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh" --decided-by operator` per `skills/init-task-persistence/SKILL.md` § Q&A round-trip.
5. Mismatch (env var set, marker absent OR marker contains different TASK-ID) → emit single-line warning, treat as non-auto (fail-safe per `skills/autonomous-mode/SKILL.md` § When this skill is active).

## Next Steps (CTA)

After verdict, the compliance agent MUST emit a CTA block per `$HOME/.claude/skills/cta-format/SKILL.md`. NON-COMPLIANT verdicts use the FAIL-Routing variant (see § FAIL-Routing in cta-format).

**Routing logic for `/dr-compliance`:**

- COMPLIANT or COMPLIANT_WITH_NOTES → primary `/dr-archive {TASK-ID}` (reflection runs internally as Step 0.5).
- NON-COMPLIANT, PRD/task alignment gap → primary `/dr-prd {TASK-ID}` (FAIL-Routing Layer 1; update requirements, resume forward)
- NON-COMPLIANT, expectations BLOCKED → primary `/dr-do {TASK-ID} --focus-items <wish_ids>` (FAIL-Routing Layer 3b; resolve operator-expectation misses listed by the validator, then re-run `/dr-qa` and `/dr-compliance` — new report gets `-v2` suffix)
- NON-COMPLIANT, code/test/lint/CI issues → primary `/dr-do {TASK-ID}` (FAIL-Routing Layer 4; fix, re-run `/dr-compliance` — new report gets `-v2` suffix)
- NON-COMPLIANT, source unclear → primary `/dr-do {TASK-ID}` (default)
- Loop guard: 3 same-layer fails → escalate to user

The CTA block MUST follow canonical FAIL-Routing format when NON-COMPLIANT (header changes to `**Compliance NON-COMPLIANT для {TASK-ID} — earliest failed layer: Layer N (Layer name)**`). Variant B menu when >1 active tasks. <!-- allow-non-ascii: russian-canonical-cta-marker-tokens-cited-from-cta-format-skill -->

## Stage Snapshot Emission (Mandatory Terminal Step)

After the `## Next Steps (CTA)` block above, the agent MUST perform snapshot emission ([definition](../skills/stage-snapshot-writer/SKILL.md)) per `$HOME/.claude/skills/cta-format/SKILL.md` § Snapshot Emission. Parameters bound for this command:

- `stage`: `compliance`
- `command`: `/dr-compliance`
- `captured-by`: `agent`
- `recommended-next`: primary CTA option (slash-prefixed `/dr-*` form)

Fail-closed: on non-zero writer exit, emit a single stderr warning line and continue (V-AC-7 contract). Kill switch `DATARIM_DISABLE_SNAPSHOT=1` is handled inside the library; under the switch the writer is a no-op without warning.
