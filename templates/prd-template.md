# PRD: {Title}

**Task:** {TASK-ID}
**Status:** Draft
**Created:** {date}
**Complexity:** Level {1-4}

> **Frontmatter `ships_in:` derivation rule.** When a PRD ships a framework / library release, the `ships_in:` value MUST be derived from the current `VERSION` file (or equivalent canonical version source) at PRD-draft time, not from operator memory. `/dr-prd` Step 1 reads the current version and pre-fills `ships_in: <next-minor>` for feature PRDs (or `<next-patch>` for hotfix). Manual override requires an inline justification line. Drift between PRD `ships_in:` and the actual release version is a recurring defect class (precedent: PRD shipped citing an older release number while the framework had advanced two minor versions).

## Discovery Summary
(Output from discovery interview -- key decisions, constraints, requirements)

## Problem Statement
(What problem are we solving? Who is affected?)

## Scope
### In Scope
### Out of Scope

## Context Analysis
(Existing code insights, constraints, dependencies)

## Technical Approach
### Selected Approach
### Alternatives Considered
(For each: description, pros, cons, why rejected)

## Consilium Summary (L3-4 only)
(Panel composition, key debates, resolution)

## Risks & Mitigation
| Risk | Impact | Mitigation |
|------|--------|------------|

## Requirements (D-REQ)

Addressable requirements for the spec-traceability graph. Each requirement gets a
stable two-digit machine id `D-REQ-NN` (unique per document). The heading may
carry a human-readable description after the id; the id token itself is
fixed-width. V-AC items bind to these ids with a `Covers:` line (see below), so
`dr-spec-lint` can resolve the path `wish_id → D-REQ → V-AC → plan-step →
evidence`. `wish_id` (expectations-checklist) stays the canonical operator-intent
id — `D-REQ` is an addressing layer on top, not a replacement.

#### D-REQ-01: {requirement description}

#### D-REQ-02: {requirement description}

## Success Criteria
- [ ] (Measurable outcomes)

> **V-AC `Covers:` binding (spec‑traceability).** On L3+ tasks each V-AC item
> MUST carry a `Covers:` line naming the `D-REQ` id(s) it verifies, for
> example `Covers: D-REQ-01, D-REQ-02`. Every referenced id MUST resolve to a
> declared `D-REQ` above. The pipeline validates this automatically through
> `spec-graph-gate.sh` at PRD and downstream stages. A `D-REQ` referenced by no
> V-AC is flagged as an orphan. See `documentation/reference/validator-contract.md` and
> `documentation/explanation/spec-traceability-rollout.md`.

> **Falsifiability requirement:** every quantitative AC (coverage %, latency budget, RPS, token delta, line count, etc.) MUST cite a concrete verification command and its exit-code contract inline — for example: `"${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/measure-foo.sh" --check` returns exit 0. No «presumed met» verdicts at QA / Compliance. If the measurement tool does not yet exist, declare its creation as part of the plan; do not approve the AC until it is falsifiable. See `skills/evolution/SKILL.md` § Pattern: Split-Architecture Metrics for the absorption-task variant.

> **V-AC path live-validation gate.** Every AC / V-AC verification line that cites a script, binary, spec file, or path MUST be live-validated before PRD approval — at minimum a `command -v <bin>` / `test -f <path>` / dry-run-with-exit-code probe. Phantom-path cites (script that does not yet exist, spec file under a wrong directory, renamed-but-still-cited binary) are an archive blocker for `/dr-prd` Step 5. If the cited tool is intentionally produced by the plan, mark it `[to-be-created]` inline so QA / Compliance treats absence as expected during pre-implementation review. Precedent: a PRD shipped with 2 phantom-path cites that survived through QA and only surfaced at Compliance, forcing an extra patch round.

## Next Steps
