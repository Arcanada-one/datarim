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
6.5. **APPEND Q&A IF ANY** (mandatory per `$HOME/.claude/skills/init-task-persistence/SKILL.md` § Q&A round-trip contract): for every operator clarification round captured during the review — either operator answer or autonomous agent-decision under FB-1..FB-5 — invoke `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh"` to persist the round into `datarim/tasks/{TASK-ID}-init-task.md § Append-log` before emitting the QA report.
    -   Write the question, answer, and rationale (when applicable) to temp files first; free-form text MUST come via `--*-file <path>` per Security Mandate § S1.
    -   Required flags: `--root <repo-root> --task {TASK-ID} --stage qa --round <N> --question-file <path> --answer-file <path> --decided-by <operator|agent> --summary "<one-line>"`.
    -   When `--decided-by agent`: `--rationale-file <path>` MUST contain ≥ 50 non-whitespace characters of best-practice rationale. Layer 3b will verify each agent-decision against the implementation.
    -   On contradiction with an expectation: add `--conflict-with <wish_id>` (+ optional `--conflict-detail-file`); CTA MUST route back to `/dr-do --focus-items <wish_id>` for closure.
    -   Skip if no clarification rounds occurred.
7.  **OUTPUT**: Write `datarim/qa/qa-report-{task-id}.md` with results.
8.  **HUMAN SUMMARY**:
    - Load `$HOME/.claude/skills/human-summary/SKILL.md`.
    - Emit the `## Отчёт оператору` (RU) / `## Operator summary` (EN) section, with the four mandated sub-sections, between the QA-report write and the CTA block ([definition](../skills/cta-format/SKILL.md)). Language follows the most recent operator message. <!-- allow-non-ascii: literal-russian-section-name-token-from-human-summary-skill -->
    - Source material: § Overview of the task description, per-layer verdicts, expectations checklist statuses (if Layer 3b ran), and the overall verdict.
    - Runs on every overall verdict (ALL_PASS, CONDITIONAL_PASS, BLOCKED). On BLOCKED the «Что не получилось» sub-section carries the failure detail in plain language and «Что дальше» paraphrases the FAIL-Routing target layer name (without command syntax — the CTA below carries that verbatim). <!-- allow-non-ascii: literal-russian-section-name-token-from-human-summary-skill -->
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

- Read the file. For each item under `## Ожидания`: <!-- allow-non-ascii: literal-russian-section-name-tokens-from-expectations-template -->
  - read `wish_id`, `Что хочу проверить`, `Как проверить (success criterion)`, `evidence_type` (v2 schema, required: `empirical | static | measurement`), current `#### Текущий статус`, and any existing `override:` line; <!-- allow-non-ascii: literal-russian-field-name-tokens-from-expectations-template -->
  - run the success criterion against the implementation and decide one of `met` / `partial` / `missed` / `n-a`;
  - append one line to that item's `#### История статусов` with the canonical format `<ISO> / <local> · /dr-qa · <prior> → <new> · reason: <one-sentence plain ru>`; <!-- allow-non-ascii: literal-russian-field-name-tokens-from-expectations-template -->
  - update the item's `#### Текущий статус` to the new value; <!-- allow-non-ascii: literal-russian-field-name-tokens-from-expectations-template -->
  - **(Per-wish report contract, mandatory for schema_version=2)** write a detailed per-wish block to `datarim/qa/qa-report-{TASK-ID}.md` per the **Per-Wish Detailed Block Template** below. The block records what was tested + what command was run + what was measured, so the operator can audit «как реализована эта задача, какие тесты + замеры были проведены, какой получен результат» without re-running QA. Evidence_type rules: <!-- allow-non-ascii: literal-russian-field-name-tokens-from-expectations-template -->
    - `empirical` — block MUST contain a runtime command invocation <!-- gate:example-only -->(curl, bats, pytest, docker exec, sample-tool execution)<!-- /gate:example-only --> + actual stdout/stderr/exit code. Static grep alone does NOT satisfy `empirical`.
    - `measurement` — block MUST contain a numeric value + comparison to expected (e.g. «latency p95 = 87ms < budget 100ms»). Plain prose alone does NOT satisfy `measurement`.
    - `static` — block MAY contain only `grep` / `test -f` / `wc -l` / file-presence checks. Validator emits an advisory warning if ALL wishes in a task are `static` (per `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-expectations-checklist.sh" --all`).
    - Legacy `schema_version=1` items: write the block on best-effort basis (no evidence_type rule enforcement); validator deprecation warning surfaces the migration prompt.
