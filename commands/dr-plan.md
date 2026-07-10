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


**Stage Header (mandatory)**: Emit `**{TASK-ID} · {title}**` as the first line of your response, before any tool-call narration. The title is the verbatim one-liner field from `tasks.md` (between `L{N} · ` and ` → tasks/`). Skip this header only for `/dr-help`, `/dr-status`, `/dr-doctor`, and `/dr-init` Steps 1-3 (which emit it immediately after Step 4). See `$HOME/.claude/skills/cta-format/SKILL.md` § Stage Header.
0.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system/SKILL.md` § Path Resolution Rule.

1.  **TASK RESOLUTION**: Apply Task Resolution Rule from `$HOME/.claude/skills/datarim-system/SKILL.md` § Task Resolution Rule. Use the resolved task ID for all subsequent steps.

1.5. **READ INIT-TASK** (mandatory per `$HOME/.claude/skills/init-task-persistence/SKILL.md`): Open `datarim/tasks/{TASK-ID}-init-task.md` if present. Read the full `## Operator brief (verbatim)` section AND every `## Append-log` entry. Any divergence between the operator's stated intent and the planned scope MUST be recorded in the plan's § Notes / § Risks. Missing init-task is non-blocking — flag as advisory and continue.

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
    -   **Architectural-superseding probe (MANDATORY first sub-step before any component breakdown)**: if the task description carries a `Spawned from` / `Source:` reference to a prior archive, OR addresses a problem class that other recent archives may have already solved, read those references and answer one question: *has any recent task already resolved the architectural problem this task addresses?* If yes — recommend cancellation, scope reduction, or re-framing as redundancy/follow-up BEFORE proceeding to component breakdown. Document the answer (and the archives consulted) inline in the plan's Overview / Decisions section. Cost: a single grep + skim. Saving: avoids designing infrastructure that has been obsoleted by a sibling task whose archive the operator has not yet internalised.
    -   **Component Breakdown**: List every modified and new file. If any component changes the timing, sequencing, or condition of a canonical interface (Stage Header, CTA block, pipeline routing markers, exemption lists), add the canonical contract file (`skills/cta-format/SKILL.md`, `skills/datarim-system/backlog-and-routing.md`, etc.) as an explicit component in the same step. PRD risk rows are not a substitute for plan component rows.
    -   **Interface Design**: Define function signatures, API contracts.
    -   **Data Flow**: Trace input -> processing -> output.
    -   **Security Design**: Perform **Threat Modeling** and map to **Security Controls** (Appendix A).

5.  **Create Implementation Plan (Phase 5)** — thin-index schema:
    -   **`datarim/tasks.md`** carries ONLY the one-liner pointer (canonical regex per `skills/datarim-system/SKILL.md` § Operational File Schema):
        ```
        - {TASK-ID} · in_progress · P{n} · L{n} · {title} → tasks/{TASK-ID}-task-description.md
        ```
        Never write plan content directly into `tasks.md`.
    -   **L1-L2 tasks:** plan body lives in `datarim/tasks/{TASK-ID}-task-description.md` § Implementation Notes (or a dedicated `## Implementation Plan` section). Description file MUST have the 12-key YAML frontmatter (see `skills/datarim-system/SKILL.md` § Description File Contract).
    -   **L3-L4 tasks:** plan body lives in `datarim/plans/{TASK-ID}-plan.md`. The description file's frontmatter sets `plan: plans/{TASK-ID}-plan.md`. The description body's `## Related` section points readers there.
    -   Both formats use the same **Design Document Template** (Phase 5 below).
    -   Include: **Security Summary** (Attack Surface, Risks), **Architecture Impact**, **Detailed Design** (API, DB, Config), **Security Design** (Threats, Controls), **Implementation Steps**, **Test Plan** (Unit/Integration/Security), **Rollback Strategy**, **Validation Checklist**.

