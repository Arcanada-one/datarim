---
name: edge-case-hunter
description: "Enumerates boundary, degenerate, and failure inputs an artifact does not visibly handle. Sibling of adversarial-review; loaded at /dr-plan and /dr-qa."
current_aal: 1
target_aal: 2
---

# Edge-Case Hunter — Enumerate What the Happy Path Ignores

Most artifacts are written for the case the author imagined. This skill
systematically surfaces the cases they did not: the empty, the maximal, the
concurrent, the interrupted, the malformed. It is the boundary-focused sibling
of `adversarial-review` (whole-artifact attack) and `structure-review`
(organisation and contradiction).

The deliverable is a **checklist of concrete edge inputs**, each tagged
handled / unhandled / out-of-scope-by-design — not a vague "consider edge
cases" note.

## Dimensions to sweep

Walk every dimension; skip one only after stating why it does not apply.

- **Cardinality:** zero items, exactly one, exactly the limit, one over the
  limit, and "very many". Off-by-one lives here.
- **Emptiness / absence:** empty string vs null vs missing vs whitespace-only;
  absent file vs empty file vs unreadable file; a config key set to "".
- **Boundaries of value:** min, max, min−1, max+1, zero, negative, the units
  boundary (bytes↔KB, ms↔s), overflow, precision loss.
- **Ordering & timing:** out-of-order arrival, duplicate delivery, the second
  invocation, the resumed-after-crash invocation, clock skew, timeout at the
  worst moment (mid-write).
- **Concurrency:** two callers racing the same resource, a reader during a
  write, a lock holder that dies, TOCTOU between a check and its dependent action.
- **Malformed & hostile input:** wrong type, injected control characters,
  oversize payload, encoding mismatch, a field that is valid-shaped but
  semantically impossible.
- **Partial failure:** step N of M succeeds then N+1 fails — what is the state,
  and is it recoverable or wedged? (Half-written artifacts are the classic.)
- **Environment:** dependency absent, network down, disk full, permission
  denied, a platform difference (path separators, `flock` availability, locale).

## The identity trap

An edge is only real if it is *distinguishable* — if two "different" inputs
drive byte-identical behaviour, the case is not an edge, it is a duplicate. When
you claim an edge is handled differently, name the observable difference (a
distinct output, a distinct exit code, a distinct log line). An edge you cannot
distinguish in behaviour is either already-covered or a false edge; say which.

## Rank by blast radius, not by novelty

A boring edge that silently corrupts state outranks a clever edge that merely
errors loudly. For each unhandled edge, estimate: does it fail loud (error,
crash — cheap) or fail silent (wrong result, corrupt state — expensive)? Push
silent-failure edges to the top.

## Output

A checklist. One row per edge: `input/state → expected behaviour → status
(handled | UNHANDLED | out-of-scope: <reason>)`. UNHANDLED rows that fail silent
are the report's headline. Feed confirmed UNHANDLED rows back as test cases —
an edge without a test regresses.

## When to load

- `/dr-plan` — while drafting the Validation Checklist, so the plan's tests
  cover boundaries, not only the happy path.
- `/dr-qa` — to check the implementation against the boundary sweep.
- Any parser, allocator, lock, retry loop, or state machine.
