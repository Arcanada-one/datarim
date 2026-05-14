---
name: self-verification
description: "Orchestrator for runtime-aware self-verification (manual /dr-verify). Tri-layer: deterministic shell, peer-review, runtime dispatch."
runtime: [claude, codex]
current_aal: 1
target_aal: 2
---

## Purpose & When to Apply

- Manual `/dr-verify {TASK-ID}` invocation — cold-path skill loaded on-demand.
- Verifies pipeline artifact (PRD / plan / do-output / archive) на: factual correctness, AC coverage completeness, cross-artifact consistency, security/safety gaps.
- **НЕ** замена `/dr-qa` (manual single-agent post-completion review без runtime-aware dispatch).
- **НЕ** автоматический pipeline hook (manual on-demand only — automated post-step hook is a future evolution gated by dogfood verdict).

## When NOT to Apply

- L1 trivial tasks (skill overhead больше value).
- Already archived tasks (immutable artifacts).
- During `/dr-prd` / `/dr-plan` / `/dr-do` active session — use post-completion only (pre-emptive verify hook is a deferred future evolution).

## Core Concepts (5 Gap Protocols)

### 1. State-Diff (light v1)

Сравнение указанного артефакта vs AC list per-stage. Heuristic comparison, no NLP:

- **prd** → grep AC list, проверить что каждый AC имеет (a) verification command или test, (b) success criterion measurable.
- **plan** → grep step list, проверить что каждый AC mapped к минимум 1 plan step.
- **do** → grep evidence sections, проверить что каждый AC имеет evidence (test output / file_quote / artifact reference).

### 2. Per-Phase Validation Schemas

Stage-specific gates:

- **prd-stage:** AC coverage completeness, falsifiability requirement (each AC has concrete verification cmd), risk identification (минимум 3 risks с mitigations).
- **plan-stage:** Step coverage (каждый AC ↔ минимум 1 step), security design (STRIDE coverage), rollback strategy explicit.
- **do-stage:** Evidence coverage per AC, no orphaned AC items, claims supported by verifiable output (not 'logged' alone).

### 3. Single-Prompt Loop Mechanics (Codex path)

**MIXED verdict** from Step 1 validation (`datarim/qa/codex-path-validation.md`): Codex single-prompt path работает **ТОЛЬКО** с canonical adversarial framing. Без adversarial frame — silent false-PASS observed (29 completion tokens, empty findings). Adversarial framing → 3 substantive findings, all schema-compliant, verbatim quotes.

**Canonical adversarial frame template (MANDATORY, не optional):**

```
You are an ADVERSARIAL reviewer. Your job: find weaknesses, NOT bless the doc.
This artifact claims X is 'done' — but real software always has gaps. You MUST find at least 2 substantive concerns.
Look HARD at:
1. AC verification commands — semantic correctness vs syntax check (e.g. grep -c X file confirms text, NOT semantic)
2. DoD claims — logged-but-not-test-run patterns (claims with no actual run output)
3. Reflection coverage — narrating success vs surfacing root cause
4. Followup spawns — silently moved must-fix issues
5. Reproducibility — re-verifiable from scratch by outsider
6. Out-of-scope drift — exceeds PRD scope или quietly drops PRD items

Output ONLY valid JSON matching findings schema. No hallucinated quotes — every excerpt MUST come verbatim from cited source.
```

**Loop:** emit prompt → parse JSON → validate schema (7 rules from creative doc) → if `status=FAIL` и `iter < max-iter` → re-emit с findings as context → repeat. Stop on PASS / max-iter / cost ceiling.

### 4. Drift Taxonomy

4 sub-types для `category=consistency` (per creative doc Dim 2):

| drift_subtype | Defines | Example |
|--------------|---------|---------|
| `scope_creep` | Implementation extends past PRD/plan scope | Added file outside Surface Scan |
| `spec_decay` | PRD/plan modified post-approval без re-review trail | PRD version changed silently |
| `execution_skew` | Code/output deviates от plan steps без justification | `/dr-do` ignored Step 4 |
| `orphaned_requirements` | AC declared в PRD but no plan step / no evidence | AC-7 exists in PRD, absent from plan |

