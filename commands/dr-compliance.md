---
name: dr-compliance
description: Adaptive post-QA hardening. Detects task type and applies matching verification checklist. Final quality gate before archiving.
---

# /dr-compliance — Adaptive Post-QA Hardening

**Role**: Compliance Agent
**Source**: `$HOME/.claude/agents/compliance.md`

## Instructions
1.  **LOAD**: Read `$HOME/.claude/agents/compliance.md` and adopt that persona.
2.  **RESOLVE PATH**: Find `datarim/` using standard path resolution.
3.  **TASK RESOLUTION**: Apply Task Resolution Rule from `$HOME/.claude/skills/datarim-system.md` § Task Resolution Rule. Use the resolved task ID for all subsequent steps.
4.  **LOAD SKILLS**:
    - `$HOME/.claude/skills/datarim-system.md` (Always)
    - `$HOME/.claude/skills/compliance.md` (Adaptive checklists)
5.  **DETECT TASK TYPE**: Read `datarim/tasks.md` (for the resolved task) and `datarim/activeContext.md`. Determine: code, documentation, research, legal, content, infrastructure, or mixed. Additionally, read `datarim/tasks/{TASK-ID}-init-task.md` if present (mandatory per `$HOME/.claude/skills/init-task-persistence.md`): the verbatim operator brief + every append-log block. Any divergence between the operator's stated intent and the verified output MUST be surfaced in the compliance report § Plain-language summary. Missing init-task is non-blocking — flag as advisory and continue.
5b. **VERIFY EXPECTATIONS** (mandatory when `datarim/tasks/{TASK-ID}-expectations.md` exists per `$HOME/.claude/skills/expectations-checklist.md`):
    -   Re-read the file. For each item under `## Ожидания`, run its `Как проверить (success criterion)` against the implementation and append one transition line to `#### История статусов` in the canonical format `<ISO> / <local> · /dr-compliance · <prior> → <new> · reason: <one-sentence plain ru>`. Update the item's `#### Текущий статус`.
    -   Invoke the routing validator:
        ```bash
        dev-tools/check-expectations-checklist.sh --verify {TASK-ID}
        ```
        -   Exit 0 + stdout marker `PASS` ⇒ proceed.
        -   Exit 0 + stdout marker `CONDITIONAL_PASS` ⇒ proceed; record «conditional» disposition in the compliance report § Plain-language summary.
        -   Exit 1 + stdout marker `BLOCKED` ⇒ compliance verdict is **NON-COMPLIANT** regardless of the rest of the checklist. Capture the validator's `Focus items:` and `Next step:` lines verbatim into the report and surface them in the FAIL-Routing CTA.
    -   Missing expectations file on L3-L4: surface as advisory finding in the report; on L1-L2 within the 30-day soft window: non-blocking.

6.  **APPLY CHECKLIST**: Execute the appropriate checklist(s) from the compliance skill:
    - **Code** → 7-step software checklist (lint, tests, coverage, CI/CD)
    - **Documentation** → completeness, accuracy, consistency, cross-references, audience
    - **Research** → methodology, citations, argument coherence, scope
    - **Legal** → jurisdiction, definitions, structure, rights/obligations
    - **Content** → factcheck, humanize, platform requirements, editorial standards
    - **Infrastructure** → configuration, rollback plan, monitoring, security
    - **Mixed** → apply relevant sections from each matching type
6.5. **APPEND Q&A IF ANY** (mandatory per `$HOME/.claude/skills/init-task-persistence.md` § Q&A round-trip contract): for every operator clarification round captured during compliance verification — either operator answer or autonomous agent-decision under FB-1..FB-5 — invoke `dev-tools/append-init-task-qa.sh` to persist the round into `datarim/tasks/{TASK-ID}-init-task.md § Append-log` before emitting the report.
    -   Write the question, answer, and rationale (when applicable) to temp files first; free-form text MUST come via `--*-file <path>` per Security Mandate § S1.
    -   Required flags: `--root <repo-root> --task {TASK-ID} --stage compliance --round <N> --question-file <path> --answer-file <path> --decided-by <operator|agent> --summary "<one-line>"`.
    -   When `--decided-by agent`: `--rationale-file <path>` MUST contain ≥ 50 non-whitespace characters citing the compliance-standard rationale.
    -   On contradiction with an expectation: add `--conflict-with <wish_id>` (+ optional `--conflict-detail-file`); CTA MUST route back to `/dr-do --focus-items <wish_id>` for closure before the task can be archived.
    -   Skip if no clarification rounds occurred.
7.  **REPORT**: Output compliance report with per-step results and overall verdict.
8.  **HUMAN SUMMARY**:
    - Load `$HOME/.claude/skills/human-summary.md`.
    - Emit the `## Отчёт оператору` (RU) / `## Operator summary` (EN) section, with the four mandated sub-sections, between the verdict / report block and the CTA block. Language follows the most recent operator message.
    - Source material: § Overview of the task description, per-step results from Step 6, and the verdict from Step 7.
    - Runs on every verdict (COMPLIANT, COMPLIANT_WITH_NOTES, NON-COMPLIANT). On NON-COMPLIANT the «Что не получилось» sub-section carries the failure detail in plain language and «Что дальше» paraphrases the FAIL-Routing CTA without command syntax.
    - The summary MUST honour the banlist + whitelist + per-paragraph escape-hatch contract from the skill (`<!-- gate:literal -->` … `<!-- /gate:literal -->` for verbatim quoted blocks only; max two fenced paragraphs per summary).
    - Output: chat. If `datarim/reports/compliance-report-{task_id}.md` exists, append the same section at the end of that file.
    - Length budget: 150–400 words **total across the four sub-sections** (not per sub-section). Hard upper bound.

## Output
- `datarim/reports/compliance-report-{task_id}.md` (if directory exists)
- Otherwise: report in chat

## Verdicts
- **COMPLIANT** — all checks pass
- **COMPLIANT_WITH_NOTES** — passes with minor observations
- **NON-COMPLIANT** — critical issues found, fix before archiving

## Next Steps (CTA)

After verdict, the compliance agent MUST emit a CTA block per `$HOME/.claude/skills/cta-format.md`. NON-COMPLIANT verdicts use the FAIL-Routing variant (see § FAIL-Routing in cta-format).

**Routing logic for `/dr-compliance`:**

- COMPLIANT or COMPLIANT_WITH_NOTES → primary `/dr-archive {TASK-ID}` (reflection runs internally as Step 0.5).
- NON-COMPLIANT, PRD/task alignment gap → primary `/dr-prd {TASK-ID}` (FAIL-Routing Layer 1; update requirements, resume forward)
- NON-COMPLIANT, expectations BLOCKED → primary `/dr-do {TASK-ID} --focus-items <wish_ids>` (FAIL-Routing Layer 3b; resolve operator-expectation misses listed by the validator, then re-run `/dr-qa` and `/dr-compliance` — new report gets `-v2` suffix)
- NON-COMPLIANT, code/test/lint/CI issues → primary `/dr-do {TASK-ID}` (FAIL-Routing Layer 4; fix, re-run `/dr-compliance` — new report gets `-v2` suffix)
- NON-COMPLIANT, source unclear → primary `/dr-do {TASK-ID}` (default)
- Loop guard: 3 same-layer fails → escalate to user

The CTA block MUST follow canonical FAIL-Routing format when NON-COMPLIANT (header changes to `**Compliance NON-COMPLIANT для {TASK-ID} — earliest failed layer: Layer N (Layer name)**`). Variant B menu when >1 active tasks.
