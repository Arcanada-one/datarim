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
5. When a V-AC is split, preserve or reassign every `Covers:`, `Verifies:`, and
   `Evidence:` binding so the automatic spec graph remains complete.

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

## Pattern 3: threshold-gate deterministic + statistical split

When a task ships a threshold gate — an abstention gate, a confidence cutoff, a rate limiter, any «if metric `op` constant → branch» control — its acceptance MUST split into two V-AC entries on different axes:

- **Deterministic axis:** does the gate read the *right field* and apply the *right constant*? (e.g. M3 reads `score_kind` and applies a scale-specific τ — `rrf`-scale τ is never compared against a `colbert_rerank`-scale score). Verified by a unit test with hand-picked inputs; falsifiable by a scale-swap test.
- **Statistical axis:** is the *resulting rate* within a documented sane band? (e.g. shadow-mode abstain rate lands in a 5–40% band over a fixed datarim-kb sample). Verified by an eval/shadow script over a representative sample, not a unit test.

### Why
The two axes need different verification tools (unit test vs eval script) and different evidence types (a green assertion vs a measured rate inside a band). Folding them into one V-AC produces false confidence — a gate can apply the correct constant yet abstain on 95% of queries, or land a healthy rate while reading the wrong field. A motivating retrieval-abstention gate split this way — a deterministic V-AC for the field+constant logic plus a statistical V-AC for the resulting abstain rate — produced two genuinely independent, independently falsifiable checks.

### How to apply
1. Identify any V-AC describing a threshold/cutoff/rate gate.
2. Split it: one V-AC asserts the field+constant logic (unit test); one asserts the resulting rate is inside a documented band (eval script).
3. For shadow-first gates, the statistical band may be calibrated against a real shadow run — document the band and sample size in the eval script header at `/dr-do`, not deferred indefinitely.
