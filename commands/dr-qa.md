---
name: dr-qa
description: Multi-layer quality verification — checks PRD alignment, design conformance, plan completeness, and code quality
---

# /dr-qa - Multi-Layer Quality Verification

**Role**: Reviewer Agent
**Source**: `$HOME/.claude/agents/reviewer.md`

## Instructions


**Stage Header (mandatory)**: Emit `**{TASK-ID} · {title}**` as the first line of your response, before any tool-call narration. The title is the verbatim one-liner field from `tasks.md` (between `L{N} · ` and ` → tasks/`). Skip this header only for `/dr-help`, `/dr-status`, `/dr-doctor`, and `/dr-init` Steps 1-3 (which emit it immediately after Step 4). See `$HOME/.claude/skills/cta-format/SKILL.md` § Stage Header.
1.  **LOAD**: Read `$HOME/.claude/agents/reviewer.md` and adopt that persona.
2.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system/SKILL.md` § Path Resolution Rule.
3.  **TASK RESOLUTION**: Apply Task Resolution Rule from `$HOME/.claude/skills/datarim-system/SKILL.md` § Task Resolution Rule. Use the resolved task ID for all subsequent steps.
4.  **SKILL**: Read `$HOME/.claude/skills/security/SKILL.md` and `$HOME/.claude/skills/testing/SKILL.md`.
5.  **CONTEXT**: Read `datarim/tasks.md` to get the resolved task's implementation plan. Read `datarim/activeContext.md` for current state. Additionally, read `datarim/tasks/{TASK-ID}-init-task.md` if present (mandatory per `$HOME/.claude/skills/init-task-persistence/SKILL.md`): the verbatim operator brief + every append-log block. Any divergence between the operator's stated intent and the implementation MUST be flagged in the QA report § Expectations / § Plain-language summary. Missing init-task is non-blocking — flag as advisory and continue.
6.  **ACTION**: Execute the verification layers below in order. Layers 1, 2, 3, 4 are the classical multi-layer review; Layer 3b is the expectations-verification gate (runs after Layer 3 when `datarim/tasks/{TASK-ID}-expectations.md` exists). Skip layers whose artifacts do not exist.
6.5. **APPEND Q&A IF ANY** (mandatory per `$HOME/.claude/skills/init-task-persistence/SKILL.md` § Q&A round-trip contract): for every operator clarification round captured during the review — either operator answer or autonomous agent-decision under FB-1..FB-5 — invoke `dev-tools/append-init-task-qa.sh` to persist the round into `datarim/tasks/{TASK-ID}-init-task.md § Append-log` before emitting the QA report.
    -   Write the question, answer, and rationale (when applicable) to temp files first; free-form text MUST come via `--*-file <path>` per Security Mandate § S1.
    -   Required flags: `--root <repo-root> --task {TASK-ID} --stage qa --round <N> --question-file <path> --answer-file <path> --decided-by <operator|agent> --summary "<one-line>"`.
    -   When `--decided-by agent`: `--rationale-file <path>` MUST contain ≥ 50 non-whitespace characters of best-practice rationale. Layer 3b will verify each agent-decision against the implementation.
    -   On contradiction with an expectation: add `--conflict-with <wish_id>` (+ optional `--conflict-detail-file`); CTA MUST route back to `/dr-do --focus-items <wish_id>` for closure.
    -   Skip if no clarification rounds occurred.
7.  **OUTPUT**: Write `datarim/qa/qa-report-{task-id}.md` with results.
8.  **HUMAN SUMMARY**:
    - Load `$HOME/.claude/skills/human-summary/SKILL.md`.
    - Emit the `## Отчёт оператору` (RU) / `## Operator summary` (EN) section, with the four mandated sub-sections, between the QA-report write and the CTA block. Language follows the most recent operator message.
    - Source material: § Overview of the task description, per-layer verdicts, expectations checklist statuses (if Layer 3b ran), and the overall verdict.
    - Runs on every overall verdict (ALL_PASS, CONDITIONAL_PASS, BLOCKED). On BLOCKED the «Что не получилось» sub-section carries the failure detail in plain language and «Что дальше» paraphrases the FAIL-Routing target layer name (without command syntax — the CTA below carries that verbatim).
    - The summary MUST honour the banlist + whitelist + per-paragraph escape-hatch contract from the skill (`<!-- gate:literal -->` … `<!-- /gate:literal -->` for verbatim quoted blocks only; max two fenced paragraphs per summary).
    - Output: chat. If `datarim/qa/qa-report-{task-id}.md` was written, append the same section at the end of that file under `## Plain-language summary`.
    - Length budget: 150–400 words **total across the four sub-sections** (not per sub-section). Hard upper bound.

