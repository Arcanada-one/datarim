---
name: v-ac-axis-split
description: "Pattern guidance: split V-AC groups mixing deterministic axis (rule match) and statistical axis (rate threshold); loaded by /dr-prd and /dr-plan."
---

V-AC groups must not commingle validation that passes by invariant rule with validation that passes by observed rate. Each axis answers a fundamentally different question.

## Pattern
When a single V-AC group contains both deterministic entries (e.g., "schema matches XSD", "status code is 200") and statistical entries (e.g., "p99 latency < 500ms", "error rate < 1% over 1h"), split into two separate V-AC groups before finalising the specification.

## Why
Deterministic and statistical validity rely on different evidence chains. A pipeline-level retrospective reclassified a mixed V-AC entry from "flaky test" to "design error" precisely because a rate-based pass criterion was grouped with rule-based checks, masking the fact that the deterministic checks always passed while the statistical check was the actual uncertainty source.

## How to apply
1. Identify each V-AC entry as either deterministic (unambiguous rule) or statistical (threshold over a window).  
2. If both axes exist in the same V-AC group, split into V-AC-N (deterministic) and V-AC-M (statistical).  
3. Statistical V-AC MUST cite measurement window, sample size, and confidence interval in its specification.  
4. Deterministic V-AC MUST be tied to bats/spec/grep evidence or an equivalent monotonic assertion.

## Reference case
- A pipeline-level retrospective on a V-AC entry where a mixed deterministic + statistical axis caused false confidence.
- A soak-test verification document captures the split pattern and evidence requirements.