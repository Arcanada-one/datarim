---
name: self-verification-examples
description: Worked /dr-verify examples — tri-layer canonical, --floor-only fast path, Codex [experimental] fallback. Fragment of `self-verification`.
---

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