---

## Layer 1: PRD Alignment

**Condition:** Execute only if `datarim/prd/*.md` exists.

**Checks:**
- Read all PRD files for the current task
- Compare each stated requirement against the implementation
- Flag any **missing features** (in PRD but not implemented)
- Flag any **scope creep** (implemented but not in PRD)
- Verify all acceptance criteria from the PRD are satisfied

**Verdict:** PASS | PASS_WITH_NOTES | FAIL

```markdown
### Layer 1: PRD Alignment — {VERDICT}

**PRD files reviewed:** {list}

| Requirement | Status | Notes |
|------------|--------|-------|
| R1: {desc} | Implemented / Missing / Partial | {detail} |

**Missing features:** {list or "None"}
**Scope creep:** {list or "None"}
```

---

## Layer 2: Design Conformance

**Condition:** Execute only if `datarim/creative/*.md` exists.

**Checks:**
- Read all creative/design documents for the current task
- Verify architectural decisions (ADRs) are respected in code
- Check that chosen patterns (from design phase) are actually used
- Flag any **deviations** from the approved design
- If deviations exist, assess whether they are improvements or regressions

**Verdict:** PASS | PASS_WITH_NOTES | FAIL

```markdown
### Layer 2: Design Conformance — {VERDICT}

**Design docs reviewed:** {list}

| Decision | Status | Notes |
|----------|--------|-------|
| ADR-001: {desc} | Followed / Deviated / N/A | {detail} |

**Deviations:** {list with assessment or "None"}
```

---

## Layer 3: Plan Completeness

**Condition:** Execute only if `datarim/tasks.md` contains implementation steps for the current task.

**Checks:**
- Read the implementation plan from `datarim/tasks.md`
- Verify each planned step was completed
- Flag any **skipped steps** with reason assessment
- Flag any **unplanned steps** that were added during implementation
- Check that step ordering was respected (dependencies honored)

**Verdict:** PASS | PASS_WITH_NOTES | FAIL

```markdown
### Layer 3: Plan Completeness — {VERDICT}

| Step | Status | Notes |
|------|--------|-------|
| 1. {desc} | Done / Skipped / Modified | {detail} |

**Skipped steps:** {list with risk assessment or "None"}
**Unplanned additions:** {list or "None"}
```

---

## Layer 3b: Expectations Verification

**Condition:** Execute when `datarim/tasks/{TASK-ID}-expectations.md` exists (mandatory for L3-L4 tasks per `$HOME/.claude/skills/expectations-checklist/SKILL.md`; optional for L1-L2 within the 30-day soft window).

**Checks:**

- Read the file. For each item under `## Ожидания`:
  - read `wish_id`, `Что хочу проверить`, `Как проверить (success criterion)`, `evidence_type` (v2 schema, required: `empirical | static | measurement`), current `#### Текущий статус`, and any existing `override:` line;
  - run the success criterion against the implementation and decide one of `met` / `partial` / `missed` / `n-a`;
  - append one line to that item's `#### История статусов` with the canonical format `<ISO> / <local> · /dr-qa · <prior> → <new> · reason: <one-sentence plain ru>`;
  - update the item's `#### Текущий статус` to the new value;
  - **(Per-wish report contract, mandatory for schema_version=2)** write a detailed per-wish block to `datarim/qa/qa-report-{TASK-ID}.md` per the **Per-Wish Detailed Block Template** below. The block records what was tested + what command was run + what was measured, so the operator can audit «как реализована эта задача, какие тесты + замеры были проведены, какой получен результат» without re-running QA. Evidence_type rules:
    - `empirical` — block MUST contain a runtime command invocation <!-- gate:example-only -->(curl, bats, pytest, docker exec, sample-tool execution)<!-- /gate:example-only --> + actual stdout/stderr/exit code. Static grep alone does NOT satisfy `empirical`.
    - `measurement` — block MUST contain a numeric value + comparison to expected (e.g. «latency p95 = 87ms < budget 100ms»). Plain prose alone does NOT satisfy `measurement`.
    - `static` — block MAY contain only `grep` / `test -f` / `wc -l` / file-presence checks. Validator emits an advisory warning if ALL wishes in a task are `static` (per `dev-tools/check-expectations-checklist.sh --all`).
    - Legacy `schema_version=1` items: write the block on best-effort basis (no evidence_type rule enforcement); validator deprecation warning surfaces the migration prompt.