5b. **Append-merge expectations checklist (L2 without PRD, plan-driven additions only)** per `$HOME/.claude/skills/expectations-checklist/SKILL.md` § Append-merge contract:
    -   **Expectations creation contract:** the expectations file is **created at `/dr-init` Step 4.7** for all tasks (L1-L4). This step does NOT create the file from scratch — it **append-merges** plan-derived wishes that augment the init-task skeleton (L2 without PRD only).
    -   Skip this step when a PRD exists — `/dr-prd` Step 5.5b already handled the PRD-driven append-merge.
    -   For L2 tasks without a PRD, the planner MUST load existing `datarim/tasks/{TASK-ID}-expectations.md` (already seeded at `/dr-init`) and append any plan-derived wishes the init-task skeleton did not cover.
    -   **Source of new items (append candidates).** Each plan § Validation Checklist row that asserts an operator-observable outcome → one candidate wish. Compare candidate's semantic content with existing items by `wish_id`:
        - **Match (semantic equivalence with existing wish):** do not append; add one `stage: append-merge` line to existing wish's `#### История статусов` (reason: "refined in the plan"). <!-- allow-non-ascii: literal-russian-status-history-section-name-from-expectations-template -->
        - **No match (genuinely new operator-observable outcome):** append at the bottom as a new item:
            - title in plain Russian ending with a period;
            - `wish_id` = kebab-slug of the title (cyrillic allowed);
            - `Что хочу проверить:` one or two sentences; <!-- allow-non-ascii: literal-russian-field-name-from-expectations-template -->
            - `Как проверить (success criterion):` one concrete signal; <!-- allow-non-ascii: literal-russian-field-name-from-expectations-template -->
            - `Связанный AC из PRD: «—»` (no PRD); <!-- allow-non-ascii: literal-russian-field-name-from-expectations-template -->
            - `evidence_type:` (default `empirical`; choose `static` or `measurement` per validation nature);
            - `#### История статусов` with one initial line `<ISO> / <local> · /dr-plan · pending → pending · reason: пункт добавлен из плана § Validation Checklist`; <!-- allow-non-ascii: literal-russian-field-name-from-expectations-template -->
            - `#### Текущий статус: pending`. <!-- allow-non-ascii: literal-russian-field-name-from-expectations-template -->
    -   **Do not rewrite, reorder, or delete existing items.** Operator controls pruning via explicit `Текущий статус: deleted`. <!-- allow-non-ascii: literal-russian-field-name-from-expectations-template -->
    -   **Post-write validation gate.** Invoke:
        ```bash
        "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-expectations-checklist.sh" --task {TASK-ID}
        ```
        Exit code `1` ⇒ STOP and fix the file before continuing.
    -   For L1 tasks this step is skipped entirely; the init-task skeleton from `/dr-init` Step 4.7 is sufficient. For L3-L4 tasks the PRD step (Step 5.5b in `/dr-prd`) handled the append-merge already.

5c. **AUTOMATIC SPEC-GRAPH VALIDATION**:
    -   Every implementation or validation step that satisfies acceptance criteria MUST carry an explicit `Verifies: V-AC-N[, ...]` marker.
    -   After the plan is written, invoke:
        ```bash
        "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/spec-graph-gate.sh" \
            --task {TASK-ID} --stage plan --root <repo-root> --format json
        ```
    -   Exit `2` blocks the stage. In explicit hard mode, exit `1` blocks transition to `/dr-do`; otherwise findings are advisory and must be summarized in the plan response.

6.  **Technology Validation**:
    -   Document technology stack selection.
    -   Verify dependencies and build configuration.

