---
task_id: TUNE-0561
artifact: creative
stage: design
title: "Exact unique-violation classification before domain-result mapping"
captured_at: 2026-08-02
captured_by: /dr-design
agent: architect
status: decided
schema_version: 1
consilium: false
references:
  - reflection-MUN-0020.md
  - reflection-MUN-0021.md
  - skills/testing/SKILL.md
  - skills/compliance/SKILL.md
---

# TUNE-0561 · Exact Unique-Violation Classification Before Domain-Result Mapping

## Context

Two independent tasks — MUN-0020 and MUN-0021 — mapped a database unique-violation
error family (`UNIQUE constraint violation` / SQLSTATE `23505` / Prisma `P2002`)
to a domain-level semantic outcome (version race / stale write). In both cases the
code caught the broad error family and inferred a domain meaning without
identifying *which* unique constraint fired. A collision from an unrelated
unique constraint — a different column, a different index — produced the same
domain label. The defect class is:

```
incident_class: broad-unique-violation-as-stale
```

MUN-0021 repeated this error class after MUN-0020 had already recorded it,
satisfying the anti-self-suppression trigger. The recurrence demonstrates that
developer judgment alone, without a structural gate, does not prevent
over-broad classification.

## Decision

**Domain-result mapping for unique violations is allowed ONLY when:**

1. The error object identifies the **exact intended named unique constraint**
   (PostgreSQL: `constraint_name` field in the error detail; Prisma: `meta.target`
   field containing a constraint or index name), OR
2. The error object identifies an **exact normalized column signature** — a set
   of column names, normalized to sorted order, that matches the declared unique
   constraint columns exactly (set equality — not subset, not superset, not
   partial overlap).

**Failing cases (MUST remain infrastructure errors — no domain mapping):**

- An unknown explicit constraint name. Its presence wins over any column
  metadata and fails immediately; a caller may not fall back to columns.
- A missing explicit name and missing column metadata.
- Partial column overlap (the error carries columns `[A, B]` but the declared
  constraint is on `[A, B, C]` — superset on the error side).
- Subset column match (error carries `[A, B, C]` but the declared constraint is
  on `[A, B]`).
- An unrelated unique constraint fires (any constraint/index name or column set
  different from the declared one). This case MUST produce a distinct, loud
  infrastructure error — not the domain outcome the classification was
  attempting to map.

**Contract shape (interface pseudocode — binding, not implementation):**

```
classify_unique_violation(error, declared_constraint):
    if error.constraint_name is present:
        return match if error.constraint_name == declared_constraint.name
        else raise InfrastructureError (unrelated constraint fired)
    if error.column_signature is present:
        normalized = normalize_as_column_set(error.columns)
        if normalized == normalize_as_column_set(declared_constraint.columns):
            return match  (exact set equality)
        elif normalized & declared_constraint.columns is non-empty:
            raise InfrastructureError (partial overlap — ambiguous)
        else:
            raise InfrastructureError (unrelated columns)
    raise InfrastructureError (insufficient metadata to classify)
```

## Rejected Alternatives

### Alternative A — Broad family catch with best-effort domain label
*Rejected.* This is the twice-repeated incident. A `UNIQUE constraint violation`
catch without constraint identification silently misclassifies unrelated
collisions. The cost of over-broad classification is wrong domain semantics
shipped as a "version race" when the real failure is a duplicate insert on an
unrelated column.

### Alternative B — Log-and-degrade: treat all unique violations as infrastructure
errors, never map to domain.
*Rejected.* Too conservative. Named-constraint matching and exact column-set
matching are deterministic and safe. The contract preserves them while
blocking the ambiguous middle.

### Alternative C — Allow partial column overlap when the overlapping columns
are a prefix of the declared constraint.
*Rejected.* A prefix match on the error side (error carries `[A]`, constraint is
on `[A, B]`) is ambiguous — the error could be from a different constraint that
also includes column `A`. Only exact set equality resolves the ambiguity.

### Alternative D — Allow Prisma `meta.target` as a single field name without
normalized column-set comparison.
*Rejected.* Prisma `meta.target` is an array of field names when the constraint
is composite; a single-field match must still be an exact set equality against
the declared constraint's column list. A single field name that happens to match
one column of a composite constraint is ambiguous.

## Enforcement Points

### 1. Unit-test boundary gate (language-agnostic rule)

Every domain-result mapping of a unique violation MUST carry runtime-shaped
unit tests for its actual driver error form (`23505`, Prisma `P2002`, or the
equivalent) and a boundary test through the mapping seam. Every mapping needs
the intended positive and unrelated-violation negative. The remaining cases
are mandatory for each metadata form the classifier accepts:

