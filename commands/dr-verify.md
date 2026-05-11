---
name: dr-verify
description: Standalone self-verification of a Datarim artifact (PRD/plan/do output). Tri-layer architecture (v2): Layer 1 deterministic floor (shell pipeline, no LLM cost) + Layer 2 cross-model peer-review (DeepSeek via coworker, ~14× cheaper than Sonnet) + Layer 3 native runtime dispatch (Claude 3-agent parallel; Codex single-prompt retained as [experimental] fallback). Findings-only mode.
---

# /dr-verify - Standalone Self-Verification (Tri-Layer)

**Role**: Verifier (orchestrated via self-verification skill)
**Source**: skill `code/datarim/skills/self-verification.md`

## Instructions

1. **LOAD**: Read skill file `~/.claude/skills/self-verification.md` (symlink) или canonical `Projects/Datarim/code/datarim/skills/self-verification.md`. Adopt orchestrator persona.
2. **RESOLVE PATH**: Walk up directories from cwd to find `datarim/`. STOP if not found, tell user to run `/dr-init`.
3. **TASK RESOLUTION**: Apply Task Resolution Rule from `datarim-system.md`. Use resolved task ID for all subsequent steps.
4. **ARGUMENT PARSING**:
   - `{TASK-ID}` mandatory positional arg
   - `--stage={prd,plan,do,all}` optional, default `all`
   - `--max-iter=N` optional, default 3
   - `--no-fix` flag, default ON (findings-only mode)
   - `--floor-only` flag — skip Layer 2 + Layer 3 (deterministic checks only, fastest, zero LLM cost)
   - `--peer-provider={deepseek,moonshot,openrouter,sonnet,haiku,...}` optional. When omitted, provider auto-resolves via 6-step chain in `dev-tools/resolve-peer-provider.sh` (CLI → per-project datarim-config → per-user XDG datarim-config → coworker `--profile code` default → cross-Claude-family subagent → same-model isolated last resort). See skill § Peer Review Provider Resolution.
   - `--runtime={claude,codex}` optional, auto-detect via env (`CODEX_RUNTIME=1` → codex, else claude); affects Layer 3 only
   - `--external-verifier=PASS` optional override (Loop Exit Criteria level 1)
   - `--cost-cap=N` optional token ceiling, default = baseline `/dr-do` tokens × 1.25
5. **CONTEXT GATHERING**: Read артефакты per `--stage`:
   - `prd` → `datarim/prd/PRD-{TASK-ID}.md` + `datarim/tasks/{TASK-ID}-task-description.md`
   - `plan` → `datarim/plans/{TASK-ID}-plan.md` + `creative/creative-{TASK-ID}-*.md` (if exist)
   - `do` → `datarim/qa/qa-report-{TASK-ID}.md` (if exists) + `datarim/tasks/{TASK-ID}-task-description.md` § Implementation Notes
   - `all` → all of above + AC list extracted from PRD
6. **TRI-LAYER DISPATCH** (canonical v2 order — fastest+cheapest first, fail-fast on Layer 1):
   - **6.1 Layer 1 — Deterministic floor.** Invoke `bash code/datarim/dev-tools/dr-verify-floor.sh --task {TASK-ID} --stage {stage} --workspace <project-root>`. Capture JSONL findings on stdout, progress on stderr. Each finding carries `source_layer: "floor"`. If `--floor-only` passed, skip 6.2 and 6.3.
   - **6.2 Layer 2 — Provider resolution + cross-model peer-review.** First invoke `bash dev-tools/resolve-peer-provider.sh [--peer-provider <flag>] [--project-config ./datarim/config.yaml] [--user-config ~/.config/datarim/config.yaml]` to resolve `provider`, `peer_review_mode`, `source_layer` (3 lines on stdout; exit 0 success / 1 invalid / 2 cost-cap). Then dispatch by mode:
     - `cross_vendor` → `coworker ask --provider <p> --profile code --task-id {TASK-ID} --paths <artifact-paths> --question "<adversarial-frame-template>"`
     - `cross_claude_family` → spawn `agents/peer-reviewer.md` subagent (model: sonnet, readonly tools)
     - `same_model_isolated` → fall through to Layer 3 single-prompt loop (or Codex degraded path)
     The `--task-id {TASK-ID}` propagation is **MANDATORY** at all dispatch paths — without it the token-cost tool cannot filter logs by task. Each finding tagged `source_layer: "peer_review"`, `peer_review_provider: <name>`, `peer_review_mode: <enum>`, `peer_review_provider_source_layer: <chain-step-tag>`.
   - **6.3 Layer 3 — Native runtime dispatch.** Branch on `--runtime`:
     - **claude path**: spawn 3 parallel subagents via `Agent` tool (`subagent_type=reviewer`/`tester`/`security`; tool whitelist: Read, Grep, Glob, Bash read-only — **NO** Write/Edit). Each receives self-contained context package. Findings tagged `source_layer: "dispatch"`.
     - **codex path** *([experimental] fallback only — see skill §Runtime-Aware Switch)*: single-prompt loop with canonical adversarial framing.
   - **Findings dedupe across layers**: tuple `(artifact_ref, ac_criteria, category)`. First-source wins in priority order: floor → peer_review → dispatch.
