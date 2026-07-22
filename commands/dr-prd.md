---
description: Generate a Product Requirements Document (PRD) with rigorous design analysis (Context, Solution Exploration, Consultation).
globs:
  - datarim/projectbrief.md
  - datarim/techContext.md
  - datarim/systemPatterns.md
  - $HOME/.claude/templates/prd-template.md
---

# PRD Generation Command

This command generates a structured Product Requirements Document (PRD) following the **Enhanced Design Process** (Phases 1-3).

## Instructions

0.  **RESOLVE PATH**: Before any read/write to `datarim/`, find the correct path by walking up directories from cwd. If `datarim/` is not found anywhere, STOP and tell user to run `/dr-init`. Do NOT create it — only `/dr-init` may create `datarim/`. See `$HOME/.claude/skills/datarim-system/SKILL.md` § Path Resolution Rule.

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


0.5. **READ INIT-TASK** (mandatory per `$HOME/.claude/skills/init-task-persistence/SKILL.md`): Open `datarim/tasks/{TASK-ID}-init-task.md` if present. Read the full `## Operator brief (verbatim)` section AND every `## Append-log` entry. Any divergence between the operator's stated intent and the discovery scope MUST be surfaced in PRD § Discovery / § Constraints. Missing init-task is non-blocking — flag as advisory and continue.

0.7. **TASK-TYPE GUARD (research-task detection)**: Before running the product-PRD phases below, check whether this task is a **research / comparative-evaluation task** rather than a buildable product change. A PRD is a *product* requirements document; research tasks (technology selection, framework benchmarking, feasibility studies, literature surveys) produce an insights / decision artefact, not a shippable feature, and forcing them through the standard Problem→Scope→Technical-Approach→Success-Criteria structure yields a mis-shaped document.
    -   **Detection signals** (any one is sufficient):
        - the task ID uses the `RESEARCH` prefix (per `$HOME/.claude/skills/datarim-system/command-and-archive-rules.md` archive-subdir table);
        - the task-description frontmatter declares `type: research` (or an equivalent research/evaluation/benchmark type);
        - the operator brief in `datarim/tasks/{TASK-ID}-init-task.md` frames the work as *"compare / evaluate / survey / investigate / decide between"* candidates with no committed implementation target.
    -   **On a positive detection**, emit a single advisory **WARNING** to the operator before continuing, and offer the **escalation hint**:
        - WARNING: `This looks like a research task; the standard product-PRD structure (Problem → Scope → Technical Approach → Success Criteria) is a poor fit for comparative / feasibility research.`
        - HINT: recommend the research path instead — run `/dr-plan` with the research-workflow skill (`$HOME/.claude/skills/research-workflow/SKILL.md`) so findings land in `datarim/insights/INSIGHTS-{task-id}.md`, and drive candidate elimination through `/dr-plan` § Research Kill-Criteria Checkpoint rather than a product Technical-Approach section. If the operator confirms a genuine product PRD is still wanted, proceed with the phases below.
    -   The guard is **advisory-only**: it never blocks. In auto-mode (see § /dr-auto Mode) resolve the confirm/decline through the Question Suppression Ladder; log the decision per `$HOME/.claude/skills/init-task-persistence/SKILL.md` § Q&A round-trip. On no detection, continue silently to Step 1.

1.  **Analyze Context (Phase 1)**:
    -   Read `datarim/projectbrief.md`, `techContext.md`, and `systemPatterns.md`.
    -   Identify affected components and constraints (Security, Performance).
    -   Read relevant source code files to understand current implementation.

1.5. **Research External Context (Phase 1.3)** (L2+ only):
    -   Determine research mode: **Lite** (L2, 5 checkpoints) or **Full** (L3-L4, 10 checkpoints). Skip entirely for L1.
    -   Load `$HOME/.claude/skills/research-workflow/SKILL.md`.
    -   Spawn researcher agent (`$HOME/.claude/agents/researcher.md`) with task context: task ID, description, identified stack/dependencies from Phase 1.
    -   Agent creates `datarim/insights/INSIGHTS-{task-id}.md` from template `${DATARIM_RUNTIME:-$HOME/.claude}/templates/insights-template.md`.
    -   Agent runs research checklist per mode, using available tools adaptively (context7, WebSearch, LTM API, codebase analysis).
    -   If insights document already exists (e.g., from a previous `/dr-prd` run), update rather than overwrite.