- **Positive test:** feed the classifier a mock error carrying the exact
  declared constraint name → classifier returns the mapped domain outcome.
- **Positive test (by column):** feed a mock error carrying the exact normalized
  column signature → classifier returns the mapped domain outcome.
- **Negative test (unrelated constraint name):** feed a mock error carrying a
  different constraint name → classifier raises an infrastructure error, NOT
  the domain outcome.
- **Negative test (unrelated column set):** feed a mock error carrying a
  different, non-overlapping column set → classifier raises an infrastructure
  error.
- **Negative test (partial overlap):** feed a mock error carrying a column set
  that partially overlaps the declared constraint → classifier raises an
  infrastructure error.
- **Negative test (missing metadata):** feed a mock error with no constraint
  name and no column metadata → classifier raises an infrastructure error.

The applicable positive and negative tests together form the
**unique-constraint classification gate**. Missing either core case, or a
shape-specific case for an accepted metadata form, is a hard QA/Compliance
FAIL.

### 2. Real-database integration test (when metadata depends on driver/schema)

When the classification logic depends on driver behavior — Prisma's
`meta.target` shape, PostgreSQL's `constraint_name` in the error detail object,
or similar runtime metadata — the gate additionally requires:

- **One real-database test per declared unique constraint** that exercises the
  actual driver's error shape. Insert a duplicate row that violates the exact
  declared constraint, catch the error, and assert the classifier maps it
  correctly. This proves the driver actually includes the metadata the
  classifier depends on.
- **One real-database test that exercises an unrelated unique constraint on the
  same table** (a different column with its own unique index). Insert a
  duplicate that violates the unrelated constraint, catch the error, and assert
  the classifier raises an infrastructure error. This proves the classifier
  discriminates between constraints in the real driver's error shape.

Mock-only tests satisfy neither the boundary proof nor the integration proof
when classification depends on driver- or schema-provided metadata. Missing
required real-database proof is a fail-hard QA and compliance result.

### 3. QA gate (/dr-qa Layer 4)

The QA contract inspects unique-violation catch blocks (`23505`, `P2002`,
`UniqueConstraintViolation`, `DuplicateKeyException`, etc.). For each hit:

- Verify the two core cases and every applicable metadata-shape case exist and
  pass.
- Verify real-database tests exist and pass (if the driver/ORM is involved).
- On missing tests: Layer 4 → **FAIL** → BLOCKED → `/dr-do`.

The gate runs whenever a change introduces or modifies domain mapping for a
unique violation.

### 4. Compliance gate (/dr-compliance Step 4)

Compliance re-runs the classification proof and additionally verifies:

- No `PASS_WITH_NOTES` carryover on a mock-only unique-violation mapping.
- The negative unrelated-constraint test includes at least one test case where
  the unrelated constraint lives on the same table (the most dangerous
  blind-spot case — same table, same error family, wrong constraint).

### 5. Mutations that broaden classification

The regression mutation deliberately broadens the classifier to the error
family alone, ignoring exact name/signature identity. The unrelated unique
violation test MUST then fail. If it remains green, the gate has not proved the
boundary. A legitimate new mapping still requires its own positive case and
the unrelated negative case.

## Acceptance Criteria

| AC | Criterion | Verification |
|----|-----------|--------------|
| AC-1 | The exact-name/exact-normalized-column rule is documented in `skills/testing/SKILL.md`. | Static contract test |
| AC-2 | `/dr-qa` and `/dr-compliance` both fail hard on missing positive, unrelated-negative, boundary, or conditionally required integration proof. | Static wiring test and review |
| AC-3 | Runtime-shaped `23505` or `P2002` unit evidence plus a mapping-boundary test is required. | QA evidence inspection |
| AC-4 | Broadening classification to the error family alone makes the unrelated-violation test fail. | Mutation proof |

## Rollback

This decision can only be rolled back through an **explicit superseding ADR**
that (a) names this ADR identifier, (b) documents why broad classification is
now safe (new driver metadata guarantees, new framework-level constraint
discovery, etc.), and (c) is approved through the same review cycle. Casual
waiver in a task's QA notes or a one-line "skip this check" in a checker
invocation is not a valid rollback.

## References

- `reflection-MUN-0020.md` — first occurrence of `broad-unique-violation-as-stale`
  (unique-violation mapped to version race without constraint identification).
- `reflection-MUN-0021.md` — recurrence; Proposal 1 text; anti-self-suppression
  trigger satisfied.
- `skills/testing/SKILL.md` — target for the new gate section.
- `skills/compliance/SKILL.md` — Step 4 enforcement point.
- `commands/dr-qa.md` — Layer 4 enforcement point.