- After all items are updated, invoke the routing validator:
  ```bash
  dev-tools/check-expectations-checklist.sh --verify {TASK-ID}
  ```
  - Exit 0 + stdout marker `PASS` ⇒ Layer 3b verdict **PASS**;
  - Exit 0 + stdout marker `CONDITIONAL_PASS` ⇒ Layer 3b verdict **PASS_WITH_NOTES** (every partial/missed item carries an operator override ≥10 chars);
  - Exit 1 + stdout marker `BLOCKED` ⇒ Layer 3b verdict **FAIL**. Capture the validator's `Focus items:` and `Next step:` lines verbatim into the QA report.

**Verdict:** PASS | PASS_WITH_NOTES | FAIL

```markdown
### Layer 3b: Expectations Verification — {VERDICT}

**Items verified:** {N}
**Status transitions written:** {N} (one История статусов line per item)

| # | wish_id | Текущий статус | Override present? | Notes |
|---|---------|----------------|-------------------|-------|
| 1 | {slug}  | met            | n/a               | — |
| 2 | {slug}  | partial        | yes (≥10 chars)   | conditional pass |
| 3 | {slug}  | missed         | no                | BLOCKED |

**Validator verdict:** {PASS | CONDITIONAL_PASS | BLOCKED}
**Focus items (if BLOCKED):** {comma-separated wish_ids}
**Next step (if BLOCKED):** `/dr-do {TASK-ID} --focus-items <wish_ids>`
```

### Per-Wish Detailed Block Template (schema_version=2)

For every wish item in `## Ожидания`, append one block to the QA report under a top-level `## Layer 3b — Per-Wish Detailed Report` section. The order of blocks matches the order of items in `expectations.md`.

```markdown
#### Wish {N} — {wish_id}: {title verbatim from expectations.md}

**Evidence type:** {empirical | static | measurement}

**Что было сделано для проверки:**
{Одно-два предложения plain ru: какой test/probe/measurement выполнен, против какого артефакта/окружения, на каком SHA / commit / environment snapshot.}

**Команда + результат:**
```
$ {actual command — exact invocation, copy-pasteable}
{stdout/stderr — abbreviated к first/last 10 lines если длиннее; full output в run.log если применимо;
 для measurement — numeric value на отдельной строке;
 для static — grep output / file existence check;
 для empirical — runtime тест invocation output + exit code}
Exit code: {N}
```

**Verdict:** {met | partial | missed | n-a} — {one-sentence reason citing the measured value vs expected; для measurement — формат «X = {value} {comparison-op} {expected}», e.g. «latency p95 = 87ms < budget 100ms»; для static — «{file-path}:{line} contains {token}»; для empirical — «exit 0 + stdout contains «{marker}»»}.
```

**Rationale (operator goal per the original wish-list brief):** «по каждому пункту отчёт о том что было сделано для тестирования и какой получен результат». Каждый wish получает отдельный отчётный блок — 1-к-1 mapping operator-goal → per-goal evidence. Без этого блока Layer 3b verdict снижается до **PASS_WITH_NOTES** с finding `per-wish-block-missing: <wish_id>`.

**Evidence-type contract enforcement (advisory at Layer 3b, hard gate at /dr-compliance):**

- `empirical` без runtime command → finding `evidence-type-mismatch: <wish_id> declared empirical but block contains only grep`.
- `measurement` без numeric value → finding `evidence-type-mismatch: <wish_id> declared measurement but block lacks numeric value`.
- `static` accepted as-is (lowest tier).

Findings at Layer 3b are advisory (PASS_WITH_NOTES); `/dr-compliance` may upgrade to BLOCKED if the operator brief explicitly required practical measurements (per task `expectations.md` § evidence_type distribution).

A FAIL at Layer 3b makes the overall verdict **BLOCKED** regardless of other layers; the FAIL-Routing CTA (see § Verdict Logic) MUST surface the focus-items line verbatim. The classical Layer 1–4 verdicts are computed independently; Layer 3b is an additional gate that runs in parallel.

### Q&A round-trip verification (additional sub-check)

