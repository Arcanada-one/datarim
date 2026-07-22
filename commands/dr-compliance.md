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
2.  **RESOLVE PATH**: Find `datarim/` using standard path resolution (see `$HOME/.claude/skills/datarim-system/SKILL.md` § Path Resolution Rule). **For a task whose code lives under `Projects/<name>/code/`, NEVER probe `Projects/<name>/code/datarim/` for workflow artefacts — that path exists only for the Datarim framework's own repo (§ Path Resolution Rule point 5). Resolve `--root` to the project's git-toplevel `datarim/`.**

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

3.  **TASK RESOLUTION**: Apply Task Resolution Rule from `$HOME/.claude/skills/datarim-system/SKILL.md` § Task Resolution Rule. Use the resolved task ID for all subsequent steps.
4.  **LOAD SKILLS**:
    - `$HOME/.claude/skills/datarim-system/SKILL.md` (Always)
    - `$HOME/.claude/skills/compliance/SKILL.md` (Adaptive checklists)
5.  **DETECT TASK TYPE**: Read `datarim/tasks.md` (for the resolved task) and `datarim/activeContext.md`. Determine: code, documentation, research, legal, content, infrastructure, or mixed. Additionally, read `datarim/tasks/{TASK-ID}-init-task.md` if present (mandatory per `$HOME/.claude/skills/init-task-persistence/SKILL.md`): the verbatim operator brief + every append-log block. Any divergence between the operator's stated intent and the verified output MUST be surfaced in the compliance report § Plain-language summary. Missing init-task is non-blocking — flag as advisory and continue.
5b. **VERIFY EXPECTATIONS** (mandatory when `datarim/tasks/{TASK-ID}-expectations.md` exists per `$HOME/.claude/skills/expectations-checklist/SKILL.md`):
    -   Re-read the file. For each item under `## Ожидания`, run its `Как проверить (success criterion)` against the implementation and append one transition line to `#### История статусов` in the canonical format `<ISO> / <local> · /dr-compliance · <prior> → <new> · reason: <one-sentence plain ru>`. Update the item's `#### Текущий статус`. <!-- allow-non-ascii: russian-expectations-section-and-field-names-cited-from-canonical-schema -->
    -   Invoke the routing validator:
        ```bash
        "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-expectations-checklist.sh" --task {TASK-ID}
        "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-expectations-checklist.sh" --verify {TASK-ID}
        ```
        -   `--task` exit 1 (structural error, e.g. `verification-not-wired` from a
            `reproducible` wish without a resolvable `evidence_artifact`) ⇒ compliance
            verdict is **NON-COMPLIANT**. Capture the structural finding verbatim;
            route back to `/dr-do {TASK-ID}` to wire the test.
        -   `--verify` exit 0 + stdout marker `PASS` ⇒ proceed.
        -   `--verify` exit 0 + stdout marker `CONDITIONAL_PASS` ⇒ proceed; record «conditional» disposition in the compliance report § Plain-language summary.
        -   `--verify` exit 1 + stdout marker `BLOCKED` ⇒ compliance verdict is **NON-COMPLIANT** regardless of the rest of the checklist. Capture the validator's `Focus items:` and `Next step:` lines verbatim into the report and surface them in the FAIL-Routing CTA.
    -   Advisory findings (`evidence-artifact-is-stub`, `verification-mode-suggested-reproducible`) appear in stderr; they do not affect the `--task` exit code and are surfaced as PASS_WITH_NOTES annotations in the compliance report.
    -   Missing expectations file on L3-L4: surface as advisory finding in the report; on L1-L2 within the 30-day soft window: non-blocking.
5c. **ANTI-DEFERRAL PROSE GATE (HARD)** per `$HOME/.claude/skills/expectations-checklist/SKILL.md`:
    -   Scan the QA report and the compliance report for self-deferral language — the failure mode where the agent labels its own incomplete work "out of scope / informational / not a blocker / will fix later" instead of finishing it. Unlike `/dr-qa` (advisory), at compliance this is a **hard** gate (mirrors the evidence-type advisory-at-QA / hard-at-compliance escalation):
        ```bash
        "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-deferral-prose.sh" \
            --file datarim/qa/qa-report-{TASK-ID}.md --root <repo-root>
        "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-deferral-prose.sh" \
            --file datarim/reports/compliance-report-{TASK-ID}.md --root <repo-root>
        ```
        (Skip the compliance-report scan on the first pass if the report is not yet written; run it after the report exists.)
    -   **Dual-repo tasks (workflow-state and touched code in different repos):** when the touched code lives in a repository nested under the workspace root (e.g. a framework task whose reports sit in the outer workspace repo while the code sits in a nested repo), add `--extra-repo <nested-repo-path>` to each scan so the touched-set covers the nested repo's `merge-base..HEAD`. Without it the scanner sees an empty touched-set from the outer root and fail-opens (advisory), making the gate a no-op for that class. `--extra-repo` is repeatable and additive; an unreadable path warns and is skipped (fail-open preserved).
    -   Exit 1 from either scan ⇒ compliance verdict is **NON-COMPLIANT**. The agent labelled self-inflicted incomplete work as deferrable without a verifiable follow-up/`blocked_by` artefact. Capture the findings verbatim into the report and route via the FAIL-Routing CTA to `/dr-do {TASK-ID} --focus-items <...>` — the gap MUST be finished in the same git branch and the same cycle, not absorbed into a self-filed backlog item. A legitimate deferral (time-dependent or hard external blocker) clears the gate only by citing a follow-up ID / `blocked_by` reference that exists in the KB.
    -   The scanner is fail-open on its own git-probe failure (warns, does not block) — an infrastructure hiccup never hard-blocks an otherwise-clean task.