7. **ITERATE**: `max-iter` cap, stop-condition checks per Loop Exit Criteria 4-level hierarchy (skill §5).
8. **WRITE AUDIT LOG**: Append-only file `datarim/qa/verify-{task-id}-{stage}-{iter}.md` per skill §Audit Log Writer pseudocode. Apply `chmod a-w` post-write. Include: validated findings, malformed section, verdict, raw outputs (truncated if >2k chars), and `source_layer_breakdown: {floor: N, peer_review: M, dispatch: K}` summary header field.
9. **EMIT VERDICT**: BLOCKED / CONDITIONAL / PASS per skill §Verdict Logic. CTA per `cta-format.md` (FAIL-routing для BLOCKED).

## Stages

| Stage | Artifacts checked | Validation focus |
|-------|-------------------|------------------|
| prd | PRD + task-description | AC coverage completeness, falsifiability, ≥3 risks с mitigations |
| plan | plan + creative docs | Step coverage (every AC ↔ ≥1 step), security design (STRIDE), rollback explicit |
| do | qa-report + Implementation Notes | Evidence coverage per AC, no orphan AC items, claims supported by output |
| all | all above + cross-artifact diff | All above + drift taxonomy (`scope_creep`, `spec_decay`, `execution_skew`, `orphaned_requirements`) |

## Findings Schema

Refer skill §Findings Schema (canonical YAML block + 7 validator rules + 3 severity anchors + 4 category anchors + 3 evidence types + auto-discard + verifiability + secret redaction).

## Verdict Logic

Refer skill §Verdict Logic:
- **BLOCKED**: ≥1 non-discarded finding with `severity=high`
- **CONDITIONAL**: ≥1 non-discarded finding with `severity=medium` AND zero `high`
- **PASS**: only `severity=low` non-discarded findings (or no findings)

## Audit Log Format

**Path**: `datarim/qa/verify-{task-id}-{stage}-{iter}.md` (append-only, `chmod a-w` post-write)

**Header section**: `task_id`, `stage`, `iter`, `runtime`, `max-iter`, `cost_consumed_tokens`, `started_at`, `finished_at`, `verdict`.

**Findings section**: YAML list per finding with all schema fields + post-write metadata.

**Malformed section** (if any): list of agent-emitted findings that failed schema validation, raw form preserved.

**Raw outputs** (truncated if >2k chars): per-agent raw response для audit trail.

## Loop Guard

If same finding emerges on **3 consecutive iterations** with same `artifact_ref` + `ac_criteria` + `category` — flag as `persistent_finding` и exit with `verdict=BLOCKED`. Prevents infinite-loop bug.

## Re-entry After Fix

После `/dr-do` (or manual operator fix) addressing findings:
- Re-run `/dr-verify {TASK-ID} --stage=<stage>`
- Previous audit log preserved for trail; new file gets `-v2`, `-v3` suffix
- Findings should diminish (recall@previous-findings = how many fixed)

## Constraints

- **Stack-agnostic** mandate. All three layers run identically under any runtime; Layer 2 vendor-neutral via coworker abstraction.
- **`--peer-provider` is now an override, not a default.** Provider auto-resolves via `dev-tools/resolve-peer-provider.sh` chain when flag is omitted. Backward-compat preserved: legacy `--peer-provider deepseek` invocation remains valid as chain step #1 (`source_layer: cli_flag`).
- **Read-only** subagent tool whitelist (Read, Grep, Glob, Bash read-only). **NO** Write, Edit, NotebookEdit at all layers.
- **Cost budget cap**: `--cost-cap=N` (default 1.25× baseline `/dr-do`). If Layer 2 + Layer 3 combined cost exceeds cap, warn operator and continue (do not auto-degrade — operator decides).
- **Append-only audit log** (`chmod a-w` post-write).
- **Findings-only mode**: NO automatic fix application. Operator triage all findings вручную.
- **`coworker --task-id <ID>` propagation MANDATORY** at Layer 2 — otherwise downstream token-cost measurement (`dev-tools/measure-invocation-token-cost.sh`) cannot filter logs by task.

## Examples

### Example 1: Tri-layer canonical (Claude runtime, default)

```
$ /dr-verify {TASK-ID} --stage all --max-iter 2 --peer-provider deepseek
[Loading skill self-verification]
[Detecting runtime: claude (default)]
[Reading PRD + plan + creative + qa-report for {TASK-ID}]
[Layer 1 — floor] dr-verify-floor.sh --task {TASK-ID} --stage all
  → 2 findings (medium, safety, check_name=shellcheck)
  → exit 0 (no high-severity, proceed)
[Layer 2 — peer_review provider=deepseek]
  coworker ask --provider deepseek --profile datarim --task-id {TASK-ID} ...
  → 1 finding (medium, correctness, peer_review_provider=deepseek)
[Layer 3 — dispatch runtime=claude]
  3 parallel agents: reviewer / tester / security
  → reviewer: 1 finding (completeness)
  → tester: 0 findings
  → security: 0 findings
[aggregate] union 4 findings → dedupe → 4 unique
  → verdict: CONDITIONAL (0 high, 4 medium)
  → source_layer_breakdown: {floor: 2, peer_review: 1, dispatch: 1}
  → audit: datarim/qa/verify-{TASK-ID}-all-1.md (chmod a-w)
Final verdict: CONDITIONAL (operator triage required)
```