2.  **Discovery Interview (Phase 1.5)**:
    -   If `datarim/insights/INSIGHTS-{task-id}.md` exists, read it before starting the interview — use research findings to inform questions and proposals.
    -   Load `$HOME/.claude/skills/discovery/SKILL.md`.
    -   Run a focused interview (mode based on complexity: Quick for L1-2, Standard for L2-3, Deep for L3-4).
    -   Apply codebase-first rule: prioritize existing code patterns and constraints over assumptions.
    -   Output structured requirements summary into the PRD discovery section.
    -   For L3-4 tasks, optionally invoke consilium skill (`$HOME/.claude/skills/consilium/SKILL.md`) for multi-perspective analysis of requirements.

3.  **Explore Solutions (Phase 2)**:
    -   Generate **3+ distinct technical approaches**.
    -   Evaluate each against criteria: Security, Pattern Alignment, DRY, Testability.
    -   Reject approaches with **Anti-Patterns** (e.g., hardcoded secrets, raw SQL).
    -   **Reuse-first check (MANDATORY when any candidate approach introduces a new non-secret, cross-project-reusable module — backend guard/interceptor/schema, frontend component/hook/util, shared config, client SDK wrapper, etc.)**: before finalizing candidate approaches, consult the `@arcanada/*` package catalog — `catalog.json` in `Arcanada-one/arcanada-shared`, generated via `pnpm catalog` (schema in `catalog.schema.json`); if the catalog hasn't landed in the target repo yet, browse `arcanada-shared/packages/*` directly and flag the gap. An existing package that already covers the need wins over a new local implementation. If no package fits, say so explicitly in the PRD (functional gap, not an unchecked assumption). See `documentation/mandates/reuse-first-mandate.md`.

4.  **Consult User (Phase 3)**:
    -   Present the alternatives clearly.
    -   Wait for user approval on the selected approach.

5.  **Generate PRD**:
    -   Use the structure from `${DATARIM_RUNTIME:-$HOME/.claude}/templates/prd-template.md`.
    -   Include: Problem Statement, Scope, Context Analysis, Technical Approach (Selected + Alternatives), Success Criteria, Risks.
    -   For infra/fleet PRDs, apply the `templates/prd-template.md` § Deploy-Phase Verification Items labelling — mark any AC whose e2e verification requires a live broker, deployed host, or external webhook as `deploy-deferred` so `/dr-qa` expects partial + operator-override instead of flagging a coverage gap.
    -   If insights document was created in Phase 1.3, add a reference in the PRD header: `**Research:** [INSIGHTS-{task-id}](../insights/INSIGHTS-{task-id}.md)`
    -   **Pre-save validation gates (MANDATORY before write):**
        - **`ships_in:` derivation.** If the PRD ships a framework / library release, read the canonical version source (e.g. `code/datarim/VERSION` or project equivalent) and pre-fill `ships_in: <next-minor-or-patch>`. Operator-supplied override requires an inline justification comment in the PRD body. Do not echo the value from memory or from the parent PRD verbatim — version drift between PRD draft and release is a recurring defect class.
        - **V-AC path live-validation.** For every AC / V-AC line citing a script, binary, spec file, or directory path: run `command -v <bin>` / `test -f <path>` / dry-run probe and confirm exit 0 before save. Cites that do not exist yet MUST be marked `[to-be-created]` inline so the gate distinguishes intentional plan-deliverables from typos / phantom paths. Block save if a non-`[to-be-created]` cite fails the probe. **Runtime-script root.** Any cite of a Datarim runtime script/tool MUST prefix an explicit root — `${DATARIM_RUNTIME:-$HOME/.claude}/` or `Projects/Datarim/code/datarim/` — never a bare-relative path (e.g. `dev-tools/foo.sh`); bare-relative paths are ambiguous about their base directory and break when the PRD is read from a different working directory.
        - **V-AC ecosystem-mandate alignment.** Run `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-v-ac-mandate-preflight.sh" --prd "$PRD_FILE"`. Advisory gate: the script extracts V-AC / Verification / Success Criteria lines and greps each against the forbidden-pattern set in `dev-tools/public-surface-forbidden.regex` (the same contract surface consumed by `public-surface-lint.sh`). Goal — surface a V-AC ↔ Public Surface Hygiene Mandate conflict at PRD-time, not at `/dr-qa`. The script always exits 0; on match it prints `WARNING:` lines to stdout for operator review. Optional `--regex <FILE>` override loads a consumer-extended pattern set without script changes.
        - **Surface-count-vs-host-count disambiguation.** Scan every AC / V-AC line for a bare numeric-count claim about an auth or security allowlist surface — OIDC `redirectUris`, CORS allowlists, CSP source-lists, or any equivalent "supports N domains / N surfaces / N origins" phrasing. This count is structurally ambiguous: "N domains" can mean N distinct hostnames, or N URL surfaces distributed across fewer hosts (e.g. one host serving multiple callback paths). The two readings produce different allowlist configurations, and the gap has already caused a real misconfigured OIDC client. Before the PRD is saved, the AC MUST be rewritten to state the interpretation explicitly — either "N distinct hostnames" or "N URL surfaces across M hosts" (M ≤ N) — with the concrete list of hosts/surfaces enumerated if known at PRD time. Do not let the ambiguous shorthand pass through to `/dr-plan` or `/dr-do`; the disambiguated wording is the one the implementer and `/dr-qa` will hold the change to.
        - **V-AC spec-graph evidence-edge seed.** For every V-AC-N in § Success Criteria, author it so its spec-graph Evidence edge is seedable: pair the `Covers:` binding with the intended verification (planned command / test / measurement) for that criterion. `/dr-do` step 7.6 turns that intent into the concrete `Evidence: V-AC-N — <artifact>` edge as tests are produced, and `spec-graph-gate.sh` verifies the resulting evidence coverage before `/dr-qa`. A V-AC with no seedable evidence path is under-specified — make it verifiable or fold it into a `D-REQ`.
    -   Save to `datarim/prd/PRD-{slug}.md`.

