---
name: v-ac-axis-split
description: "Pattern guidance — when V-AC group mixes deterministic axis (rule match / shape check / type assertion) and statistical axis (live-rate threshold / SLA percentile / soak distribution), split upfront into two V-AC groups; loaded by /dr-prd and /dr-plan during V-AC generation"
---

V-AC groups must not commingle validation that passes by invariant rule with validation that passes by observed rate. Each axis answers a fundamentally different question.

## Pattern
When a single V-AC group contains both deterministic entries (e.g., "schema matches XSD", "status code is 200") and statistical entries (e.g., "p99 latency < 500ms", "error rate < 1% over 1h"), split into two separate V-AC groups before finalising the specification.

## Why
Deterministic and statistical validity rely on different evidence chains. TUNE-0183 V-AC-14.11 was reclassified from "flaky test" to "design error" precisely because a rate-based pass criterion was grouped with rule-based checks, masking the fact that the deterministic checks always passed while the statistical check was the actual uncertainty source.

## How to apply
1. Identify each V-AC entry as either deterministic (unambiguous rule) or statistical (threshold over a window).  
2. If both axes exist in the same V-AC group, split into V-AC-N (deterministic) and V-AC-M (statistical).  
3. Statistical V-AC MUST cite measurement window, sample size, and confidence interval in its specification.  
4. Deterministic V-AC MUST be tied to bats/spec/grep evidence or an equivalent monotonic assertion.

## Reference case
- TUNE-0183 — V-AC-14.11 reclassification: mixed deterministic + statistical axis caused false confidence.
- Source of truth: `verify-INFRA-0199-soak.md` documents the split pattern and evidence requirements.