### Example 2: --floor-only (fast pre-merge dogfood, zero LLM cost)

```
$ /dr-verify {TASK-ID} --stage do --floor-only
[Layer 1 — floor] dr-verify-floor.sh --task {TASK-ID} --stage do
  → 0 findings, exit 0
[Layer 2 — peer_review] SKIPPED (--floor-only)
[Layer 3 — dispatch]    SKIPPED (--floor-only)
Final verdict: PASS (deterministic floor clean; no LLM verification performed)
```

### Example 3: Codex CLI [experimental] fallback

```
$ /dr-verify {TASK-ID} --stage all --runtime codex
[Layer 1 — floor]  → 0 findings (runtime-agnostic)
[Layer 2 — peer_review provider=deepseek]  → 1 finding (correctness)
[Layer 3 — dispatch runtime=codex] [EXPERIMENTAL fallback]
  single-prompt loop with adversarial framing
  → 1 finding (completeness)
[aggregate] 2 unique findings post-dedupe
Final verdict: CONDITIONAL
```

### Example 4: Zero-flag UX (resolution chain auto-resolves)

```
$ /dr-verify {TASK-ID} --stage prd
[Layer 1 — floor]  → 0 findings
[resolve-peer-provider]
  no --peer-provider flag
  no ./datarim/config.yaml
  no ~/.config/datarim/config.yaml
  coworker --profile code default → deepseek
  → provider=deepseek, mode=cross_vendor, source_layer=coworker_default
[Layer 2 — peer_review provider=deepseek mode=cross_vendor]
  coworker ask --provider deepseek --profile code --task-id {TASK-ID} ...
  → 1 finding (medium, correctness)
[Layer 3 — dispatch runtime=claude]  → 0 findings
[aggregate] 1 unique finding
  → verdict: CONDITIONAL
  → audit: datarim/qa/verify-{TASK-ID}-prd-1.md
    peer_review_provider: deepseek
    peer_review_mode: cross_vendor
    peer_review_provider_source_layer: coworker_default
```

If neither config nor coworker is set up (greenfield onboarding), chain step #5 dispatches `agents/peer-reviewer.md` (model: sonnet) — covered by Claude subscription, no external API key required:

```
$ /dr-verify {TASK-ID} --stage prd
...
[resolve-peer-provider]
  no flag, no config, no coworker
  → provider=sonnet, mode=cross_claude_family, source_layer=fallback_subagent
[Layer 2 — peer_review provider=sonnet mode=cross_claude_family]
  spawn agents/peer-reviewer.md (readonly: Read, Grep, Glob)
  → 2 findings (medium, completeness + safety)
...
```

## Transition Checkpoint

Before exiting `/dr-verify`:
- [ ] Skill loaded and persona adopted?
- [ ] Audit log written to `datarim/qa/verify-{task-id}-{stage}-{iter}.md`?
- [ ] `chmod a-w` applied?
- [ ] Verdict (BLOCKED/CONDITIONAL/PASS) emitted?
- [ ] CTA per `cta-format.md`?

## Next Steps (CTA)

After verdict, MUST emit CTA block per `$HOME/.claude/skills/cta-format.md`.

**Routing logic for `/dr-verify`**:
- **PASS / CONDITIONAL** → primary `/dr-compliance {TASK-ID}` (proceed to final hardening) или `/dr-archive {TASK-ID}` если already compliance done
- **BLOCKED** — FAIL-Routing variant per highest-severity-category map:

| Highest finding category | Return Command (primary in CTA) | Rationale |
|--------------------------|---------------------------------|-----------|
| safety (any severity) | `/dr-design {TASK-ID}` | Security/safety gap requires re-design |
| correctness | `/dr-do {TASK-ID}` | Factual claim violations — fix code/evidence |
| completeness | `/dr-plan {TASK-ID}` or `/dr-prd {TASK-ID}` | Missing artifact piece — re-plan or re-spec |
| consistency | `/dr-plan {TASK-ID}` | Cross-artifact drift — sync plan/code |

Multi-category BLOCKED: route to earliest pipeline stage affected (PRD > plan > do).

The FAIL-Routing CTA header MUST read: `**Verify failed для {TASK-ID} — verdict: BLOCKED, highest severity: high, category: <X>**`.

Variant B menu when >1 active tasks в `activeContext.md`.

**ARGUMENTS**: `{TASK-ID} [--stage={prd,plan,do,all}] [--max-iter=N] [--no-fix] [--runtime={claude,codex}] [--external-verifier=PASS] [--cost-cap=N]`