6.5.  **Symbol Existence Check (MANDATORY when the plan names a method, function, file, flag, env var, or CLI command as a fix target)**:
    -   For every named code surface in the plan (e.g. `module.foo`, `path/to/file.ext`, `--flag-name`, `$ENV_VAR`), grep the project to confirm it exists.
    -   **Access-layer existence, not just symbol existence (MANDATORY when a plan step reads or writes a datastore through an ORM / datasource / generated client).** A named symbol existing is NOT the same as the data-access binding for that store being wired. When the plan's data-flow depends on reading/writing a table, collection, or stream via an ORM model, a configured datasource, or a generated client, verify that the specific access binding actually exists and is connected to that store — cite the file:line where the datasource/model/client is declared, or mark it `[to-be-created]` with a one-sentence justification. A store reachable only through a different access path (e.g. a table touched solely by a shell/CLI job with no ORM model, or a second database with no configured client) MUST be surfaced at plan time, so the data-flow is not built on an access layer that cannot exist for that store. Cost: one grep for the datasource/model declaration; saving: a full pipeline cycle — a phantom access layer otherwise surfaces only at implementation time and forces a mid-build re-architecture.
    -   The plan MUST cite the file:line where each named target lives. Phantom targets (named in the plan but absent from the code) are a planning defect — fix the plan or fix the code, then re-grep.
    -   If a target is intentionally to be created, the plan MUST say so explicitly and justify the new surface (one sentence: why does this need to exist?). Otherwise, redirect the fix to the actual surface that owns the behaviour.
    -   Apply to all references: not just function names, but also config keys, CLI sub-commands, file paths, env vars, and HTTP routes.
    -   **PRD AC verification commands MUST also be smoke-checked at plan time.** For every PRD AC `**Verification:**` line, run the verification command against the implemented CLI surface OR its pre-implementation skeleton. Verify: all flags exist with the documented argument shape; positional vs named args match the contract; env vars referenced are documented; expected exit code matches. Phantom flags (e.g. `--dry-run` when script accepts only named flags), positional-args invocations against named-flag contracts, and misnamed env vars (e.g. `CLAUDE_RUNTIME` when impl reads `CODEX_RUNTIME`) are caught here, not at `/dr-verify` post-`/dr-do`. Cost: ~5 seconds per AC; saving: a full pipeline cycle (do + verify + reconciliation).
    -   **AC ↔ V-AC semantic match (not just verbatim text mirror).** For every Validation Checklist row, verify that the V-AC verification command empirically tests the specific contract the corresponding PRD AC asserts. Example failure mode: PRD AC «cost-cap soft enforcement, exit 2 on breach» but V-AC row tests `for f in ...; test -f $f` (file presence) — verbatim cite of AC number, but verification tests something else entirely. Verbatim mirror is necessary but not sufficient — meaning must align.
    -   **V-AC runtime feasibility probe (MANDATORY when any Validation Checklist row's verification is a runtime command — `docker exec`, `kubectl exec`, `curl`/Playwright against a running service, `systemctl`/`journalctl`, or a live `redis-cli`/`psql`/`mongosh` query).** Semantic AC↔V-AC match (the bullet above) proves the command tests the *right contract*; it does NOT prove the command *can PASS under a correct implementation*. A runtime command can be infeasible by runtime semantics — e.g. `docker exec C printenv X` never observes a value set via `process.env[X]=Y` inside a running Node process, because `printenv` reads the shell env, not the live process env — yet such a V-AC survives a text-only review. Before locking each runtime-command V-AC, prove feasibility per `$HOME/.claude/skills/v-ac-feasibility/SKILL.md`: dry-run the command against a real dev/staging/test runtime (or a skeleton) under a deliberately-correct fixture, OR name the exact observation path (log line / health-endpoint field / persisted side-effect) through which the asserted value becomes observable to the command. Annotate the verdict inline (`V-AC-N — feasible (dry-run …)` / `feasible (observation path: …)` / `infeasible as written → re-scoped to …`). A runtime-command V-AC with no feasibility annotation is a planning defect — re-scope to an observable assertion before `/dr-do`. Cost: one dry-run or one observation-path statement. Saving: a full pipeline cycle — an infeasible V-AC otherwise surfaces only at `/dr-do` / `/dr-verify` as a test that cannot pass however correct the code.
    -   **V-Plan grep-text case-sensitivity audit (MANDATORY when V-Plan / Validation row uses `grep -E "<text>"` against an append-log / markdown heading / status word).** Literal `grep` is case-sensitive by default; markdown headings often capitalise the first word (e.g. heading «Partial closure» vs grep pattern `"partial closure"` → 0 matches, semantic match exists). For every literal-string grep in the V-Plan, either: (a) add `-i` flag for case-insensitive match, OR (b) quote the exact heading/status word from the source-of-truth as the grep pattern. Trigger heuristic: if the grep text contains common headline words (`partial`, `closure`, `pending`, `done`, `met`, `missed`, `deferred`), warn the operator that case-sensitivity is a likely defect class — literal-grep can report FAIL while semantic intent is satisfied, wasting a QA-failure-routing cycle on a non-defect.
    -   **Git topology probe (MANDATORY when Implementation Steps name a file as edit / rollback target)**: for every named file path in Implementation Steps, disambiguate gitignored-vs-non-git via two steps — first probe the working tree by exit code: `if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then ... else <non-git branch> fi` (non-zero exit ⇒ path is non-git, use alt rollback); inside a working tree, run `git -C "$dir" check-ignore -v -- "$path"` (quote BOTH `"$dir"` and `"$path"` — directories or files with whitespace / backticks / `$(...)` break unquoted; `--` terminates option parsing — planner-emitted paths are untrusted input per Security Mandate S1/S5). If the path is gitignored OR lives outside any git working tree:
        -   The Rollback Strategy MUST cite a non-git restore mechanism (backup-then-overwrite, `cp` from snapshot, deploy-script re-run) — `git checkout` / `git revert` are unavailable for gitignored or untracked paths.
        -   Flag the file explicitly in the plan's § Rollback Strategy with a one-line annotation: `<path> — gitignored (or non-git); rollback via <mechanism>`.
        -   Common surfaces: deploy-script-synced web roots, gitignored landing/dist directories, runtime symlinks to canonical repos in sibling submodules, CDN-synced assets.
        -   Rationale: a plan that names a gitignored file as edit target and prescribes `git checkout <path>` as rollback is unexecutable — the file is invisible to git. A 5-second `git check-ignore` at plan time catches this class of unexecutable rollback before `/dr-do`.
    -   **Shared-tree foreign-edit probe (MANDATORY when Implementation Steps name a file as an edit target in a workspace shared by parallel sessions).** A file may already carry another session's uncommitted changes; a naive `git add <file>` at `/dr-do` would silently capture those foreign hunks into this task's commit (Multi-Agent Workspace Discipline violation). For every named edit-target file, run `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-shared-tree-conflict.sh" --repo <repo> <file>...` (exit 1 = the file differs from `origin/main` in the working tree → it carries in-flight edits). When it reports `CONFLICT`, the plan's § Implementation Steps MUST prescribe committing via an isolated `git worktree` off a clean `origin/main` base (re-applying only this task's hunks), NOT `git add <file>`. Cost: one probe per edit-target. Saving: avoids a mixed-file commit that drags a parallel session's work — caught at plan time, not discovered at commit time. Cost is one probe per edit-target; the saving is not shipping a mixed-file commit that captures a parallel session's unstaged work.
    -   **Public-surface routing convention probe (MANDATORY when V-AC includes any HTTP/HTTPS request — `curl`, `wget`, HTTPie, Playwright `page.goto`, fetch, browser smoke — against a deployed web surface)**: before writing any HTTP URL into the Validation Checklist, grep the surface's router or front-controller for the actual URL conventions in use. Apply the case-sensitivity heuristic from the preceding audit bullet — prefer `-i` or exact-match quoting to avoid false negatives on capitalised conventions.
        <!-- gate:example-only -->
        -   Common router locations: `router/index.php`, `app/routes.php`, `config/routes.rb`, `urls.py`, framework-equivalent front-controller.
        <!-- /gate:example-only -->
        -   Conventions to verify before writing HTTP smoke commands (applies uniformly to curl, wget, HTTPie, Playwright `page.goto`, fetch, browser smoke):
            -   Pagination format — path-regex (`/blog/page/N`) vs query param (`?page=N`) vs numeric segment (`/blog/N`).
            -   Lang prefix — path-segment (`/{lang}/...`) vs query (`?lang=`) vs subdomain vs none.
            -   Slug regex — accepted character set for dynamic path segments.
        -   Cite the router file:line where the convention is defined inline in the plan (V-AC reviewers verify without re-grepping). When citing, quote ONLY the route-pattern / param-name tokens needed to verify the convention — NEVER cite full lines containing DSNs, tokens, secrets, or internal hostnames (Security Mandate S3); redact to `…` and reference `file:line` only.
        -   Rationale: a V-AC `curl https://example.com/blog?page=2` (or equivalently `Playwright page.goto('/blog?page=2')`) against a router that maps only `/blog/page/N` returns 404 at deploy verification — the V-AC is unexecutable as written regardless of HTTP client. A 30-second router grep at plan time catches this before `/dr-do` produces a failing smoke.
    -   **External target reality-probe (MANDATORY when an agent-decision under FB-4/FB-5 cites a specific filesystem path or external URL — `Projects/<repo>/`, `Projects/Websites/<site>/`, `https://<domain>/<path>` — as a deploy / write / lookup target).** Memory and INSIGHTS files can reference never-provisioned resources or paths that drifted away from canonical. Before locking the target into the plan: `ls "<path>"` MUST return a real entry; for any web target, `curl -fsSL -o /dev/null -w '%{http_code}\n' https://<domain>/' MUST return `200` (or a justified non-200 — e.g. `404` is expected for a path that this plan will create on deploy). Non-existent path or HTTP `000` (DNS does not resolve) ⇒ memory stale; pause and ask the operator to confirm the canonical target before continuing.
        -   Cost: ~5 seconds per cited target. Saving: one extra QA cycle where the gap surfaces as a `partial` expectation entry that has to be re-routed back to `/dr-do`.
        -   Quote the probe result inline in the plan (`<path> — ls confirms`, `https://<domain>/ — HTTP 200`) so reviewers can replay without re-querying.
    -   **External capability tier-probe (MANDATORY when a plan step depends on a CLI sub-command or external API endpoint whose availability is gated by account-tier, license, or feature-flag — not merely by the binary being installed).** A capability can be present in the tool yet forbidden to this account: `tailscale cert` exists on every install but is refused on the Free plan; a paid-API endpoint returns `402`/`403` for a free-tier key while `--help` still lists it. `--help` (or `command -v`) proves the sub-command *exists* — it does NOT prove the plan's account/tier is *entitled* to run it. Before locking such a step into the plan, the probe MUST attempt the operation itself, or its documented dry-run (`--dry-run`, a no-op/idempotent invocation, or the smallest real call), and read the actual exit code / HTTP status — a tier-gate refusal (`403`, `402`, `quota exceeded`, `requires <paid> plan`) means the capability is unavailable for this plan and the step must be re-scoped or operator-escalated, NOT carried forward on the strength of `--help` alone.
        -   Cost: ~5-10 seconds (one real or dry-run invocation). Saving: a full pipeline cycle — a tier-gated capability that `--help` blessed surfaces as a hard block only at implementation time.
        -   Quote the probe result inline in the plan (`<capability> — dry-run exit 0, entitled` or `<capability> — HTTP 403 tier-gated → re-scope`) so reviewers can replay without re-querying.
    -   **CLI binary-name discovery probe (MANDATORY when the plan names a CLI tool as an install-target — "the plan installs and then invokes `<tool>`").** The published package name, the documentation name, and the actual executable on `PATH` after install are frequently NOT the same string — a vendor can rename the binary while keeping the brand (a plan wrote `cursor` as the command; the installed executable was `cursor-agent`). `command -v <assumed-name>` BEFORE install proves nothing, because the tool is not installed yet. For every CLI tool the plan installs and then calls, the plan MUST cite EITHER (a) the binary name discovered via `command -v <name>` (or the installer's own post-install output) AFTER a fresh install on a sibling system, OR (b) an explicit `[to-be-discovered]` marker naming the install step that will resolve it — never an assumed "well-known" command name carried into Implementation Steps unverified.
        -   Cost: one fresh install + `command -v` on a sibling host, or a deferred `[to-be-discovered]` marker. Saving: a full pipeline cycle — an assumed-but-wrong binary name surfaces as a "command not found" hard block only at `/dr-do` execution time.
        -   Quote the result inline in the plan (`<tool> → binary `<discovered-name>` (command -v on sibling host)` or `<tool> → [to-be-discovered] at install step N`) so reviewers can replay without re-installing.
    -   **External target necessity-probe (MANDATORY when an agent-decision concludes "resource X is unavailable / broken → the plan must provision or fix X", where X is a private repo, credential, integration, service, or access path in a remote / contractor / non-default environment).** Proving X is unreachable (feasibility) is NOT proving X is needed (necessity). Before locking a "provision / fix X" step into the plan, probe whether X is actually *used* in this environment at all: inventory the real consumers (`ls`/`git remote -v` of cloned repos, live-usage grep, "what process or workflow on this host actually reaches X"). If nothing in the environment uses X, the correct decision is "X out of scope", not "restore access to X". Especially when the environment is not the operator's primary one (a contractor VM, a client host, a sibling space) — its repo/integration set differs from the default. Cost: ~10 seconds (usage inventory). Saving: avoids designing infrastructure for a need that does not exist. Quote the necessity-probe result inline (`X used by: <consumers>` or `X used by: none → out of scope`).
    -   **History-agnostic runtime-body probe (MANDATORY when Implementation Steps name any file under `skills/`, `agents/`, `commands/`, or `templates/` of a Datarim-style framework runtime as an edit or create target).** The framework runtime is history-agnostic by contract: shipped rule bodies MUST NOT embed task-ID provenance (`Source: <TASK-ID>`, `Per <TASK-ID>`, `<TASK-ID> introduced …`) — such references couple a rule to an ephemeral identifier, distract the reading agent, and risk leaking a historical ID into an end-user-facing AI output. Today this is enforced only downstream (`/dr-do` post-phase-commit pre-flight, `/dr-qa`, `/dr-compliance`, CI `task-id-gate`), so a plan that *prescribes* writing provenance into a shipped body is not caught until a full QA cycle has been spent. Shift the probe left: before locking a runtime-body edit into the plan, apply the deterministic gate contract per `$HOME/.claude/skills/evolution/history-agnostic-gate.md` — verify (a) no Implementation Step or example text the plan will ship into a runtime body carries a task-ID provenance token, and (b) every file/script/path the plan cites as an edit or rollback target resolves via the exists + deprecation ladder in `$HOME/.claude/skills/plan-path-validator/SKILL.md` (`git cat-file -e`/`test -e` for existence, deprecation-marker grep for staleness) — reuse that skill rather than re-deriving the probe. Annotate the verdict inline (`runtime-body probe — clean, no provenance; N path refs present, 0 deprecated` or `provenance leak in Step N example → rephrase to abstract prose before /dr-do`). A runtime-body edit-target with no history-agnostic annotation is a planning defect — resolve it at plan time, not at `/dr-qa`. Cost: one `scripts/task-id-gate.sh <touched-paths>` dry-run plus the path-validator ladder (~10 seconds). Saving: a full QA-failure-routing cycle — a provenance leak or phantom runtime path otherwise surfaces only at `/dr-qa`/`/dr-compliance` and forces a separate late fix.
<!-- gate:history-allowed -->
    -   **Install-topology survey gate (MANDATORY when the plan fixates a path-resolution canon — env-var, runtime root, install path, template ref, config-file location — that consumer agents will copy literally from runtime markdown).** A canon that works for the default install can silently miss every other install mode. Before locking the canonical form into the plan, survey ALL install topologies the runtime supports and verify the proposed canon resolves correctly in each. For frameworks (e.g. Datarim under `code/datarim/install.sh`), this means: (a) default symlink install (`./install.sh` no flags → runtime at `$HOME/.claude/`); (b) per-project install (`./install.sh --project DIR` → runtime at custom location); (c) copy-mode with custom `CLAUDE_DIR` env override; (d) plugin overlays mounting under a runtime root. Cite the survey result inline in the plan (`canon X works for default symlink ✓ / fails for --project DIR ✗ → escalate to env-var fallback form Y`). Heuristic: if the existing canonical pattern for adjacent surfaces uses an env-var fallback (e.g. `${RUNTIME_VAR:-$HOME/.claude}/...`), prefer that form for new path refs too — silent precedent is canonical. Source: TUNE-0267 v1 → v2 canon-correction (v1 `$HOME/.claude/templates/X` worked only for default symlink; v2 migrated 41 refs to `${DATARIM_RUNTIME:-$HOME/.claude}/templates/X` after operator Q&A surfaced the blind spot). Cost: ~30 seconds (grep install script for mode flags + grep adjacent surfaces for existing env-var patterns). Saving: avoids a full canon-correction cycle.
<!-- /gate:history-allowed -->
    -   Rationale: a 30-second grep at planning time prevents 10–30 minute investigations during `/dr-do`. A plan that names a method as the fix surface but the method does not exist (e.g. behaviour was implemented inline in a different module) requires in-flight redirect — a single grep at `/dr-plan` time would have caught it.

6.6.  **Auth-Parameter Widening Axis Enumeration (MANDATORY when the plan widens the accepted values of an authentication parameter — e.g. accepting a second `aud`, an additional `iss`, a broader `scope`, or an additional `alg`)**:
    -   Enumerate every JWT claim the widened code path touches — `iss`, `aud`, `scope`, `alg`, `exp` — plus any additional claim the specific widening reads.
    -   For each enumerated claim, confirm the plan documents how it is handled on BOTH the accept path and the reject path, not just the one axis being changed.
    -   Add one dedicated spec case per axis variant to the Validation Checklist: an accept case for the newly-widened value, and a reject case for every other value on that axis.
    -   Rationale: prevents pass-for-wrong-reason. A widening that touches only one axis (e.g. `aud`) can still ship a hole on an orthogonal axis (e.g. `iss`) if that axis is never independently exercised — a spec that only varies the changed axis passes while a token that is wrong on the untouched axis slips through unexamined.
    -   Example: widening `aud` from `["auth.example.com"]` to `["auth.example.com", "auth.example.org"]` requires spec cases for `aud=.com` accept, `aud=.org` accept, `aud=other` reject, AND `iss=.com` / `iss=.org` verified independently on both accept paths — not assumed correct because the `aud` cases passed.

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
    -   Run `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/network-exposure-gate.sh" --task-description datarim/tasks/{TASK-ID}-task-description.md [--network-diff] --quiet`
        and apply the verdict per `$HOME/.claude/skills/network-exposure-baseline/SKILL.md` § Tiered Gate Rules:
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
        not "because we have to". TTL ≤ 90 days from plan authorship, in the
        future. The gate is fail-closed on missing/malformed
        `priority`/`type`.

12.  **Class B Public Surface Scan** (MANDATORY when Class A/B gate per `$HOME/.claude/skills/evolution/SKILL.md` classifies the task as **Class B** — operating-model / contract change):
    -   Enumerate ALL user-facing surfaces that reflect the new operating model. Minimum:
        -   `code/datarim/docs/getting-started.md`
        -   `code/datarim/README.md`
        -   `code/datarim/CLAUDE.md`
        -   `Projects/Datarim/CLAUDE.md` and `Projects/Datarim/README.md`
        -   `Projects/Websites/datarim.club/pages/getting-started.php` (public onboarding — **mandatory**)
        -   `Projects/Websites/datarim.club/pages/changelog.php` (release entry)
        -   `Projects/Websites/datarim.club/content/{en,ru}.php` (if stat counts / onboarding-related strings change)
        -   `Projects/Websites/datarim.club/config.php` (version)
    -   **n-way runtime↔site sync (when task adds a NEW command/skill/agent)** — for every NEW artifact, public surface coverage MUST include:
        -   `Projects/Websites/datarim.club/data/{commands,skills,agents}/<name>.php` (EN + RU short + body — site discoverability surface)
        -   `Projects/Datarim/code/datarim/docs/{commands,skills,agents}.md` (catalogue row, update count in the heading)
        -   `Projects/Datarim/code/datarim/CLAUDE.md` (commands/skills/agents table row, update count footer)
        -   `Projects/Datarim/code/datarim/README.md` (commands list mention, update count in the badge / description)
        These are the 4 surfaces required by the Public-surface ↔ runtime sync mandate (consumer CLAUDE.md § Public-surface ↔ runtime sync). Asymmetric drift ("site is ahead of the framework" or vice versa) = a discoverability gap. Detector: `dev-tools/doc-fanout-lint.sh` + `tests/test-command-doc-coverage.bats`.
    -   For EACH surface in the list, plan §5 MUST include an explicit affected-files entry AND PRD MUST include a corresponding acceptance criterion (e.g. `AC-NN: live curl /documentation/getting-started \| grep <new-term>` for live verification).
    -   Deferring a surface to /dr-qa or /dr-archive is a **Class B contract violation** — Class B tasks ship with their full public surface coverage in /dr-do, not "minor — we will tidy this up later".
    -   When a Class B operating-model AC (e.g. `pages/getting-started.php` symlink content) is deferred from `/dr-do`, it surfaces only at `/dr-archive` live deploy verification. Surface scan checkpoint prevents recurrence.

12.5. **APPEND Q&A IF ANY** (mandatory per `$HOME/.claude/skills/init-task-persistence/SKILL.md` § Q&A round-trip contract): for every operator clarification round captured during this stage — either operator answer or autonomous agent-decision under FB-1..FB-5 — invoke `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh"` to persist the round into `datarim/tasks/{TASK-ID}-init-task.md § Append-log`.
    -   Write the question and answer (and rationale, when applicable) to temp files first; free-form text MUST come via `--*-file <path>` per Security Mandate § S1.
    -   Required flags: `--root <repo-root> --task {TASK-ID} --stage plan --round <N> --question-file <path> --answer-file <path> --decided-by <operator|agent> --summary "<one-line>"`.
    -   When `--decided-by agent`: `--rationale-file <path>` MUST contain ≥ 50 non-whitespace characters of reasoning.
    -   On contradiction with an expectation: add `--conflict-with <wish_id>`; CTA MUST route work back to `/dr-prd` (revise discovery) or `/dr-do --focus-items <wish_id>` (when the conflict is implementation-detail level).
    -   Skip if no clarification rounds occurred. Utility exit 0 = appended; 1 = IO/validation error; 2 = usage error.

13.  **Output Summary**:
    -   Confirm task status update.
    -   List next steps by complexity:
        -   L3-4 → `/dr-design`
        -   L1-2 → `/dr-do`

## Template Structure (Design Document)

The plan in `datarim/tasks.md` MUST include: **Overview**, **Security Summary** (Attack Surface, Risks), **Architecture Impact**, **Detailed Design** (components, API, DB), **Security Design** (Threat Model, Appendix A controls), **Implementation Steps**, **Test Plan**, **Rollback Strategy**, **Validation Checklist**, **Next Steps**. (Enhanced Design Process Phases 4-6.)

When the task touches a command, skill, or agent that has a public docs-site counterpart, the plan's **Out of Scope** section MUST carry a presumptive site-sync call so the later hardening gate verifies a decision rather than making one from scratch: `Site data sync (e.g. data/commands/<name>.php): [skip — internal-mechanics change | update — user-facing behaviour change; confirm at /dr-compliance if uncertain]`. Most internal-mechanics edits presume *skip*; flag *update* only when the change alters what the docs page promises the operator.

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
[ ] If the plan touches a networking surface (compose ports / redis / postgres / systemd socket / firewall), `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/network-exposure-gate.sh"` was invoked and its verdict was applied: `hard_block` ⇒ § Network Exposure section present with Tier classification + verifier-pass AC; `advisory_warn` ⇒ § Risks one-liner; `skip` ⇒ nothing.
[ ] If Implementation Steps name a shipped framework runtime body (`skills/`/`agents/`/`commands/`/`templates/`) as an edit or create target, the § 6.5 History-agnostic runtime-body probe was run (task-ID-provenance gate per `$HOME/.claude/skills/evolution/history-agnostic-gate.md` + path exists/deprecation ladder per `$HOME/.claude/skills/plan-path-validator/SKILL.md`) and the verdict is annotated inline? (Shifts the history-agnostic gate left from `/dr-qa`/`/dr-compliance` to plan review, before approve.)
```

## Usage

Run: `/dr-plan`

## Reusable Templates

- `${DATARIM_RUNTIME:-$HOME/.claude}/templates/integration-checklist.md` — third-party-integration checklist for any task that adds, replaces, or modifies an integration with an external HTTP API, SDK, webhook target, OAuth provider, payment gateway, message queue, storage API, or LLM/STT/TTS endpoint. Reference from Step 6 (Technology Validation) when the task contains the `external API` keyword or introduces a new third-party dependency.
- `${DATARIM_RUNTIME:-$HOME/.claude}/templates/security-deps-upgrade-plan.md` — see `skills/security/SKILL.md`. Reference during Step 6 for dependency-CVE / framework-bump tasks.
- `${DATARIM_RUNTIME:-$HOME/.claude}/templates/infra-cost-reduction-checklist.md` — see `skills/infra-automation/SKILL.md`. Reference during Step 6 for VM/storage right-sizing or unused-resource cleanup.
<!-- gate:example-only -->
- For stack-specific scaffolds (e.g. NestJS, Django, Rails): see the relevant project's `CLAUDE.md` or its per-project `${DATARIM_RUNTIME:-$HOME/.claude}/templates/` directory. The Datarim framework `${DATARIM_RUNTIME:-$HOME/.claude}/templates/` dir remains stack-agnostic — see `skills/evolution/stack-agnostic-gate.md`.
<!-- /gate:example-only -->

## /dr-auto Mode (when `DATARIM_AUTO_MODE=1`)

When auto-mode is active (env var `DATARIM_AUTO_MODE=1` AND matching marker `datarim/.auto-mode-active` containing this TASK-ID), this command:

1. Consults `${DATARIM_RUNTIME:-$HOME/.claude}/skills/autonomous-mode/SKILL.md` § Question Suppression Ladder ([definition](../skills/autonomous-mode/SKILL.md)) before any `AskUserQuestion` or equivalent operator prompt at this stage.
2. Stage-specific suppression hooks:
   - Step 3 Strategist Gate (L3-4 only) — pivot suggestion resolved through Ladder; suggest pivot inline, escalate to L5 only if it changes scope materially.
   - Step 4 Architectural-superseding probe — operator decision (proceed / cancel / reframe) resolved through Ladder L1-L2 (read sibling archives).
3. Discovered gaps → apply L1 Inline Resolution Rule ([definition](../skills/autonomous-mode/SKILL.md)) per `skills/autonomous-mode/SKILL.md`; log in `datarim/tasks/{TASK-ID}-auto-inline-log.md` if applied inline.
4. Hard-gated actions → escalate to operator through Ladder L5; log via `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh" --decided-by operator` per `skills/init-task-persistence/SKILL.md` § Q&A round-trip.
5. Mismatch (env var set, marker absent OR marker contains different TASK-ID) → emit single-line warning, treat as non-auto (fail-safe per `skills/autonomous-mode/SKILL.md` § When this skill is active).

## Next Steps (CTA)

After plan generation, the planner agent MUST emit a CTA block ([definition](../skills/cta-format/SKILL.md)) per `$HOME/.claude/skills/cta-format/SKILL.md`.

**Routing logic for `/dr-plan`:**

- L3-4 with creative-phase needs → primary `/dr-design {TASK-ID}` (auto-transition for L3-4)
- L3-4 without creative-phase needs → primary `/dr-do {TASK-ID}` (skip design)
- L1-2 → primary `/dr-do {TASK-ID}` (begin TDD)
- Plan incomplete or strategist suggests pivot → primary `/dr-prd {TASK-ID}` (revise scope)
- Always include `/dr-status` as escape hatch

The CTA block MUST follow the canonical format (numbered, one `**рекомендуется**`, `---` HR). Variant B menu when >1 active tasks. <!-- allow-non-ascii: literal-russian-cta-marker-from-cta-format-skill -->

## Post-Step Self-Verification Hook (Automatic)

After the `## Next Steps (CTA)` block and before Stage Snapshot Emission, the agent MUST run the automatic self-verification hook for this stage. This is the pipeline-integrated counterpart of the manual `/dr-verify` command ([definition](../skills/self-verification/SKILL.md)); it reuses the same tri-layer contract but is dispatched automatically, complexity-tiered, and findings-only.

**Kill switch:** when `DATARIM_DISABLE_VERIFY_HOOK=1` is set, the whole hook is a no-op (no floor run, no dispatch, no warning). Use for cost-sensitive batch runs.

**Complexity tiering (`L1 OFF / L2 = 1 agent / L3+ = 3 parallel`).** Read the resolved task's `complexity` from `datarim/tasks/{TASK-ID}-task-description.md` frontmatter (fallback: the `L{N}` field on the `tasks.md` one-liner). Dispatch scales with complexity:

| Complexity | Layer 1 floor | Layer 2 peer-review | Layer 3 native dispatch |
|------------|---------------|---------------------|--------------------------|
| L1 | skipped (hook OFF — skill overhead exceeds value) | skipped | skipped |
| L2 | run (deterministic, zero LLM cost) | 1 agent (`agents/peer-reviewer.md`, readonly) | skipped |
| L3 / L4 | run | 1 agent | 3 parallel agents (reviewer / tester / security) |

**Layer 1 floor invocation (L2+):**

```text
bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/dr-verify-floor.sh" \
    --task {TASK-ID} --stage <stage> --workspace <project-root>
```

Capture JSONL findings on stdout (each carries `source_layer: "floor"`); stderr carries per-check progress. Bind `<stage>` to this command's stage literal declared in Stage Snapshot Emission below (`prd` / `plan` / `do`).

**Layer 2 / Layer 3 dispatch (per tier above)** follow the manual `/dr-verify` steps 6.2 and 6.3 verbatim (provider resolution via `dev-tools/resolve-peer-provider.sh`, `--task-id {TASK-ID}` propagation MANDATORY, readonly tool whitelist Read / Grep / Glob / Bash-read-only — NO Write / Edit / NotebookEdit). Semantic review stays in the selected agent runtime; never route it through coworker.

**Advisory vs blocking (`DATARIM_VERIFY_HOOK_MODE`, default advisory).**

- **advisory (default):** findings are surfaced but the stage still completes. The CTA already emitted stays authoritative; append a one-line hook summary (`verdict + source_layer_breakdown`) so the next stage and the operator see the floor result. This matches the do-stage evidence-still-accruing rationale — an automatic post-step hook must not silently gate a stage the operator did not opt to hard-gate.
- **hard (`DATARIM_VERIFY_HOOK_MODE=hard`):** a `BLOCKED` verdict (≥1 non-discarded `severity=high` finding) flips the CTA to the FAIL-Routing variant per the `/dr-verify` highest-severity-category map, so the operator is routed back to the earliest affected stage instead of forward.

**Findings-only, always.** No layer auto-fixes. Operator triages. Audit trail follows the manual path — write `datarim/qa/verify-{TASK-ID}-<stage>-<iter>.md` (append-only, `chmod a-w`) per the skill's Audit Log Writer only when Layer 2/3 ran (L2+); a pure-floor L2-tier run may skip the file and fold the floor verdict into the CTA summary line.

**Fail-closed on tooling error:** a non-zero floor *exit from a crash* (not the documented high-severity count) or a missing `dr-verify-floor.sh` emits a single stderr warning and the stage continues (advisory) — the hook never bricks the pipeline on its own infrastructure fault.


## Stage Snapshot Emission (Mandatory Terminal Step)

After the `## Next Steps (CTA)` block above, the agent MUST perform snapshot emission ([definition](../skills/stage-snapshot-writer/SKILL.md)) per `$HOME/.claude/skills/cta-format/SKILL.md` § Snapshot Emission. Parameters bound for this command:

- `stage`: `plan`
- `command`: `/dr-plan`
- `captured-by`: `agent`
- `recommended-next`: primary CTA option (slash-prefixed `/dr-*` form)

Fail-closed: on non-zero writer exit, emit a single stderr warning line and continue (V-AC-7 contract). Kill switch `DATARIM_DISABLE_SNAPSHOT=1` is handled inside the library; under the switch the writer is a no-op without warning.
