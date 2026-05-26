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

## Pattern 2: gate-activation axis dry-run

When a task ships a new validator gate, or flips an existing gate from advisory to fail-hard (the «gate-activation axis»), `/dr-plan` Component Breakdown MUST include a validator dry-run row enumerating every file that currently fails under the gate's invocation `--scope`. Any file the PRD declares Out-of-Scope but that falls under the gate's `--scope` MUST be either (a) rewritten in-task or (b) explicitly waived with a documented `--scope` reduction in the plan.

### Why
A validator-activation task that defers files under the same scope is self-blocking — the gate runs against the deferred files at `/dr-archive` time and rejects the archive that activated it. Sizing the gate scope in plan-time absorbs the surprise into the rewrite plan or shrinks the gate to match the rewrite, rather than discovering the contradiction inside `/dr-archive`.

### How to apply
1. Identify any V-AC that activates a validator gate (`--scope X,Y,Z` in the gate's invocation surface).
2. Run the gate against each declared scope in dry-run mode during `/dr-plan` Phase 4.
3. List every failing file in the Component Breakdown.
4. For each failing file: classify as (rewrite-in-task) or (waiver-shrinks-scope). PRD Out-of-Scope declarations that conflict with the gate scope MUST be resolved one of these two ways — not deferred to archive time.