- After all items are updated, invoke the routing validator:
  ```bash
  "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-expectations-checklist.sh" --verify {TASK-ID}
  ```
  - Exit 0 + stdout marker `PASS` ⇒ Layer 3b verdict **PASS**;
  - Exit 0 + stdout marker `CONDITIONAL_PASS` ⇒ Layer 3b verdict **PASS_WITH_NOTES** (every partial/missed item carries an operator override ≥10 chars);
  - Exit 1 + stdout marker `BLOCKED` ⇒ Layer 3b verdict **FAIL**. Capture the validator's `Focus items:` and `Next step:` lines verbatim into the QA report.

- **Anti-deferral prose scan (ADVISORY at QA).** After the routing validator, scan the QA report just written for self-deferral language — the failure mode where the agent labels its own incomplete work "out of scope / informational / not a blocker / will fix later" instead of finishing it:
  ```bash
  "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-deferral-prose.sh" \
      --file datarim/qa/qa-report-{TASK-ID}.md --task {TASK-ID} --root <repo-root>
  ```
  - Exit 0 ⇒ no self-inflicted deferral; no action.
  - Exit 1 ⇒ deferral on a touched file without a verifiable follow-up/blocked_by artefact. At QA this is **advisory**: keep the Layer 3b verdict at most **PASS_WITH_NOTES**, record the findings in the QA report, and warn the operator that `/dr-compliance` will treat the same finding as a hard block. (This mirrors the evidence-type advisory-at-QA / hard-at-compliance escalation.) The scanner is fail-open: a git-probe failure warns and passes, never false-blocks.

**Verdict:** PASS | PASS_WITH_NOTES | FAIL

```markdown
### Layer 3b: Expectations Verification — {VERDICT}

**Items verified:** {N}
**Status transitions written:** {N} (one История статусов line per item) <!-- allow-non-ascii: literal-russian-field-name-tokens-from-expectations-template -->

| # | wish_id | Текущий статус | Override present? | Notes | <!-- allow-non-ascii: literal-russian-field-name-tokens-from-expectations-template -->
|---|---------|----------------|-------------------|-------|
| 1 | {slug}  | met            | n/a               | — |
| 2 | {slug}  | partial        | yes (≥10 chars)   | conditional pass |
| 3 | {slug}  | missed         | no                | BLOCKED |

**Validator verdict:** {PASS | CONDITIONAL_PASS | BLOCKED}
**Focus items (if BLOCKED):** {comma-separated wish_ids}
**Next step (if BLOCKED):** `/dr-do {TASK-ID} --focus-items <wish_ids>`
```

### Per-Wish Detailed Block Template (schema_version=2)

For every wish item in `## Ожидания`, append one block to the QA report under a top-level `## Layer 3b — Per-Wish Detailed Report` section. The order of blocks matches the order of items in `expectations.md`. <!-- allow-non-ascii: literal-russian-section-name-token-from-expectations-template -->

<!-- allow-non-ascii-block: russian-per-wish-qa-template-fixture-required-by-contract -->
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
<!-- /allow-non-ascii-block -->

**Evidence-type contract enforcement (advisory at Layer 3b, hard gate at /dr-compliance):**

- `empirical` без runtime command → finding `evidence-type-mismatch: <wish_id> declared empirical but block contains only grep`. <!-- allow-non-ascii: literal-russian-mixed-prose-with-evidence-type-mismatch-finding-token -->
- `measurement` без numeric value → finding `evidence-type-mismatch: <wish_id> declared measurement but block lacks numeric value`. <!-- allow-non-ascii: literal-russian-mixed-prose-with-evidence-type-mismatch-finding-token -->
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

## Layer 3c: Automatic Spec-Graph Verification

Invoke:

```bash
"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/spec-graph-gate.sh" \
    --task {TASK-ID} --stage qa --root <repo-root> --format json
```