5d. **AUTOMATIC SPEC-GRAPH GATE**:
    -   Invoke an independent final graph check:
        ```bash
        "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/spec-graph-gate.sh" \
            --task {TASK-ID} --stage compliance --root <repo-root> --format json
        ```
    -   Include graph completeness, evaluated artifacts, trace buckets, and the report-only grade in the compliance audit addendum.
    -   Exit `2` makes the verdict **NON-COMPLIANT**. In explicit hard mode, exit `1` also makes the verdict **NON-COMPLIANT**. The grade letter never changes routing.

6.  **APPLY CHECKLIST**: Execute the appropriate checklist(s) from the compliance skill:
    - **Code** → 7-step software checklist (lint, tests, coverage, CI/CD)
    - **Documentation** → completeness, accuracy, consistency, cross-references, audience
    - **Research** → methodology, citations, argument coherence, scope
    - **Legal** → jurisdiction, definitions, structure, rights/obligations
    - **Content** → factcheck, humanize, platform requirements, editorial standards
    - **Infrastructure** → configuration, rollback plan, monitoring, security
    - **Mixed** → apply relevant sections from each matching type
6.4. **RE-ASSERT TEST-ENVIRONMENT VERIFICATION** (MANDATORY when the task ships runtime behaviour AND the project space has a test environment): load `$HOME/.claude/skills/test-env-verification/SKILL.md`. Read the `/dr-qa` Layer 4h record from `datarim/qa/qa-report-{TASK-ID}*.md`. The change MUST have been verified on the test environment — **backend AND frontend** — autonomously, before this task may be prepared for production. If the Layer 4h verdict is `PASS`/`PASS_WITH_NOTES`/`SKIP`/`NO-TEST-ENV`, carry it forward into the compliance verdict (record verbatim). If the record is ABSENT (QA predates this gate) and the task ships behaviour to a test-env-having project, run the autonomous procedure now (ship to test via `deploy:test`, exercise backend + frontend, capture results) — a `FAIL` or a missing verification makes compliance **NON-COMPLIANT** and routes back to `/dr-qa`. `NO-TEST-ENV`/`SKIP` never block. This gate complements (does not replace) the deploy-class prod-readiness probe: test-env functional verification precedes prod-readiness, which precedes the operator-gated prod deploy.
6.45. **RELEASE EVIDENCE GATES** (conditional, fail-closed):
    -   **GitHub Actions AC:** when an acceptance criterion requires GitHub Actions, run `dev-tools/check-github-actions-execution.sh` live against the actual required workflow, exact required job/status context, and full implementation SHA. Only exit `0` / `executed-success` from `evidence_source=github-api` is compliant. A follow-up task, provider outage, no-execution result, unrelated job, or successful canary cannot replace execution of the required job.
    -   **Public repository boundary:** for a new public repository or visibility transition, run `dev-tools/check-public-repository-boundary.sh` against the exact immutable ref, allowlist, canonical regex policy, and independently hashed secret-scan evidence. Also verify the provider's paginated hosted surfaces (Actions logs/artifacts, releases/assets, repository metadata, wiki/pages/issues/discussions as applicable) with redacted counts and no incomplete page. Any nonzero helper result, unscanned surface, unsupported object, or evidence drift makes the verdict **NON-COMPLIANT**.
    -   These checks are read-only. Do not print matches, tokens, signed URLs, or raw provider annotations. Secret findings route to containment/rotation; history mutation requires separate operator authorization.
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

When auto-mode is active (env var `DATARIM_AUTO_MODE=1` AND the matching per-task marker — resolved via `dev-tools/auto-mode-marker.sh resolve --root <workspace> --task-id <TASK-ID>`, per-task `datarim/.auto/<TASK-ID>.mode` with legacy `datarim/.auto-mode-active` fallback — containing this TASK-ID), this command:

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