5.5b. **Append-merge expectations checklist (L3-L4, mandatory)** per `$HOME/.claude/skills/expectations-checklist/SKILL.md`:
    -   The checklist file `datarim/tasks/{TASK-ID}-expectations.md` is created by `/dr-init` at Step 4.7. At `/dr-prd`, the architect MUST append-merge any new wishes derived from the PRD § Success Criteria block — never create the file from scratch, and never replace existing operator-derived wishes.
    -   **Source of items.** Each operator wish becomes one item. Derive items from:
        (a) the init-task `## Operator brief (verbatim)` plus every `## Append-log` entry (one wish per distinct intent), and
        (b) the PRD § Success Criteria list (one wish per V-AC where the criterion reflects an operator-observable outcome — internal-only AC stays in PRD).
    -   **Per-item shape** (Option B schema; full contract in `expectations-checklist.md`):
        - title in plain Russian, ending with a period;
        - `wish_id` = kebab-slug of the title (cyrillic allowed);
        - `Что хочу проверить:` one or two sentences; <!-- allow-non-ascii: russian-expectations-field-name-cited-from-canonical-schema -->
        - `Как проверить (success criterion):` one concrete signal; <!-- allow-non-ascii: russian-expectations-field-name-cited-from-canonical-schema -->
        - `Связанный AC из PRD:` `V-AC-<N>` или «—»; <!-- allow-non-ascii: russian-expectations-field-name-cited-from-canonical-schema -->
        - `#### История статусов` with one initial line `<ISO> / <local> · /dr-prd · pending → pending · reason: пункт создан при формировании PRD`; <!-- allow-non-ascii: russian-status-history-section-name-cited-from-canonical-schema -->
        - `#### Текущий статус` set to `pending`. <!-- allow-non-ascii: russian-current-status-section-name-cited-from-canonical-schema -->
    -   **Append-merge if the file already exists.** Load existing items by `wish_id`. New PRD-derived wishes whose slug does not match any existing item are appended at the bottom; existing items are not rewritten. If a previously-linked AC was renamed, append one `stage: append-merge` History line to the affected item.
    -   **Post-write validation gate.** Invoke:
        ```bash
        "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/check-expectations-checklist.sh" --task {TASK-ID}
        ```
        Exit code `1` ⇒ STOP and fix the file before continuing. Exit code `2` ⇒ usage error in the invocation, not in the file.
    -   For `complexity: L1` or `L2` this step is skipped here; `/dr-plan` handles L2 without PRD.