- Include graph findings, evaluated artifacts, and the five `dr-trace` coverage buckets in `datarim/qa/qa-report-{TASK-ID}.md`.
- L1 skips; L2 is advisory. L3-L4 is advisory by default and hard only when `DATARIM_SPEC_GRAPH_MODE=hard`.
- Exit `2` is a QA **BLOCKED** configuration/required-artifact failure. Hard-mode exit `1` is a Layer 3c **FAIL** routed to `/dr-prd` or `/dr-plan` according to the earliest missing edge.

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

### 4d-bis. Agentic Entrypoint Wiring + Live-Run Gate

**Condition:** the task ships a service/daemon/cron/agent whose declared purpose is to invoke an external CLI/LLM/subprocess (e.g. `claude -p`, `gh`, `aws`) and act on its output. Apply per `$HOME/.claude/skills/testing/live-smoke-gates.md` § Gate 7.

- **Entrypoint-reachability (both ways):** prove the *real* entrypoint (`__main__` / systemd `ExecStart` / cron command / queue consumer) actually calls the declared function — static call-graph grep (entrypoint imports AND invokes the orchestrator/lane, not merely that it exists) **and** a runtime probe showing the function was entered. An orchestrator/lane reachable only from tests is **dead code in prod**: the wish is **missed**, Layer 4 = **FAIL** → `/dr-do`.
- **One live tool-run:** run the agent **once for real** with the feature enabled and the tool present, against realistic input; capture the real tool's stdout/exit + the resulting side-effect (audit record / notification / MR / file change). Pair with the Auth Probe and PATH check (the tool must be on the *service's* PATH, not just the login shell's).
- **Record in QA report:** the exact run command, tool version, captured real output, and the observed side-effect. A mock assertion does NOT satisfy this. An `evidence_type: empirical` wish marked **met** on mocks alone (no live tool-run) is a Layer 3b/4 finding ⇒ **FAIL** — never PASS_WITH_NOTES. A kill-switch-OFF exit-0 probe proves the agent does *nothing*; it does not satisfy this gate.

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
    "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/detect-playwright-tooling.sh" [--headed | --headed-strict] --json
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

### 4g. Prod-Readiness Gate (deploy-class tasks — blocking before merge)

**Condition:** Execute only when the task is **deploy-class**, i.e.
`bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-deploy-class.sh" --task-description datarim/tasks/{TASK-ID}-task-description.md`
exits 0 (the task touches a deploy surface — systemd units, sudoers, CI cutover,
`.env-deploy`). On exit 1 the gate verdict is **SKIP** and this layer is a no-op.

**Why this gate exists:** a deploy/cutover change can pass every test on the
test runner and still fail on the first production command because the prod
runner is not symmetric (the classic case: prod sudoers lacks the NOPASSWD rules
the test runner already has). This gate forces verification of test↔prod runner
symmetry **before the pipeline may propose merge** — the framework must not
recommend merging an unverified cutover.

**Steps:**

1.  Load `$HOME/.claude/skills/prod-readiness-probe/SKILL.md` and run the probe
    in read-only mode against the test and prod runners.
2.  **Hybrid:** if the project authored `datarim/deploy-readiness.yml` (validate
    with `dev-tools/check-deploy-readiness.sh --validate-yaml`), run the
    deterministic three-way comparison (test actual vs prod actual vs declared);
    otherwise fall back to the skill's agent-checklist investigation.
3.  Verify: sudoers symmetry, PATH parity, listening ports, systemd units,
    runtime version floors.
4.  **prod is hard-gated** — the probe is read-only (`sudo -l`,
    `systemctl status`, `ss`, `redis-cli info server`, `node --version`); it
    performs NO writes. A required prod mutation is **predicted and reported**,
    never executed by the framework — remediation is an explicit operator action.

**Verdict → action:**

- `SKIP` / `PASS` ⇒ Layer 4g contribution = PASS; the pipeline **MAY propose merge**.
- `FAIL` (asymmetry found) ⇒ Layer 4g = **FAIL**; the pipeline **MUST NOT propose merge** until resolved. Overall QA verdict is **BLOCKED**.
- `BLOCKED` (probe could not run, e.g. prod unreachable, and no operator confirmation) ⇒ Layer 4g = **FAIL**; **MUST NOT propose merge**. `BLOCKED` never auto-resolves to PASS — the operator must confirm out-of-band verification.