When `datarim/tasks/{TASK-ID}-init-task.md § Append-log` contains one or more `### <ISO> — Q&A by /dr-<stage> (round N)` blocks (contract: `$HOME/.claude/skills/init-task-persistence/SKILL.md` § Q&A round-trip contract), Layer 3b extends its verification with two additional checks. The Q&A pass runs after the per-item expectation walk above and is gated on the same Layer 3b verdict ladder.

1. **Agent-decision implementation grep.** For every block whose `**Decided by:** agent` line is present, extract the `Summary` text and grep the implementation surface (changed files for this task, the task description, the archive draft if any) for the salient token(s) of the summary. The decision is **reflected** when a textual or semantic match exists in the implementation artefacts; **not reflected** otherwise. Findings format: `Q&A round-trip: agent-decision <round-N> not reflected in implementation`.
2. **Conflict closure verification.** For every block carrying `**Conflict with existing wish:** <wish_id> — …` (non-`none`), the Append-log MUST also contain a closure entry — either an operator amendment (`amendment by …`) or a later Q&A round on the same `wish_id` that resolves the contradiction. An **unclosed Conflict** raises Layer 3b verdict **BLOCKED**; finding format: `Q&A round-trip: unclosed Conflict on <wish_id> — operator returns task via /dr-do --focus-items <wish_id>`.

Both checks are **fail-soft when no Q&A blocks exist** (legacy tasks). Both contribute to the same Layer 3b verdict — an unreflected agent-decision raises **FAIL** (operator can override via amendment); an unclosed Conflict raises **BLOCKED** without override.

The Q&A round-trip findings appear in the same Layer 3b table under a dedicated row group:

```markdown
**Q&A round-trip rounds verified:** {N}
**Agent-decisions reflected:** {N_ok} / {N_total}
**Unclosed Conflict findings:** {list of wish_ids}  (BLOCKED if non-empty)
```

---

## Layer 4: Code Quality

**Condition:** Always executed.

**Checks:**

### 4a. Tests
- Run the project test suite (detect runner from `package.json`, `Makefile`, `Cargo.toml`, etc.)
- Report: total tests, passed, failed, skipped
- If tests fail, list failures with file and line