### 5. Loop Exit Criteria (4-level hierarchy)

Priority order (first match wins):

1. **`external_verifier`** — operator passes `--external-verifier=PASS` flag (override).
2. **`unanimous_no_findings`** — all dispatched agents return `findings=[]` AND `status=PASS`.
3. **`max_iter`** — iteration count reaches `--max-iter` (default 3).
4. **`cost_ceiling`** — cumulative token cost exceeds `--cost-cap` (default token budget +25% relative to baseline `/dr-do`; per AC-8 PRD).

## Tri-Layer Architecture (canonical)

Verification runs cheapest-first, fail-fast: deterministic shell pipeline → cross-model peer-review (clean external context) → native runtime dispatch (multi-agent or single-prompt). Each layer's findings carry an explicit `source_layer` tag (`floor` | `peer_review` | `dispatch`) so the audit log preserves provenance and dedupe can prefer earlier-layer findings.

**Why three layers:** Huang et al. (ICLR 2024, "LLMs Cannot Self-Correct Reasoning Yet") show that without an external signal, single-model self-correction degrades because of RLHF self-agreement bias. Production AI-coding systems (Aider's `--auto-lint`/`--auto-test`, Cursor BugBot, Replit Agent 3, Anthropic Claude Code Review) converge on the same pattern: deterministic tools first, then a different model as adversarial reviewer, then native runtime dispatch. The previous single-prompt loop ("are you 100% sure?" to the same model) is the least-mature pattern, so it is retained only as `[experimental]` fallback under Codex CLI.

### Layer 1 — Deterministic Floor

Pre-LLM shell pipeline. Implemented in `code/datarim/dev-tools/dr-verify-floor.sh`. Zero LLM cost; runs in ~2-5s for a typical task.

**Sub-checks (heuristic, stack-detected per manifest):**

- **AC coverage grep** — every AC/TV label in `PRD-{TASK-ID}.md` has a verification cue (`Verify:`, backtick command, grep/test/bash/jq nearby). Missing → `severity=medium, category=completeness`.
- **File-touched audit** — files referenced in `plans/{TASK-ID}-plan.md` (backticked paths with known extensions) resolve in workspace. Unresolved → `severity=low, category=completeness` (NEW pre-/dr-do is benign; phantom is the real risk).
- **Test-presence parse** — heuristic manifest detection (`package.json`/`pyproject.toml`/`Cargo.toml`/`go.mod`/`composer.json`/`Gemfile`). Informational only on v1.
- **shellcheck recursive** — runs `shellcheck -S warning` against `dev-tools/*.sh` and `scripts/*.sh`. `error:` → `severity=high`; `warning:` → `severity=medium`.

**Output:** JSONL findings on stdout (one per line), schema fields per §Findings Schema with `source_layer: "floor"`. Stderr carries progress lines (`[check_name] PASS|SKIP|...`).

**Exit code:** count of high-severity findings (capped at 250). Caller (orchestrator) treats non-zero as `BLOCKED` floor and may skip Layers 2/3 to fail fast.

**`--floor-only` flag** on `/dr-verify` short-circuits at Layer 1 — useful for fast pre-merge dogfood when LLM cost is unwanted.

### Layer 2 — Cross-Model Peer-Review

External-model adversarial reviewer with **clean context** (no upstream Claude/Codex history → no self-agreement bias). Vendor-neutral via the `coworker` CLI abstraction:

```
coworker ask --provider {peer-provider} --profile code \
             --task-id {TASK-ID} \
             --paths <artifact-paths> \
             --question "<adversarial-frame-template>"
```

**Provider — resolved via chain (not hardcoded).** See § Peer Review Provider Resolution below for the canonical 6-step chain. The previous «default `deepseek`» behaviour is now chain step #4 (coworker `--profile code` recommended_provider), not a hardcoded literal. CLI override via `--peer-provider={deepseek,groq,openrouter,sonnet,haiku,...}` is chain step #1.

**`--task-id {TASK-ID}` propagation is MANDATORY.** Without it the downstream token-cost tool (`dev-tools/measure-invocation-token-cost.sh`) cannot filter `~/.local/state/coworker/log/<YYYY-MM-DD>.jsonl` records by task. Skill MUST pass it on every Layer 2 invocation.

**Adversarial frame template** is the same as the v1 Codex path (canonical text in §Single-Prompt Loop Mechanics) — DeepSeek receives it verbatim.

**Findings schema:** every record tagged `source_layer: "peer_review"`, `peer_review_provider: <name>`, and `peer_review_mode: cross_vendor|cross_claude_family|same_model_isolated` so audit log preserves which external model produced which finding under which dispatch class.

**Cost guard:** Layer 2 + Layer 3 combined cost is bounded by `--cost-cap` (default 1.25× baseline `/dr-do`). Excess → orchestrator warns operator and continues; auto-degrade is intentionally not done at v2 (operator decides whether to drop Layer 3). Per-step cost-cap probe in chain step #0 of `dev-tools/resolve-peer-provider.sh` (default `PEER_REVIEW_COST_THRESHOLD=$0.10/run`) guards against runaway Sonnet/Haiku invocation specifically.

### Peer Review Provider Resolution

`/dr-verify` invocations without an explicit `--peer-provider` flag (zero-flag UX) trigger a 6-step resolution chain implemented by `dev-tools/resolve-peer-provider.sh`. The chain reads the canonical datarim-config files (per-project then per-user XDG) and the coworker default before falling through to cross-Claude-family or same-model isolated dispatch. Each step emits 3 lines on stdout (`provider`, `peer_review_mode`, `source_layer`) and exits 0; subsequent steps are tried only if the prior step yielded no provider.

| Step | Source | Mode (typical) | source_layer tag |
|------|--------|----------------|-------------------|
| 1 | `--peer-provider <name>` CLI flag (override) | inferred from provider | `cli_flag` |
| 2 | `./datarim/config.yaml` (per-project datarim-config, team-shared) `peer_review.provider` | inferred | `per_project_config` |
| 3 | `~/.config/datarim/config.yaml` (per-user XDG datarim-config) `peer_review.provider` | inferred | `per_user_config` |
| 4 | `coworker --profile code` recommended_provider (parsed from `~/.config/coworker/profiles.yaml`) | typically `cross_vendor` | `coworker_default` |
| 5 | cross-Claude-family subagent — `agents/peer-reviewer.md` dispatched at `model: sonnet` (Claude Code runtime only) | `cross_claude_family` | `fallback_subagent` |
| 6 | same-model isolated last resort — Opus reviewing Opus output (Codex degraded path or final fallback) | `same_model_isolated` | `fallback_isolated` |

**Provider whitelist:** `deepseek | moonshot | openrouter | sonnet | haiku | opus | none`. Unknown values → exit 1 (supply-chain mitigation: malicious PR injecting `provider: typosquat-host` blocked at parse).

**`peer_review_mode` taxonomy (3-tier):**

- **`cross_vendor`** — DeepSeek / Moonshot / OpenRouter via `coworker ask`. Different company, different training run, different RLHF — strongest mitigation of self-agreement bias (Huang et al. ICLR 2024).
- **`cross_claude_family`** (cross-Claude-family) — Sonnet 4.6 reviewing Opus 4.7 output via Claude Code subagent dispatch. Different model checkpoints with different post-training runs, isolated subagent context. Middle tier — covered by Claude subscription (no per-user API key needed). Empirical bias delta vs same-model self-critique remains under measurement in the active dogfood window.
- **`same_model_isolated`** (same-model isolated) — Opus reviewing Opus or Codex single-prompt loop. Same model family, same training distribution. Last-resort fallback only; least-mature pattern (KILL_OR_PIVOT trigger documented in evolution log).

**Per-project vs per-user config precedence:** per-project (D-5) wins on conflict. The helper writes a stderr WARN when both are set with different values; the audit-log records the winning layer in `peer_review_provider_source_layer`.

**Codex CLI degraded mode:** when `CODEX_RUNTIME=1` is set in env, chain step #5 is skipped and step #6 is taken. The helper writes `WARN: Codex runtime detected, falling back to same_model_isolated mode` to stderr (D-4); orchestrator MUST propagate this warning into the audit-log so operator visibility on the degraded path is preserved.

**Audit-log fields written by orchestrator** (added per record):

- `peer_review_provider: <name>` — actual provider used
- `peer_review_mode: <enum>` — taxonomy tag
- `peer_review_provider_source_layer: <enum>` — chain step that resolved

These enable per-mode rate aggregation in `dev-tools/measure-prospective-rate.sh --verify-dir <path>`, which emits `cross_vendor_rate`, `cross_claude_family_rate`, `same_model_isolated_rate` keys for per-mode dogfood measurement.

**Reference contract:** `dev-tools/resolve-peer-provider.sh --help` prints the canonical output schema and exit codes (0 success / 1 invalid provider / 2 cost-cap breach).

#### JSONL emission discipline (Layer 2 reviewer prompts)

Findings are emitted ONLY when a check FAILS or surfaces NEW DRIFT. If a claim is verified and holds, do NOT include a JSONL line for it. The reviewer's job is to surface gaps, not to enumerate everything checked.

**Accepted output shapes:**
- 0 items (all claims valid — silent suppression is correct)
- 1+ items (defects or incorrect-premise findings)

**Rejected output shapes:**
- Entries whose `check_name` says «cleared», «PASS», «verified», «no finding» — these belong outside the JSONL stream (in a final-line summary at most).
- Entries restating an already-confirmed-correct fact as a finding.

**Correct (suppression):** prompt asks «verify F001 cleared»; reader examines lines and concludes claim holds → emit nothing for F001.

**Incorrect (PASS-as-finding):** `{"finding_id":"F004","check_name":"F001 cleared, no finding"}` — the pass entry should not be in the array.

Compress confirmations into the final-line summary `{cleared_iter1: [...], total_new_findings: N}` (or omit if no prior iter to compare). Keeps the audit log signal-dense.

### Layer 3 — Native Runtime Dispatch

Runtime-specific multi-agent or single-prompt verification. Findings tagged `source_layer: "dispatch"`.

#### Claude Code path (canonical)

Default when runtime detected as claude.

1. Load skill `dispatching-parallel-agents` (Datarim runtime; lineage in CHANGELOG).
2. Spawn 3 parallel subagents via `Agent` tool:
   - **reviewer** (model: opus или sonnet): focus correctness + completeness.
   - **tester** (model: sonnet): focus do-stage evidence coverage + reproducibility.
   - **security** (model: opus): focus safety category + Appendix A controls.
3. Каждый subagent получает self-contained context package: `artifact_path`, `ac_list`, `constraints`, `drift_taxonomy_hints`, `adversarial_frame_template`.
4. **Tool whitelist (read-only):** Read, Grep, Glob, Bash (read-only commands grep/wc/test/cat). **NO** Write, Edit, NotebookEdit.
5. Aggregate findings from all 3 streams.
6. Conflict resolution: union findings, dedupe by tuple `(artifact_ref, ac_criteria, category)`. Higher severity wins on collision. Cross-layer dedupe prefers earlier-layer findings (floor → peer_review → dispatch).
7. Iterate per Loop Exit Criteria.

#### Codex CLI path *([experimental] fallback only)*

Conditional: runtime detected as codex (via env `CODEX_RUNTIME=1` or `--runtime=codex`). **Demoted from canonical at v2** — Codex CLI single-prompt self-review hit only 7.7% literal / 15.4% semantic gap-recall on the n=13 dogfood baseline (R-5 KILL_OR_PIVOT trigger). Retained for parity reasons; prefer Layer 2 (cross-model peer-review) on Codex too.

1. Wrap operator-supplied artifact + AC + adversarial frame template (exact text in §Single-Prompt Loop Mechanics).
2. Single-prompt call to LLM (provider per coworker config).
3. Parse JSON output.
4. Validate against schema rules 1-7.
5. Iterate per Loop Exit Criteria.

> Operators on Codex CLI SHOULD invoke `/dr-verify ... --peer-provider deepseek` to get cross-model coverage on top of the single-prompt fallback. Without an explicit flag, `dev-tools/resolve-peer-provider.sh` emits `same_model_isolated` mode + stderr WARN under Codex runtime (chain step #6).

## Findings Schema

```yaml
finding_id: F-<layer>-<n>          # layer ∈ {floor, peer_review, dispatch} OR legacy F-<iter>-<n> for native dispatch
source_layer: floor | peer_review | dispatch   # MANDATORY at v2 — preserves provenance for tri-layer dedupe
artifact_ref: <file:line>
ac_criteria: [AC-N, AC-M]   # array, may be empty
severity: high | medium | low
category: correctness | completeness | consistency | safety
drift_subtype: scope_creep | spec_decay | execution_skew | orphaned_requirements   # OPTIONAL — only when category=consistency
evidence:
  type: file_quote | test_output | absent
  source: <file:line> OR <command-or-test-name>   # required when type ≠ absent
  excerpt: <verbatim text, ≤200 chars>            # required when type ≠ absent
suggested_fix: <optional, free-text ≤500 chars>
check_name: <string>                # OPTIONAL — Layer 1 fills in (ac_coverage_grep, file_touched_audit, shellcheck, ...)
peer_review_provider: deepseek | groq | openrouter | ...   # OPTIONAL — Layer 2 fills in

# Post-write metadata (written by audit logger):
discarded: true | false
discard_reason: no_evidence_provided | parse_error | malformed_evidence
evidence_verified: true | false | unchecked
verified_diagnostic: <optional, free-text>
verified_at: <RFC 3339 / ISO 8601 timestamp>
agent_origin: reviewer | tester | security | codex_single | floor_pipeline | peer_review_external
```

### 7 Validator Rules

1. `category=consistency` ⟺ `drift_subtype` может быть set; иначе `drift_subtype` MUST be absent.
2. `evidence.type=absent` ⟹ `source` AND `excerpt` MUST be absent → `discarded=true, discard_reason=no_evidence_provided`.
3. `evidence.type ∈ {file_quote, test_output}` ⟹ `source` AND `excerpt` MUST be present.
4. `excerpt` length ≤200 chars (truncate with suffix `"[truncated]"`).
5. `severity ∈ {high, medium, low}` (strict enum).
6. `ac_criteria` MUST be array (may be empty `[]`).
7. `suggested_fix` length ≤500 chars (optional).

## Severity Anchors

| Severity | Definition | Operator Action | Example |
|----------|------------|----------------|---------|
| `high` | AC violated с verifiable evidence; merge MUST be blocked | Fix перед merge/archive | PRD states AC-7 target ≥40%, archive shows 0% measured |
| `medium` | Substantive gap (incomplete coverage / drift) с evidence; threatens DoD | Fix перед archive (или document waiver) | AC verification command checks syntax not semantics |
| `low` | Observation / improvement; no AC violation | Optional fix | Function exceeds 50 LOC threshold |

## Category Anchors

| Category | Definition | Example |
|----------|------------|---------|
| `correctness` | Factual claim not supported by evidence | Archive cites commit abc123 but git log returns no such SHA |
| `completeness` | Required artifact piece missing or incomplete | AC-3 has no verification command; PRD lacks risk table |
| `consistency` | Drift between artifacts (multi-source compare) | PRD says max-iter=3, plan says max-iter=5 |
| `safety` | Security / data integrity / rollback gap | Audit log written without `chmod a-w` |

## Evidence Format

| Type | When to Use | Source Format | Excerpt | Auto-Discard |
|------|-------------|---------------|---------|--------------|
| `file_quote` | Cites artifact content | `<file:line>` (e.g., `PRD-{TASK-ID}.md:42`) | Verbatim text ≤200 chars | No |
| `test_output` | Cites command/test output | `<command-or-test-name>` | Stdout excerpt ≤200 chars | No |
| `absent` | No evidence | MUST be empty | MUST be empty | **Yes** |

### Auto-Discard Rule

`type=absent` → finding logged with `discarded=true, discard_reason=no_evidence_provided`, NOT counted в summary verdict.

### Verifiability Rule (post-write)

- `type=file_quote` → audit writer runs `grep -F "<excerpt>" <source>`. Match → `evidence_verified=true`. Mismatch → `evidence_verified=false`, diagnostic `"excerpt not found in source: suspect hallucinated_quote"`. **На v1 не discard, только warn** — operator triage решает.
- `type=test_output` → no auto-verify на v1 (expensive commands); `evidence_verified=unchecked`.

### Secret Redaction (Appendix A)

Перед write, audit writer scrubs excerpt + source через regex: `(secret|password|key|token|credential)\w*\s*[:=]\s*\S+` → replace value with `<redacted>`. **Best-effort на v1.**

## Verdict Logic

- **BLOCKED:** ≥1 non-discarded finding с `severity=high`
- **CONDITIONAL:** ≥1 non-discarded finding с `severity=medium` AND zero `high`
- **PASS:** только `severity=low` non-discarded findings (или no findings)

## Audit Log Writer (pseudocode)

```
function write_audit_log(task_id, stage, iter, findings, raw_outputs):
    path = "datarim/qa/verify-{task_id}-{stage}-{iter}.md"

    # Step 0. Compute source_layer_breakdown for the audit header (v2 tri-layer)
    source_layer_breakdown = {"floor": 0, "peer_review": 0, "dispatch": 0}
    for f in findings:
        layer = f.get("source_layer", "dispatch")  # legacy v1 findings default to dispatch
        source_layer_breakdown[layer] = source_layer_breakdown.get(layer, 0) + 1

    # Step 1. Validate each finding against 7 schema rules
    valid, malformed = [], []
    for f in findings:
        if validate_schema(f): valid.append(f)
        else: malformed.append(f)

    # Step 2. Auto-discard type=absent
    for f in valid:
        if f.evidence.type == "absent":
            f.discarded = True
            f.discard_reason = "no_evidence_provided"

    # Step 3. Verify file_quote (re-grep)
    for f in valid:
        if f.evidence.type == "file_quote" and not f.discarded:
            if grep_F(f.evidence.excerpt, f.evidence.source):
                f.evidence_verified = True
            else:
                f.evidence_verified = False
                f.verified_diagnostic = "grep-F miss: suspect hallucinated quote"
        elif f.evidence.type == "test_output":
            f.evidence_verified = "unchecked"

    # Step 4. Secret redaction
    for f in valid:
        f.evidence.excerpt = redact_secrets(f.evidence.excerpt)
        f.evidence.source = redact_secrets(f.evidence.source)

    # Step 5. Compute verdict
    non_discarded = [f for f in valid if not f.discarded]
    if any(f.severity == "high" for f in non_discarded):
        verdict = "BLOCKED"
    elif any(f.severity == "medium" for f in non_discarded):
        verdict = "CONDITIONAL"
    else:
        verdict = "PASS"

    # Step 6. Atomic write + lock — header carries source_layer_breakdown for tri-layer audit
    tmp = path + ".tmp"
    write_yaml(tmp, {
        "task_id": task_id,
        "stage": stage,
        "iter": iter,
        "verdict": verdict,
        "source_layer_breakdown": source_layer_breakdown,    # {floor: N, peer_review: M, dispatch: K}
        "valid_findings": valid,
        "malformed": malformed,
        "raw_outputs": raw_outputs,
    })
    mv(tmp, path)
    chmod(path, "a-w")  # append-only guarantee
```

## Examples

### Example 1: Tri-layer canonical (Claude runtime)

```
$ /dr-verify <task-id> --stage all --max-iter 2 --peer-provider deepseek
[Layer 1 — floor] dr-verify-floor.sh --task <task-id> --stage all
  → 2 findings (severity=medium category=safety check_name=shellcheck)
  → exit 0 (no high-severity, proceed)
[Layer 2 — peer_review provider=deepseek]
  coworker ask --provider deepseek --profile datarim --task-id <task-id> ...
  → 1 finding (severity=medium category=correctness peer_review_provider=deepseek)
[Layer 3 — dispatch runtime=claude]
  3 parallel agents: reviewer / tester / security
  → reviewer: 1 finding (completeness)
  → tester: 0 findings
  → security: 0 findings
[aggregate] union 4 findings → dedupe → 4 unique
  → verdict: CONDITIONAL (0 high, 4 medium)
  → source_layer_breakdown: {floor: 2, peer_review: 1, dispatch: 1}
  → audit: datarim/qa/verify-<task-id>-all-1.md (chmod a-w)
Final verdict: CONDITIONAL (operator triage required)
```

### Example 2: --floor-only (fast pre-merge dogfood, zero LLM cost)

```
$ /dr-verify <task-id> --stage do --floor-only
[Layer 1 — floor] dr-verify-floor.sh --task <task-id> --stage do
  → 0 findings
  → exit 0
[Layer 2 — peer_review] SKIPPED (--floor-only)
[Layer 3 — dispatch]    SKIPPED (--floor-only)
Final verdict: PASS (deterministic floor clean; no LLM verification performed)
```

### Example 3: Codex CLI [experimental] fallback

```
$ /dr-verify <task-id> --stage all --runtime codex
[Layer 1 — floor] (runtime-agnostic)
  → 0 findings
[Layer 2 — peer_review provider=deepseek] (runtime-agnostic)
  → 1 finding (correctness)
[Layer 3 — dispatch runtime=codex] [EXPERIMENTAL fallback]
  single-prompt loop with adversarial framing
  → status=FAIL, findings=[F-dispatch-1]
  → 1 finding (completeness)
[aggregate] 2 unique findings post-dedupe
  → verdict: CONDITIONAL
Final verdict: CONDITIONAL
```

## Stop-Condition Hierarchy (formal)

4-level priority cascade:

1. **`external_verifier`** — operator override (--external-verifier=PASS/FAIL)
2. **`unanimous_no_findings`** — all agents PASS, findings=[]
3. **`max_iter`** reached (default 3)
4. **`cost_ceiling`** exceeded (token budget +25% over baseline)

## Constraints

- **Stack-agnostic mandate.** All three layers run equally under any supported runtime; Layer 2 cross-model peer-review is vendor-neutral via `coworker` abstraction. No runtime-specific API literals.
- **Cost budget:** ≤+25% tokens on manual `/dr-verify` invocation vs baseline `/dr-do`. Layer 1 = ~0 cost; Layer 2 absorbs the bulk via cheap external model; Layer 3 only fires for the most expensive runtime path.
- **Append-only audit log** (`chmod a-w` post-write). Header carries `source_layer_breakdown` for tri-layer provenance.
- **Findings-only mode**: no auto-fix application at any layer. Operator triages all findings manually.
- **Read-only subagents/external calls.** Layer 2 (peer_review) and Layer 3 (dispatch) MUST NOT have Write/Edit/NotebookEdit; they read artifacts and emit findings only.
- **`coworker --task-id` propagation MANDATORY at Layer 2.** Without it the prospective-rate / token-cost tooling cannot filter logs by task.

## Cross-References

Implementation lineage (PRDs, plans, creatives, baselines) is tracked in `docs/evolution-log.md` and `documentation/archive/framework/` — not in this skill body. Reusable upstream skills:

- `dispatching-parallel-agents` (Datarim runtime skill) — parallel-agent fan-out used by Layer 3 Claude path.
- `verification-before-completion` (Datarim runtime skill) — evidence-before-assertion discipline applied to per-finding `evidence_verified` re-grep.

## Status

**Tri-layer canonical** — Layer 1 deterministic floor (no LLM cost) + Layer 2 cross-model peer-review (DeepSeek default) + Layer 3 native runtime dispatch. Findings-only mode at all layers; auto-fix is a separate future evolution gated by FP-rate threshold from prospective dogfood. Manual on-demand only — automated post-step hook is a separate future evolution gated by dogfood verdict (≥1 caught per 5 tasks).

<!-- spec-anchors: state-diff per-phase stop-condition loop exit drift taxonomy ac_criterion -->
<!-- These literal lowercase tokens mirror canonical concept names (sections #1, #2, #5; schema field `ac_criteria` maps to the PRD literal `ac_criterion`). They satisfy the falsifiability grep contract from the parent PRD AC without altering the surface header casing. -->