**Record in QA report:** the verdict, the runner pair probed, the exact
read-only commands run, captured output, and — on FAIL — the asymmetry plus the
predicted production impact and the operator remediation required.

**Verdict:** SKIP | PASS | FAIL

### 4h. Test-Environment Verification Gate (behaviour-shipping tasks — blocking before prod prep / archive)

**Condition:** Execute when the task ships runtime behaviour (code/config/migration —
not docs-only or framework-only) AND the project space has a test environment, per
`$HOME/.claude/skills/test-env-verification/SKILL.md` § When this skill is active.
Resolution chain: space registry `spaces/<space>/space.yml` → `test_environments[]`
(authoritative) → CI `deploy:test` heuristic (fallback) → else `NO-TEST-ENV`.

**Why this gate exists:** a change can pass every component/unit/Playwright test in
an isolated worktree and still have never run on a real deployed environment.
Operator mandate: when a test environment exists, the change MUST be
verified on it — **backend AND frontend** — **autonomously**, before the task is
prepared for prod or archived. Do not ask the operator each task whether to test;
this skill pre-resolves that decision to "yes".

**Steps (autonomous):**

1.  Load `$HOME/.claude/skills/test-env-verification/SKILL.md`.
2.  Resolve the test environment(s) + record the source that resolved them.
3.  Ship the change to the test env via the project's `deploy:test` CI (integrate
    onto the triggering branch — cherry-pick-onto-`dev` when the feature was cut
    from `main` and `dev` ≫ `main`; never a blind feature→dev merge). Poll CI until
    `deploy:test` is green.
4.  Exercise **backend** (health + ≥1 behaviour-bearing call on the changed path;
    safe-mode / `dry_run` when the env can mutate real external systems — never a
    billable/destructive external action on test without operator sign-off).
5.  Exercise **frontend** (load the affected flow on the deployed test build; if the
    test env disables the agent's auth path, record the limitation and fall back to
    the deployed-bundle check + the Layer 4f component/live-render Playwright — do
    NOT silently skip the frontend).
6.  **Record in QA report** under `### Layer 4h — Test-Environment Verification`: the
    resolved env + source, CI deploy pipeline + job result, exact backend/frontend
    commands, captured output, per-surface verdict.

**Verdict → action:**

- `PASS` / `PASS_WITH_NOTES` ⇒ Layer 4h contribution = PASS; the pipeline MAY propose prod prep / archive.
- `SKIP` (docs/framework-only) / `NO-TEST-ENV` (none registered or discoverable) ⇒ no-op; recorded verbatim (NO-TEST-ENV is NOT a verification pass).
- `FAIL` (not shipped to test, or exercised and broken) ⇒ Layer 4h = **FAIL**; the pipeline **MUST NOT propose prod prep / archive**. Overall QA verdict is **BLOCKED**; route to `/dr-do` (broken) or back to the deploy step (not shipped).

**Verdict:** PASS | PASS_WITH_NOTES | SKIP | NO-TEST-ENV | FAIL

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
4. Hard-gated actions → escalate to operator through Ladder L5; log via `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh" --decided-by operator` per `skills/init-task-persistence/SKILL.md` § Q&A round-trip.
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

The FAIL-Routing CTA header MUST read: `**QA failed для {TASK-ID} — earliest failed layer: Layer N (Layer name)**`. Variant B menu when >1 active tasks. <!-- allow-non-ascii: literal-russian-fail-routing-cta-header-template-token -->

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

After the `## Next Steps (CTA)` block above, the agent MUST perform snapshot emission ([definition](../skills/stage-snapshot-writer/SKILL.md)) per `$HOME/.claude/skills/cta-format/SKILL.md` § Snapshot Emission. Parameters bound for this command:

- `stage`: `qa`
- `command`: `/dr-qa`
- `captured-by`: `agent`
- `recommended-next`: primary CTA option (slash-prefixed `/dr-*` form)

Fail-closed: on non-zero writer exit, emit a single stderr warning line and continue (V-AC-7 contract). Kill switch `DATARIM_DISABLE_SNAPSHOT=1` is handled inside the library; under the switch the writer is a no-op without warning.
