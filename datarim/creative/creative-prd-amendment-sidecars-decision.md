# ADR: Immutable PRD-Amendment Sidecars — Decision

- **Task:** TUNE-0563 (renumbered from TUNE-0546 on 2026-08-02)
- **Date:** 2026-08-04
- **Status:** Decided
- **Decision:** **DROP** — do not land the recovered sidecar mechanism; uphold the
  standing "prose amendments stay prose" contract in
  `skills/immutability/SKILL.md`.

## Context

An orphaned worktree (`tune-0294-prd-amendment`, HEAD `39a19f4`
"feat: add governed PRD amendments", registered in no ref) carries a complete
machine-validated immutable PRD-amendment implementation absent from
`origin/main`:

- `scripts/lib/prd-amendments.sh` — ~380-line Python-in-bash validator
  (closed 18-key frontmatter schema, SHA-256 parent/predecessor chain,
  operator-decision digest binding, symlink/TOCTOU hardening, read-only
  `.chain` ledger).
- `dev-tools/check-prd-amendments.sh` + `dev-tools/create-prd-amendment.sh`
  (thin CLI validator + locked, no-clobber, fsync'd transactional publisher
  with rollback).
- `templates/prd-amendment-template.md` (closed sidecar schema).
- Wiring into `dr-spec-lint.sh`, `dr-trace.sh`, `spec-graph-gate.sh`,
  `dr-spec-rules.yaml` (new `vac-id-unique` rule), `commands/dr-prd.md`
  (`--amend` flow, Step 0.7), plus a `resolve_prd_file` PRD `-vN` revision
  resolver in `scripts/lib/spec-graph.sh`.
- Three test suites: `prd-amendments.bats` (448 lines),
  `prd-amendment-wiring.bats`, `prd-amendment-spec-graph.bats`.

Current `origin/main` treats amendments as prose only:
`skills/immutability/SKILL.md` § Design Amendment (lightweight L2 appendix
with operator sign-off) and `commands/dr-plan.md` Return-to-Plan amendment.

## Options Considered

1. **LAND (replay-with-review):** port the recovered files onto current main,
   adapt to the drifted spec-graph surfaces, wire into `/dr-prd`, `/dr-plan`,
   `/dr-qa`, land everything in one reviewable commit set.
2. **DROP:** record the rejection permanently so the branch is not
   re-discovered as lost work a third time.

## Decision: DROP

### Rationale

1. **A standing, dated architectural decision already rejects exactly this
   mechanism.** `skills/immutability/SKILL.md` carries the block "Prose
   amendments stay prose — decided 2026-08-02" (landed on main in merged
   PR #325, commit `c33d95b`, 2026-08-02). It explicitly names "a
   machine-readable immutable-sidecar mechanism (validator, creator, template,
   chain ledger, three suites)" — i.e. this branch — and declines it. That
   decision is part of the CURRENT immutability contract, is two days old, is
   evidence-based, and defines its own revisit trigger ("usage, not
   tidiness"). Landing would mean autonomously deleting a ratified evolution
   decision from a shipped skill — contrary to the framework's
   human-in-the-loop rule for evolution.
2. **Zero measured demand.** At decision time the workspace held 274 PRDs and
   zero `§ Design Amendment` sections — the lightweight prose path has never
   once been exercised. Enforcement infrastructure for a workflow with no
   observed usage adds a gate to keep green and a surface to maintain in
   exchange for nothing. Nothing has changed since 2026-08-02 that would
   re-open this: the revisit trigger has not fired.
3. **Storage-layer mismatch.** The mechanism anchors its immutability
   guarantee (read-only 0400 `.chain` ledger, hash-chained sidecars) inside
   `datarim/prd/`, which the framework's two-layer architecture declares
   gitignored, ephemeral, and regenerable. Git tracks no history there, file
   modes do not survive re-materialisation, and fleet sync engines do not
   guarantee mode preservation. A cryptographic append-only chain whose
   substrate is by contract disposable delivers the ceremony of immutability
   without its durability.
4. **Dependency-weight conflict with the validator contract.** The
   implementation is ~600 lines of embedded Python across three scripts. The
   Validation Discipline contract for `dev-tools/` validators is "pure shell,
   no dependencies beyond bash + grep + the framework's own dev-tools".
   Existing spec-graph helpers use python3 only for small JSON plumbing; a
   full security-hardened Python validator (S2 review scope: `os.open` flag
   handling, TOCTOU re-stat loops, symlink walks) is a different order of
   maintenance and audit burden — for an unused feature.
5. **Scope smuggling.** The branch also introduces PRD `-vN` revision
   resolution (`resolve_prd_file`) into every graph consumer — a second,
   independent architectural change current main has deliberately not adopted.
   Landing the bundle would change PRD identity semantics framework-wide as a
   side effect of an amendment feature.

### Credit where due

The recovered implementation is high quality: closed schema, contiguous
digest chain, bounded operator-decision hashing (append-only init-task logs do
not invalidate prior approvals), no-clobber fsync'd publisher with rollback,
and three thorough suites. The rejection is architectural (wrong contract to
strengthen, wrong substrate, no demand), not a quality judgment. If the
revisit trigger ever fires, the orphaned worktree at
`.worktrees/datarim/tune-0294-prd-amendment` (HEAD `39a19f4`) is the reference
implementation to replay — with review, since its base is stale.

## Consequences

- `skills/immutability/SKILL.md` § Design Amendment remains the canonical
  amendment contract (prose, operator sign-off, supersede path).
- The rejection is recorded in `documentation/how-to/evolution-log.md`
  (2026-08-04 entry) so the branch is not re-triaged as lost work again.
- The orphaned worktree directory is intentionally preserved (only copy; no
  ref points at `39a19f4`). Do not delete it; do not re-land it without an
  operator-approved reversal of the 2026-08-02 decision.
- **Revisit trigger (unchanged from the skill):** prose amendments start
  appearing in real PRDs and drift becomes an observed problem.
