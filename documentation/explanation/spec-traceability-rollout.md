# Spec-Traceability Rollout (advisory-first)

The spec-traceability layer (`D-REQ` addressing + `dr-spec-lint` graph
validation) is introduced **advisory-first**. It never flips to a hard gate on
the whole corpus on day one — doing so would turn the entire legacy backlog red
at once for no proportional benefit. The activation order below is the
contract; the rule registry (`dev-tools/dr-spec-rules.yaml`) and the validator
flags encode it.

## Activation order

1. **Dry-run the whole corpus.** Run `dr-spec-lint --dry-run` across existing
   PRD/plan artefacts. The graph is built, nothing is reported, exit is `0`.
   This proves the parser handles the real corpus without raising noise.
2. **Baseline + legacy-debt inventory.** Run advisory and capture findings as a
   baseline. Pre-existing findings on untouched legacy artefacts are *debt*,
   tracked as a separate migration, not a blocker on current work.
3. **Advisory window.** Existing pipeline stages invoke
   `spec-graph-gate.sh` automatically. Findings are visible, but the adapter
   exits `0`. No operator command is required.
4. **Hard gate — explicit activation.** Set
   `DATARIM_SPEC_GRAPH_MODE=hard`. The adapter enforces only the graph edges
   whose artefacts should exist at the current stage. Canonical current-task
   workflow artefacts stay in scope even though `datarim/` is gitignored; Git
   diff narrows tracked implementation files only.
5. **Legacy debt — separate tracked migration.** Bringing the historical corpus
   into compliance is its own backlog item, not folded into feature work.

## Complexity-level policy

| Level | Spec-graph enforcement |
|-------|------------------------|
| **L1** Quick Fix | Skipped entirely — no `D-REQ` graph expected. |
| **L2** Enhancement | Advisory only (format/uniqueness/resolution errors surfaced, not gated). |
| **L3+** Feature/Major | Hard-gated **after** the transition window, scoped to changed artefacts. |

This maps to the `applies_to:` field in `dev-tools/dr-spec-rules.yaml`: the full
`graph-complete-l3` rule applies to `[L3, L4]`; format/resolution rules apply
from `L2` upward but are advisory at L2.

## Automatic stage matrix

| Stage | Required graph surface |
|-------|------------------------|
| PRD | wishes, D-REQ ids, V-AC ids, `Covers:` |
| Plan | PRD surface plus explicit `Verifies:` plan edges |
| Do | plan surface plus explicit `Evidence:`; advisory always |
| QA | full graph plus QA evidence |
| Compliance | full graph plus compliance confirmation |
| Verify | requirements appropriate to the requested verify stage |

Engine regressions run in the existing Bats CI. Consumer repositories that
commit workflow artifacts may add their own automatic CI adapter later; Datarim
does not ship a separate manual-dispatch workflow or hook-install ceremony.

## Relationship to existing gates

The spec graph answers **reference resolution** (does every requirement bind to
a V-AC, plan step, and evidence?). It does **not** replace:

- **expectations-checklist** — operator intent (`wish_id` stays canonical).
- **V-AC** — acceptance criteria semantics.

Both stay canonical; `D-REQ` is an addressing layer on top of them, not a
replacement. When the deterministic graph lint and an LLM gate disagree, the
graph lint owns reference resolution and expectations owns operator intent —
both remain mandatory.