5.5c. **AUTOMATIC SPEC-GRAPH VALIDATION**:
    -   After the PRD and expectations checklist are on disk, invoke:
        ```bash
        "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/spec-graph-gate.sh" \
            --task {TASK-ID} --stage prd --root <repo-root> --format json
        ```
    -   The architect authors stable `D-REQ-NN` headings and L3-L4 V-AC `Covers:` bindings; this gate validates them automatically. Do not ask the operator to run a separate validator.
    -   Exit `2` blocks the stage as a configuration or required-artifact failure. Exit `1` blocks only in explicit hard mode. Advisory findings are summarized before the CTA.

5.5. **Network Exposure Baseline (tiered gate)**:
    -   Read `$HOME/.claude/skills/network-exposure-baseline/SKILL.md` § Tier Model + § Tiered Gate Rules.
    -   Decide gate disposition by invoking the canonical executor:
        ```bash
        decision=$("${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/network-exposure-gate.sh" \
            --task-description datarim/tasks/{TASK-ID}-task-description.md \
            --quiet)
        ```
        Resolve the path to `dev-tools/` via the runtime root (`$HOME/.claude/` symlinks to `code/datarim/`).
    -   Apply the decision:
        -   **`hard_block`** → the PRD MUST include a section titled **«Network Exposure Baseline»** with:
            (a) declared default Tier per port/listener affected by this task
                (`Tier 0` socket, `Tier 1` loopback, `Tier 2` Tailscale, or
                `Tier 3` public);
            (b) for any Tier 3 entry: justification text + `expires` date
                (≤90 days from PRD authorship); and
            (c) explicit acceptance criterion that the verifier
                (`dev-tools/network-exposure-check.sh`) passes against the
                proposed configuration.
            Missing section ⇒ PRD is incomplete, do not advance to `/dr-plan`.
        -   **`advisory_warn`** → include the section if the task touches a
            networking surface; otherwise mention exposure stance in one
            sentence in § Risks. Do not block.
        -   **`skip`** → no PRD section required.
    -   The gate is **fail-closed**: missing or malformed `priority`/`type`
        frontmatter resolves to `hard_block`. Fix the description before
        re-running.

6.  **Backlog Generation** (optional):
    -   Extract actionable items from PRD sections (features, components, migrations, integrations).
    -   **Determine prefix for generated items** per Unified Task Numbering (`$HOME/.claude/skills/datarim-system/SKILL.md`):
        - If PRD is scoped to one project → use that project's prefix.
          <!-- gate:history-allowed -->
          Example: PRD-SUP-0001 → items are `SUP-0002`, `SUP-0003`, ...
          <!-- /gate:history-allowed -->
        - If PRD is cross-project → use area prefix (e.g., `INFRA-NNNN` for infrastructure work)
    -   Scan existing tasks and backlog to determine next sequential number per prefix.
    -   Present to user: "PRD identifies N potential backlog items: [numbered list with proposed IDs, titles, complexity]"
    -   If approved: create entries in `datarim/backlog.md` with status `pending` and a reference to PRD in the description (e.g., `Source: PRD-{ID}`).

6.5. **APPEND Q&A IF ANY** (mandatory per `$HOME/.claude/skills/init-task-persistence/SKILL.md` § Q&A round-trip contract): for every operator clarification round captured during this stage — either operator answer or autonomous agent-decision under FB-1..FB-5 — invoke `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh"` to persist the round into `datarim/tasks/{TASK-ID}-init-task.md § Append-log`.
    -   Write the question and answer (and rationale, when applicable) to temp files first; free-form text MUST come via `--*-file <path>` per Security Mandate § S1 (do not pass operator text as literal CLI strings).
    -   Required flags: `--root <repo-root> --task {TASK-ID} --stage prd --round <N> --question-file <path> --answer-file <path> --decided-by <operator|agent> --summary "<one-line>"`.
    -   When `--decided-by agent`: `--rationale-file <path>` is required and its body MUST contain ≥ 50 non-whitespace characters explaining the choice (best-practice reference, prior archive, FB-rules link).
    -   On contradiction with an expectation: add `--conflict-with <wish_id>` (+ optional `--conflict-detail-file`); CTA MUST route work back to `/dr-prd` (current stage — revise discovery) for closure.
    -   Skip the step entirely if no clarification rounds occurred. Utility exit 0 = appended; 1 = IO/validation error; 2 = usage error.

