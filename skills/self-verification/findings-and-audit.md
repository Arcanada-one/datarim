---
name: self-verification-findings
description: Findings schema, 7 validator rules, severity/category anchors, evidence format, verdict logic, audit-log writer pseudocode. Fragment of `self-verification`; load when emitting or validating /dr-verify findings.
---

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
  type: file_quote | test_output | verified_absence | absent
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

### 8 Validator Rules

1. `category=consistency` ⟺ `drift_subtype` may be set; otherwise `drift_subtype` MUST be absent.
2. `evidence.type=absent` means **no evidence was supplied**; `source` AND `excerpt` MUST be absent → `discarded=true, discard_reason=no_evidence_provided`.
3. `evidence.type=verified_absence` means a required artifact/value was deterministically searched for and confirmed missing; `source` and `excerpt` MUST identify the check/search performed. It is evidence and MUST NOT be auto-discarded.
4. `evidence.type ∈ {file_quote, test_output, verified_absence}` ⟹ `source` AND `excerpt` MUST be present.
5. `excerpt` length ≤200 chars (truncate with suffix `"[truncated]"`).
6. `severity ∈ {high, medium, low}` (strict enum).
7. `ac_criteria` MUST be array (may be empty `[]`).
8. `suggested_fix` length ≤500 chars (optional).

## Severity Anchors

| Severity | Definition | Operator Action | Example |
|----------|------------|----------------|---------|
| `high` | AC violated with verifiable evidence; merge MUST be blocked | Fix before merge / archive | PRD states AC-7 target ≥40%, archive shows 0% measured |
| `medium` | Substantive gap (incomplete coverage / drift) with evidence; threatens DoD | Fix before archive (or document waiver) | AC verification command checks syntax not semantics |
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

`type=absent` → finding logged with `discarded=true, discard_reason=no_evidence_provided`; it is NOT counted in the summary verdict. `type=verified_absence` is retained and counted like other evidence-backed findings.

### Verifiability Rule (post-write)

- `type=file_quote` → audit writer runs `grep -F "<excerpt>" <source>`. Match → `evidence_verified=true`. Mismatch → `evidence_verified=false`, diagnostic `"excerpt not found in source: suspect hallucinated_quote"`. **In v1 do not discard, just warn** — operator triage decides.
- `type=test_output` → no auto-verify in v1 (expensive commands); `evidence_verified=unchecked`.

### Secret Redaction (Appendix A)

Before write, the audit writer scrubs excerpt + source via regex: `(secret|password|key|token|credential)\w*\s*[:=]\s*\S+` → replace value with `<redacted>`. **Best-effort in v1.**

## Verdict Logic

- **BLOCKED:** ≥1 non-discarded finding with `severity=high`
- **CONDITIONAL:** ≥1 non-discarded finding with `severity=medium` AND zero `high`
- **PASS:** only `severity=low` non-discarded findings (or no findings)

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
