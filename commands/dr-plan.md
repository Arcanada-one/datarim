---
description: Create detailed implementation plan (Phases 4-6, Appendix A Security).
globs:
  - datarim/tasks.md
  - datarim/activeContext.md
  - datarim/prd/*.md
---

# PLAN Command

This command generates a detailed implementation plan in `datarim/tasks.md`, strictly following the **Enhanced Design Process** (Phases 4-6).

## Instructions

0.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system.md` § Path Resolution Rule.

1.  **TASK RESOLUTION**: Apply Task Resolution Rule from `$HOME/.claude/skills/datarim-system.md` § Task Resolution Rule. Use the resolved task ID for all subsequent steps.

2.  **Analyze Context**:
    -   Read `datarim/tasks.md` (Complexity, Requirements for the resolved task).
    -   Read `datarim/activeContext.md` (Active Tasks list).
    -   Review `datarim/prd/*.md` if available.
    -   Read `datarim/insights/INSIGHTS-{task-id}.md` if exists (research context from `/dr-prd` Phase 1.3).

3.  **Strategist Gate** (mandatory for L3-4, optional for L2):
    -   Load `$HOME/.claude/agents/strategist.md`.
    -   Evaluate:
        -   **Value** — is this worth building?
        -   **Risk** — what's irreversible?
        -   **Cost** — what's the minimum viable experiment?
    -   If strategist recommends pivot or cheaper alternative, present to user before proceeding.

4.  **Detailed Design (Phase 4)**:
    -   **Component Breakdown**: List every modified and new file.
    -   **Interface Design**: Define function signatures, API contracts.
    -   **Data Flow**: Trace input -> processing -> output.
    -   **Security Design**: Perform **Threat Modeling** and map to **Security Controls** (Appendix A).

5.  **Create Implementation Plan (Phase 5)** — thin-index schema:
    -   **`datarim/tasks.md`** carries ONLY the one-liner pointer (canonical regex per `skills/datarim-system.md` § Operational File Schema):
        ```
        - {TASK-ID} · in_progress · P{n} · L{n} · {title} → tasks/{TASK-ID}-task-description.md
        ```
        Never write plan content directly into `tasks.md`.
    -   **L1-L2 tasks:** plan body lives in `datarim/tasks/{TASK-ID}-task-description.md` § Implementation Notes (or a dedicated `## Implementation Plan` section). Description file MUST have the 12-key YAML frontmatter (see `skills/datarim-system.md` § Description File Contract).
    -   **L3-L4 tasks:** plan body lives in `datarim/plans/{TASK-ID}-plan.md`. The description file's frontmatter sets `plan: plans/{TASK-ID}-plan.md`. The description body's `## Related` section points readers there.
    -   Both formats use the same **Design Document Template** (Phase 5 below).
    -   Include: **Security Summary** (Attack Surface, Risks), **Architecture Impact**, **Detailed Design** (API, DB, Config), **Security Design** (Threats, Controls), **Implementation Steps**, **Test Plan** (Unit/Integration/Security), **Rollback Strategy**, **Validation Checklist**.

6.  **Technology Validation**:
    -   Document technology stack selection.
    -   Verify dependencies and build configuration.

6.5.  **Symbol Existence Check (MANDATORY when the plan names a method, function, file, flag, env var, or CLI command as a fix target)**:
    -   For every named code surface in the plan (e.g. `module.foo`, `path/to/file.ext`, `--flag-name`, `$ENV_VAR`), grep the project to confirm it exists.
    -   The plan MUST cite the file:line where each named target lives. Phantom targets (named in the plan but absent from the code) are a planning defect — fix the plan or fix the code, then re-grep.
    -   If a target is intentionally to be created, the plan MUST say so explicitly and justify the new surface (one sentence: why does this need to exist?). Otherwise, redirect the fix to the actual surface that owns the behaviour.
    -   Apply to all references: not just function names, but also config keys, CLI sub-commands, file paths, env vars, and HTTP routes.
    -   Rationale: a 30-second grep at planning time prevents 10–30 minute investigations during `/dr-do`. A plan that names a method as the fix surface but the method does not exist (e.g. behaviour was implemented inline in a different module) requires in-flight redirect — a single grep at `/dr-plan` time would have caught it.

7.  **Installer / Deploy-Script Content-Type Audit (MANDATORY when plan touches install.sh, sync-script, or any deploy/copy tool)**:
    -   Grep the file-type filter (`case "*.md"`, `find ... -name`, extension whitelist, etc.) in the target script.
    -   List every supported extension explicitly in the plan's Technology Validation or Architecture Impact section.
    -   If the plan promotes/adds files with an extension the installer does NOT handle, either:
        - (a) Extend the installer filter in the same plan (add to scope), or
        - (b) Record the gap as an explicit known-limitation and open a follow-up backlog item to fix the installer.
    -   Rationale: an installer's file-type filter (e.g. `case "*.md"` at install.sh:NN) can silently exclude another extension referenced elsewhere in the plan — the gap is readable from line 1 but surfaces only at verification. Grepping the filter at planning time catches this class of asymmetry.

8.  **Research Kill-Criteria Checkpoint** (for comparative/research tasks):
    -   After research but BEFORE mechanical testing (smoke-install, Docker runs, benchmarks): evaluate whether research evidence alone eliminates candidates (deprecated, stale, wrong license, wrong category, hype).
    -   Candidates failing kill-criteria from research skip testing entirely — saves hours of Docker/install time.
    -   Rationale: research evidence has eliminated more than half of candidates in past comparative tasks (saving multi-hour Docker/install cycles) — apply kill-criteria from research before mechanical testing.

9.  **Planning Hygiene — Summary Counts from Source Table**:
    -   Any aggregate count in the plan (e.g. "total deferred", "files touched", "rows", "threats") MUST be derived from the authoritative source table (drift report, component breakdown, threat model) and the plan MUST cite that source inline.
    -   Freehand summary numbers are prohibited — they propagate into validation checklists and blur AC verification.
    -   Example: not `"12 deferred diffs"` but `"14 deferred diffs (from drift-{TASK-ID}.md: 8 skills + 2 agents + 4 commands)"`.

10.  **Fixture Capture for External Output (MANDATORY when the plan parses a CLI / subprocess / API response)**:
    -   When the task depends on an external tool's output format (CLI, subprocess, webhook, HTTP API, log stream), capture a **real** sample during `/dr-plan` and commit it to `datarim/tasks/{TASK-ID}-fixtures.md` with timestamp, tool version, command invoked, and all relevant output formats.
    -   Do NOT design a parser against the documented or inferred format alone when a live sample is reachable. Documentation drifts, versions vary, and the fastest path to a correct parser is a fixture you can paste into a test.
    -   Prefer the tool's machine-readable output (`--json`, `--output-format stream-json`, `--format porcelain`) over human-text; structural fields are stable, prose drifts. If the plan proposes regex-on-human-text while a machine format is available, stop and revisit.
    -   If a live failure window is already open (e.g. a production service in an error state), capture the fixture AND run the end-to-end smoke test in the same session — limit windows close fast and cannot be recreated on demand.
    -   Rationale: a plan that initially proposes regex parsing of human-readable timestamps (e.g. `"resets 5pm (UTC)"`) often misses a strictly-better machine-readable field (UNIX epoch, structural ID) available in the same response — locale/TZ fragility is the cost. A 30-min live capture during `/dr-plan` surfaces the structural alternative.
    -   **Known CLI agent pattern — exit code 0 on JSON errors:** Many CLI agents return exit code 0 even when the JSON output contains `is_error: true`. The error is encoded inside JSON, not signaled by the process exit code. When capturing fixtures, always capture both a success AND an error case to verify exit code behavior. Parsers must check `is_error`/`subtype` in JSON, not rely on exit codes.

11.  **Live Audit Checkpoint (MANDATORY when plan locks a runtime stack via lockfile-format manifest)**:
    -   For each lockable manifest the plan proposes, materialise a minimal stub in `/tmp/dr-plan-audit-{TASK-ID}/` containing only the runtime dependencies (skip dev/test/lint), pinned exactly as the plan locks them.
    -   Run the ecosystem audit gate using the same threshold the plan declares for CI. Use the project's package-manager-native audit command at the project's declared severity threshold.
    <!-- gate:example-only -->
    -   Concrete recipes (illustrative — substitute the project's actual package manager and threshold):
        -   Node ecosystem: `<package-manager> install --omit=dev && <package-manager> audit --omit=dev --audit-level=high`
        -   Python ecosystem: install runtime deps, then `pip-audit --strict`
        -   Rust ecosystem: `cargo audit --deny warnings`
    <!-- /gate:example-only -->
    -   **If the audit gate fails on the proposed lock**, before promoting the plan to `/dr-do`:
        -   (a) Bump version pins in the plan (and any cited PRD constraint) until the gate passes; OR
        -   (b) Open a backlog item describing the unfixable CVE chain and document it in the plan's Security Summary as an **explicit accepted risk** with sign-off line.
        -   Do NOT proceed to `/dr-do` with a plan that pre-fails the CI security gate it itself declares.
    -   Rationale: a plan can lock a runtime framework pin at PRD-time and declare a CI security gate at high-severity threshold, only to discover at `/dr-do` install-time that the gate fails on multiple high + critical CVEs in the locked stack (body-bypass, middleware path traversal, etc.). A 30-second audit-command run against the proposed lock at `/dr-plan` time surfaces this and triggers the version bump before code generation — saving ~1h of mid-implementation re-pinning, re-install, re-test cycles.

11.5.  **CI Verification Gate — Delta-vs-Baseline Framing (MANDATORY when plan declares a CI green-jobs gate as an acceptance criterion)**:
    -   Before drafting V-CI («all CI jobs green» / «pipeline green» / similar) as the acceptance bar, **probe the target branch's last CI run**. If the baseline run is itself failing, a strict «all green» gate is unfulfillable by a mechanical change and will force ad-hoc V-gate reformulation at `/dr-do` or `/dr-archive` time.
    -   For target branches with a failing baseline (e.g. WIP branches, work-branches accumulating partial fixes, dependency-bump branches against a red baseline), draft V-CI as a **delta** check: «no NEW failures vs baseline» — the change must not regress any job that was green on the baseline run.
    -   Strict «all CI jobs green» is appropriate **only** when the baseline run is itself green.
    <!-- gate:example-only -->
    -   Concrete recipes (illustrative — substitute the project's actual CI provider; pattern applies equally to GitHub Actions, GitLab CI, CircleCI, Buildkite, Jenkins):
        -   Detect baseline status: `gh run list --branch <BRANCH> --limit 1 --json conclusion,databaseId`
        -   Capture failed jobs on baseline: `gh run view <baseline-run-id> --json jobs --jq '[.jobs[] | select(.conclusion=="failure") | .name]'`
        -   After change, compare: `gh run view <change-run-id> --json jobs --jq '[.jobs[] | select(.conclusion=="failure") | .name]'`
        -   Delta gate passes iff change-run failed-set ⊆ baseline failed-set (no new entries).
        -   GitLab CI equivalent: `glab ci list --branch <BRANCH>` + `glab ci view <id>` JSON.
    <!-- /gate:example-only -->
    -   The plan MUST cite the baseline run id and the baseline failed-job list inline so reviewers can verify the delta gate at `/dr-qa` / `/dr-archive` without re-querying.
    -   Rationale: WIP-branch dep-bump archives have repeatedly required ad-hoc V-checklist reformulation from «all green» to «no NEW failures vs baseline» because the target branch carried multiple pre-existing red jobs (`shellcheck-extracted`, `bandit-extracted`, `regression-bats`, `markdown-policy`, `semgrep`). Mechanical SHA replacement of pinned action versions cannot regress unrelated red jobs, but a strict-green gate written without baseline awareness force-fails the V-checklist post-hoc. A 30-second baseline probe at `/dr-plan` time prevents the reformulation churn.

11.6.  **Network Exposure Surfaces (tiered gate)**:
    -   Detect whether the plan touches any networking surface: docker-compose
        `ports`/`expose`, `redis.conf`, `postgresql.conf`, systemd `.socket`,
        firewall/UFW rules, or a runtime bind argument. If yes, set the
        `--network-diff` signal for the gate executor.
    -   Run `dev-tools/network-exposure-gate.sh --task-description datarim/tasks/{TASK-ID}-task-description.md [--network-diff] --quiet`
        and apply the verdict per `$HOME/.claude/skills/network-exposure-baseline.md` § Tiered Gate Rules:
        -   **`hard_block`** → the plan MUST include a section
            **«Network Exposure»** that lists every touched listener with
            target Tier (0/1/2/3) and, for Tier 3, the proposed
            `x-exposure-justification` text and `x-exposure-expires` date.
            The plan MUST also cite an explicit acceptance criterion that
            `dev-tools/network-exposure-check.sh` will pass against the
            proposed configuration. Without this section the plan is
            incomplete; do not advance to `/dr-do`.
        -   **`advisory_warn`** → if a networking surface is touched, emit a
            single-line advisory in the plan's § Risks pointing readers to
            the skill. Do not block.
        -   **`skip`** → no plan section required.
    -   When justifications are needed, provide concrete mitigation language —
        not «потому что надо». TTL ≤ 90 days from plan authorship, in the
        future. The gate is fail-closed on missing/malformed
        `priority`/`type`.

12.  **Class B Public Surface Scan** (MANDATORY when Class A/B gate per `$HOME/.claude/skills/evolution.md` classifies the task as **Class B** — operating-model / contract change):
    -   Enumerate ALL user-facing surfaces that reflect the new operating model. Minimum:
        -   `code/datarim/docs/getting-started.md`
        -   `code/datarim/README.md`
        -   `code/datarim/CLAUDE.md`
        -   `Projects/Datarim/CLAUDE.md` and `Projects/Datarim/README.md`
        -   `Projects/Websites/datarim.club/pages/getting-started.php` (public onboarding — **mandatory**)
        -   `Projects/Websites/datarim.club/pages/changelog.php` (release entry)
        -   `Projects/Websites/datarim.club/content/{en,ru}.php` (if stat counts / onboarding-related strings change)
        -   `Projects/Websites/datarim.club/config.php` (version)
    -   For EACH surface in the list, plan §5 MUST include an explicit affected-files entry AND PRD MUST include a corresponding acceptance criterion (e.g. `AC-NN: live curl /docs/getting-started \| grep <new-term>` for live verification).
    -   Deferring a surface to /dr-qa or /dr-archive is a **Class B contract violation** — Class B tasks ship with their full public surface coverage in /dr-do, not «minor скорректируем потом».
    -   When a Class B operating-model AC (e.g. `pages/getting-started.php` symlink content) is deferred from `/dr-do`, it surfaces only at `/dr-archive` live deploy verification. Surface scan checkpoint prevents recurrence.

13.  **Output Summary**:
    -   Confirm task status update.
    -   List next steps by complexity:
        -   L3-4 → `/dr-design`
        -   L1-2 → `/dr-do`

## Template Structure (Design Document)

The plan in `datarim/tasks.md` MUST include: **Overview**, **Security Summary** (Attack Surface, Risks), **Architecture Impact**, **Detailed Design** (components, API, DB), **Security Design** (Threat Model, Appendix A controls), **Implementation Steps**, **Test Plan**, **Rollback Strategy**, **Validation Checklist**, **Next Steps**. (Enhanced Design Process Phases 4-6.)

## Security Requirements (Appendix A)

-   **Principles**: Fail-closed, Least privilege, No secrets in code/logs.
-   **Anti-Patterns**: Trusting user input, Logging sensitive data, Hardcoding secrets, SQL concatenation, Unvalidated file paths.

## Transition Checkpoint

Before proceeding to `/dr-design` or `/dr-do`:
```
[ ] Requirements clearly documented?
[ ] Components and affected files identified?
[ ] Installer/deploy-script content-type audit done (if plan touches install.sh / sync / deploy)?
[ ] Live fixture captured into `datarim/tasks/{TASK-ID}-fixtures.md` if the plan parses any external tool output (CLI/API/subprocess/log)? (Empirical capture replaces locale-fragile regex with structural parsing of machine-readable fields.)
[ ] All aggregate counts in plan derived from source tables (not freehand)?
[ ] Definition of Done is testable and explicit?
[ ] Boundaries stated (what we DON'T do)?
[ ] Technology stack validated (if applicable)?
[ ] If plan declares a CI green-jobs gate, baseline CI run probed and V-CI drafted as «all green» (only if baseline green) or «no new failures vs baseline» (if baseline carries pre-existing red jobs)? Baseline run id and baseline failed-job list cited inline in plan? (WIP-branch dep-bump archives have repeatedly required ad-hoc V-checklist reformulation; baseline probe at plan time prevents the churn.)
[ ] Live audit checkpoint executed for any lockable manifest (project's package-manager-native audit at the declared CI threshold) and either gate passes or accepted-risk sign-off is recorded in plan? (A backend-framework pin chosen at PRD time can fail the project's high-severity audit gate — check at plan-time, not at do-time.)
[ ] Rollback strategy viable? (verify commands actually work — e.g., is the target a git repo?)
[ ] For TDD sections of the plan: each test assertion traced through *current* (pre-fix) code state before being labelled expected-pass or expected-fail? (A plan predicting «N of M tests pass before fix» is wrong if the predictions are not checked against the actual code path with the bug still present.)
[ ] Every test-count baseline claim (e.g. «X/Y tests pass») cites the branch and HEAD SHA the count was measured on? (Prior incident: a plan captured a green/red split on a feature branch and framed it as the main baseline; first action of /dr-do — `git checkout origin/main` — revealed the actual baseline differed because the failures belonged to an unmerged sibling branch. A `git rev-parse HEAD` next to the count would have caught it before the remediation tree was drafted.)
[ ] tasks.md updated with implementation plan?
[ ] If the plan touches a networking surface (compose ports / redis / postgres / systemd socket / firewall), `dev-tools/network-exposure-gate.sh` was invoked and its verdict was applied: `hard_block` ⇒ § Network Exposure section present with Tier classification + verifier-pass AC; `advisory_warn` ⇒ § Risks one-liner; `skip` ⇒ nothing.
```

## Usage

Run: `/dr-plan`

## Reusable Templates

- `templates/integration-checklist.md` — third-party-integration checklist for any task that adds, replaces, or modifies an integration with an external HTTP API, SDK, webhook target, OAuth provider, payment gateway, message queue, storage API, or LLM/STT/TTS endpoint. Reference from Step 6 (Technology Validation) when the task contains the `external API` keyword or introduces a new third-party dependency.
- `templates/security-deps-upgrade-plan.md` — see `skills/security.md`. Reference during Step 6 for dependency-CVE / framework-bump tasks.
- `templates/infra-cost-reduction-checklist.md` — see `skills/infra-automation.md`. Reference during Step 6 for VM/storage right-sizing or unused-resource cleanup.
<!-- gate:example-only -->
- For stack-specific scaffolds (e.g. NestJS, Django, Rails): see the relevant project's `CLAUDE.md` or its per-project `templates/` directory. The Datarim framework `templates/` dir remains stack-agnostic — see `skills/evolution/stack-agnostic-gate.md`.
<!-- /gate:example-only -->

## Next Steps (CTA)

After plan generation, the planner agent MUST emit a CTA block per `$HOME/.claude/skills/cta-format.md`.

**Routing logic for `/dr-plan`:**

- L3-4 with creative-phase needs → primary `/dr-design {TASK-ID}` (auto-transition for L3-4)
- L3-4 without creative-phase needs → primary `/dr-do {TASK-ID}` (skip design)
- L1-2 → primary `/dr-do {TASK-ID}` (begin TDD)
- Plan incomplete or strategist suggests pivot → primary `/dr-prd {TASK-ID}` (revise scope)
- Always include `/dr-status` as escape hatch

The CTA block MUST follow the canonical format (numbered, one `**рекомендуется**`, `---` HR). Variant B menu when >1 active tasks.