### 4b. Security
- Apply checks from `$HOME/.claude/skills/security/SKILL.md`
- Scan for hardcoded secrets, exposed endpoints, missing input validation
- Check dependency vulnerabilities if lockfile exists (use the project's package-manager-native audit command at the declared severity threshold)

### 4c. Anti-Patterns
- Methods exceeding 50 lines
- Functions with more than 7 parameters
- Duplicated code blocks
- Missing error handling on async operations
- Console.log / print statements left in production code

### 4d. Live Smoke-Test Gate (raw SQL / cross-DB / cross-instance)
- If the changed code uses `$queryRaw`, `raw()`, `sequelize.query()`, or any path that bypasses the ORM type-checker — a **live smoke test** against the actual target datasource is **mandatory**. Mocked/unit tests do not satisfy this gate (see `$HOME/.claude/skills/testing/SKILL.md` § Live Smoke-Test Gate).
- In multi-datasource projects (e.g. aio-v2: `PrismaService` → `stats` mysql5 vs `PrismaBiService` → `bi_aggregate` mysql8), verify the correct client is injected for the target table. A wrong-client `$queryRaw` compiles clean and fails at runtime.
- **Record in QA report:** the exact smoke-test command, the datasource hit, and the result (row count / expected empty / error). No smoke test ⇒ Layer 4 verdict is **FAIL**, not PASS_WITH_NOTES.

### 4e. Definition of Done
- Read DoD from `datarim/tasks.md` or `datarim/prd/*.md`
- Check each criterion

### 4f. Browser-based Frontend QA (Playwright pass)

**Condition:** Execute only when the changed-files set for the task contains frontend markup per `$HOME/.claude/skills/playwright-qa/SKILL.md` § Frontend touch detection. Skip silently otherwise.

**Steps:**

1.  Read the init-task frontmatter for `qa_browser_mode` (`headed` | `headed-strict` | `skip`); honour the CLI flags `--headed` / `--headed-strict` if present in the operator invocation.
2.  Acquire the per-task lock at `datarim/qa/playwright-{TASK-ID}/.lock` (`flock --timeout 30`, fallback to atomic `mkdir`). Lock-timeout ⇒ finding `playwright-lock-timeout`, continue without the pass.
3.  Resolve the tool:
    ```bash
    dev-tools/detect-playwright-tooling.sh [--headed | --headed-strict] --json
    ```
    Parse `tool` / `headed` / `display` / optional `finding` from the JSON line. Exit code 2 ⇒ FAIL (strict headed without display); exit code 1 ⇒ should not occur here (no `--require`); exit code 0 with `tool: none` ⇒ finding `playwright-tooling-missing`, skip the pass.
4.  Create the per-run directory `datarim/qa/playwright-{TASK-ID}/run-$(date -u +%Y%m%dT%H%M%SZ)/`.
5.  Invoke the resolved tool against the project's local dev surface (default) or a static fixture identified in the init-task. Capture `screenshot.png` + `trace.zip` (CLI/MCP only) + combined stdout/stderr to `run.log`.
6.  Write `summary.md` per the shape defined in `$HOME/.claude/skills/playwright-qa/SKILL.md` § Artifact layout (tool / headed mode / display / target URL / viewport / exit code / findings list).
7.  Update the `latest` symlink (copy-fallback on filesystems without symlink support).
8.  Release the lock.

**Record in QA report:** add a line under Layer 4 with `Playwright pass:` followed by the resolved tool, headed mode, exit code, and path to the `run-<ts>/` directory. List any findings (`playwright-tooling-missing`, `playwright-lock-timeout`, `headed-requested-but-no-display`, `headed-strict-no-display`) under § Layer 4 / 4f.

**Verdict contribution:**

- `tool: none` ⇒ finding only, no verdict change.
- `--headed-strict` + no display ⇒ Layer 4 = FAIL.
- Browser invocation non-zero exit ⇒ Layer 4 = FAIL.
- Otherwise ⇒ Layer 4 contribution = PASS (the pass succeeded; visual review is the operator's responsibility).

**Verdict:** PASS | PASS_WITH_NOTES | FAIL

```markdown
### Layer 4: Code Quality — {VERDICT}

**Tests:** {X passed, Y failed, Z skipped}
**Security issues:** {count — list if any}
**Anti-patterns:** {count — list if any}
**Playwright pass:** {SKIPPED (no frontend touch) | tool=<t>, headed=<m>, exit=<n>, dir=<path> | FAIL (<reason>)}

| DoD Criterion | Status |
|--------------|--------|
| {criterion} | Met / Not met |
```

---

## QA Report Template

Write to `datarim/qa/qa-report-{task-id}.md`:

```markdown
# QA Report — {TASK-ID}

**Date:** {YYYY-MM-DD}
**Reviewer:** Reviewer Agent
**Overall Verdict:** {ALL_PASS | CONDITIONAL_PASS | BLOCKED}

---

{Layer 1 section — or "Layer 1: PRD Alignment — SKIPPED (no PRD artifacts)"}

---

{Layer 2 section — or "Layer 2: Design Conformance — SKIPPED (no design artifacts)"}

---

{Layer 3 section — or "Layer 3: Plan Completeness — SKIPPED (no implementation plan)"}

---

{Layer 3b section — or "Layer 3b: Expectations Verification — SKIPPED (no expectations checklist)"}

---

{Layer 4 section}

---

## Summary

**Layers executed:** {N of 4}
**Results:** {list of layer verdicts}

## /dr-auto Mode (when `DATARIM_AUTO_MODE=1`)

When auto-mode is active (env var `DATARIM_AUTO_MODE=1` AND matching marker `datarim/.auto-mode-active` containing this TASK-ID), this command:

1. Consults `${DATARIM_RUNTIME:-$HOME/.claude}/skills/autonomous-mode/SKILL.md` § Question Suppression Ladder before any `AskUserQuestion` or equivalent operator prompt at this stage.
2. Stage-specific suppression hooks:
   - Stage failure routing (back to /dr-do vs proceed with caveats) — resolved through Ladder L2 (re-run test, runtime probe) before L5 escalation.
   - V-AC ambiguity (partial pass vs full pass) — strict ambiguity rule applies: ≥2 plausible verdicts → L5.
3. Discovered gaps → apply L1 Inline Resolution Rule per `skills/autonomous-mode/SKILL.md`; log in `datarim/tasks/{TASK-ID}-auto-inline-log.md` if applied inline.
4. Hard-gated actions → escalate to operator through Ladder L5; log via `dev-tools/append-init-task-qa.sh --decided-by operator` per `skills/init-task-persistence/SKILL.md` § Q&A round-trip.
5. Mismatch (env var set, marker absent OR marker contains different TASK-ID) → emit single-line warning, treat as non-auto (fail-safe per `skills/autonomous-mode/SKILL.md` § When this skill is active).

## Next Steps

{Based on overall verdict — see routing below}
```

---

## Verdict Logic

### Per-Layer Verdicts

| Verdict | Meaning |
|---------|---------|
| **PASS** | All checks satisfied, no issues |
| **PASS_WITH_NOTES** | All checks satisfied, minor observations that don't block |
| **FAIL** | One or more checks failed, must be addressed |

### Overall Verdict

| Overall | Condition | Next Step |
|---------|-----------|-----------|
| **ALL_PASS** | Every executed layer is PASS | L3-4 → `/dr-compliance`; L1-2 → `/dr-archive` |
| **CONDITIONAL_PASS** | All layers PASS or PASS_WITH_NOTES, no FAIL | L3-4 → `/dr-compliance`; L1-2 → `/dr-archive` (notes documented) |
| **BLOCKED** | One or more layers FAIL | Route by earliest failed layer (see FAIL Routing below) |

---

## Next Steps (CTA)

After verdict, the reviewer agent MUST emit a CTA block per `$HOME/.claude/skills/cta-format/SKILL.md`. BLOCKED verdicts MUST use the FAIL-Routing variant.

**Routing logic for `/dr-qa`:**

- ALL_PASS or CONDITIONAL_PASS at L3-4 → primary `/dr-compliance {TASK-ID}` (final hardening)
- ALL_PASS or CONDITIONAL_PASS at L1-2 → primary `/dr-archive {TASK-ID}` (notes documented if any)
- **BLOCKED** — FAIL-Routing variant per Layer-to-command map:

| Failed Layer | Return Command (primary in CTA) | Rationale |
|--------------|---------------------------------|-----------|
| Layer 1 (PRD Alignment) | `/dr-prd {TASK-ID}` | Requirements incomplete or wrong — update PRD first |
| Layer 2 (Design Conformance) | `/dr-design {TASK-ID}` | Architecture decisions violated — revise design |
| Layer 3 (Plan Completeness) | `/dr-plan {TASK-ID}` | Steps skipped or plan outdated — update plan |
| Layer 3b (Expectations) | `/dr-do {TASK-ID} --focus-items <wish_ids>` | Operator expectations missed/partial without override — return to implementation focused on the listed `wish_id`s |
| Layer 4 (Code Quality) | `/dr-do {TASK-ID}` | Code bugs, security, anti-patterns — fix code |

Multi-layer FAIL: route to **earliest** failed layer (Layer 1 > 2 > 3 > 3b > 4). Earlier failures are root causes. Layer 3b sits between plan completeness and code quality because operator-expectation misses indicate scope-drift; they are higher-level than code defects but presuppose the plan was executed.

The FAIL-Routing CTA header MUST read: `**QA failed для {TASK-ID} — earliest failed layer: Layer N (Layer name)**`. Variant B menu when >1 active tasks.

## Loop Guard

If the same layer fails **3 times** on the same task, escalate to the user with a summary of all three failures. Options:
- (a) Force-pass with documented waiver (recorded in QA report)
- (b) Reduce task scope
- (c) Cancel the task

## Re-entry After FAIL Fix

After returning to an earlier stage and correcting the issue:
- **Resume forward** through remaining pipeline stages
- **QA must be re-run** — previous pass is invalidated by the correction
- Previous QA report kept for audit trail; new report gets `-v2`, `-v3` suffix

## Transition Checkpoint

Before proceeding to next stage:
```
[ ] All applicable layers executed?
[ ] DoD criteria verified against implementation?
[ ] Security issues addressed (or documented as accepted risk)?
[ ] QA report written to datarim/qa/?
```

## Stage Snapshot Emission (Mandatory Terminal Step)

After the `## Next Steps (CTA)` block above, the agent MUST perform snapshot emission per `$HOME/.claude/skills/cta-format/SKILL.md` § Snapshot Emission. Parameters bound for this command:

- `stage`: `qa`
- `command`: `/dr-qa`
- `captured-by`: `agent`
- `recommended-next`: primary CTA option (slash-prefixed `/dr-*` form)

Fail-closed: on non-zero writer exit, emit a single stderr warning line and continue (V-AC-7 contract). Kill switch `DATARIM_DISABLE_SNAPSHOT=1` is handled inside the library; under the switch the writer is a no-op without warning.