7.  **Output Summary**:
    -   Confirm file location.
    -   List next steps: `/dr-init`, `/dr-plan`.

## Template Structure

The PRD MUST include:
-   **Context & Analysis**: Existing code insights, Constraints.
-   **Technical Approach**: Proposed solution, Alternatives considered (Pros/Cons).
-   **Risks & Mitigation**: Security and technical risks.
-   **Success Criteria**: Measurable outcomes.

## Usage

Run: `/dr-prd "Brief description of the task"`

## /dr-auto Mode (when `DATARIM_AUTO_MODE=1`)

When auto-mode is active (env var `DATARIM_AUTO_MODE=1` AND the matching per-task marker — resolved via `dev-tools/auto-mode-marker.sh resolve --root <workspace> --task-id <TASK-ID>`, per-task `datarim/.auto/<TASK-ID>.mode` with legacy `datarim/.auto-mode-active` fallback — containing this TASK-ID), this command:

1. Consults `${DATARIM_RUNTIME:-$HOME/.claude}/skills/autonomous-mode/SKILL.md` § Question Suppression Ladder ([definition](../skills/autonomous-mode/SKILL.md)) before any `AskUserQuestion` or equivalent operator prompt at this stage.
2. Stage-specific suppression hooks:
   - Step 2 Discovery Interview — each Q resolved through Ladder L1-L4 before falling through to Discovery prompt; business-strategy Qs go straight to L5.
   - Step 4 Consult User gate — proposed approach + alternatives auto-selected if Ladder unambiguous; L5 only for true cross-cutting trade-offs.
3. Discovered gaps → apply L1 Inline Resolution Rule ([definition](../skills/autonomous-mode/SKILL.md)) per `skills/autonomous-mode/SKILL.md`; log in `datarim/tasks/{TASK-ID}-auto-inline-log.md` if applied inline.
4. Hard-gated actions → escalate to operator through Ladder L5; log via `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/append-init-task-qa.sh" --decided-by operator` per `skills/init-task-persistence/SKILL.md` § Q&A round-trip.
5. Mismatch (env var set, marker absent OR marker contains different TASK-ID) → emit single-line warning, treat as non-auto (fail-safe per `skills/autonomous-mode/SKILL.md` § When this skill is active).

## Next Steps (CTA)

After PRD save, the architect agent MUST emit a CTA block ([definition](../skills/cta-format/SKILL.md)) per `$HOME/.claude/skills/cta-format/SKILL.md`.

**Routing logic for `/dr-prd`:**

- PRD approved, L3-4 → primary `/dr-plan {TASK-ID}` (detailed implementation plan)
- PRD approved, L2 → primary `/dr-plan {TASK-ID}` (planning phase)
- PRD approved, L1 → primary `/dr-do {TASK-ID}` (skip planning for trivial fix)
- Backlog items proposed and accepted → mention "N items added to backlog" + primary `/dr-plan {TASK-ID}`
- Always include `/dr-status` as escape hatch

The CTA block MUST follow the canonical format (numbered, one `**рекомендуется**`, `---` HR). Variant B menu when >1 active tasks. <!-- allow-non-ascii: russian-canonical-cta-marker-tokens-cited-from-cta-format-skill -->

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

- `stage`: `prd`
- `command`: `/dr-prd`
- `captured-by`: `agent`
- `recommended-next`: primary CTA option (slash-prefixed `/dr-*` form)

Fail-closed: on non-zero writer exit, emit a single stderr warning line and continue (V-AC-7 contract). Kill switch `DATARIM_DISABLE_SNAPSHOT=1` is handled inside the library; under the switch the writer is a no-op without warning.
