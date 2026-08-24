---
name: customer-delivery
description: Enforce delivery from a verbatim requirement through pre-work knowledge selection, production evidence, and disposition; excludes enabling-only closure.
---

# Customer Delivery

A user-facing requirement is delivered only when a verbatim customer statement
flows through pinned knowledge, an implementation delta, red/green evidence, a
merged revision, a deployed revision, live production evidence, and an explicit
operator visual disposition — in that order, with no missing edge.

Enabling artifacts — tools, documentation, tests, CI runs, ledger entries,
receipts — support closure but never substitute for it.

## U1. Verbatim atomic requirements

- Store every customer remark verbatim; a paraphrase is metadata, never the
  source of truth.
- Decompose each remark into atomic, stable Requirement IDs.
- Corrections are append-only: record the superseding statement and retain the
  superseded one.

**Fail** if a requirement cites a paraphrase, an aggregate summary, or an
unstable ID as its origin.

## U2. Acceptance tuple

Every Requirement ID carries:

- originating source and exact quotation;
- affected product and surface or route (surface class);
- locale, viewport, and theme dimensions when applicable;
- observable before-state and required after-state;
- evidence method and responsible owner;
- applicable role, skill, blueprint, constraint, policy, and success criterion;
- delivery task, code/content paths, and target environment;
- customer disposition: pending, accepted, rejected, or superseded;
- visibility classification: enabling or visitor-visible;
- receipt pointer to its coverage receipt.

Bind expectations through schema v4 by declaring `customer_derived` on every
wish. A `true` declaration carries the Requirement ID, surface class,
visibility, and receipt pointer; a `false` declaration carries none of those
four fields.

At least one acceptance criterion must assert an observable visitor-facing
change on the live production product. A rendered test-environment comparison
is mandatory supporting evidence but cannot replace the live result.

**Fail** if a user-facing requirement is satisfied only by knowledge,
documentation, test, CI, or ledger output.

## U3. Pre-work knowledge pinning

- The applicable knowledge is selected before implementation starts. Before
  `implementation_started_at`, the issued contract pins current
  admissible revisions of the applicable role, skill, blueprint, constraint,
  policy, and success criterion — each with an immutable revision, digest, and
  timestamp.
- `Gap` or `Unbound` may authorize research or capability creation but may
  never be represented as blueprint-applied product delivery.
- Selection after implementation start is post-hoc attribution and fails.

**Fail** if any required knowledge kind is missing, `Gap`/`Unbound` stands in
for a delivery-bound contract, or a revision is selected after work began.

## U4. Coverage receipt

Emit a machine-readable acyclic mapping per delivery:

`Requirement -> selected knowledge revisions -> implementation delta ->
red/green evidence -> merged revision -> deployed revision -> live evidence ->
customer disposition`

- A missing edge means `NOT MET`.
- Receipts are deterministic and mutation tested: removal of any required edge
  must turn the gate red.

**Fail** on a cycle, a missing edge, a mutable revision reference, or a receipt
that cannot fail when an edge is removed.

## U5. Closure semantics

A user-facing task or epic cannot close while:

- any originating customer review is open or changes-requested;
- any required live evidence is absent;
- production is behind the accepted revision; or
- operator visual acceptance is pending.

Executable rules, not guidance:

- `green CI != deployed`
- `deployed != visually accepted`
- `enabling work != customer outcome`

Epic state is derived from the Requirement graph and child acceptance states,
never from an independently authored prose status.

**Fail** if a task closes on CI, merge, or internal review alone.

## U6. Review-to-evolution

Classify every review finding exactly one of:

`ABSENT`, `WEAK`, `STALE`, `MIS_SCOPED`, `NOT_BOUND`, `NO_CANON_CHANGE`

- The first five require an artifact revision or new artifact plus a
  red-capable enforcement change.
- `NO_CANON_CHANGE` requires evidence and reviewer approval.
- Evolution never replaces the associated product fix.

**Fail** on a classified finding with no enforcement change, an unapproved
`NO_CANON_CHANGE`, or an evolution-only closure of the product requirement.

## U7. Visible-output accounting

Every user-facing epic reports two separately counted lists:

- enabling changes;
- visitor-visible changes.

An epic with zero visitor-visible changes cannot satisfy a user-facing parent
requirement. Narrow enabling tasks may close individually but contribute no
completion weight to the visible outcome.

**Fail** if an epic closes with an empty visitor-visible list, or enabling
weight is counted as visible completion.

## U8. Painted-surface visual acceptance

Capture affected web page classes as painted surfaces across:

- RU and EN;
- mobile and desktop;
- light and dark.

Automated structural, WCAG, overflow, contrast, and mutation checks are
required but cannot replace the operator's visual disposition when the source
requirement is qualitative.

**Fail** if a qualitative requirement closes on automated assertions alone,
without an explicit operator disposition for every required surface cell.

## Hard rules

1. Tools, docs, tests, CI, and ledger output cannot satisfy user-facing
   delivery.
2. `Gap` and `Unbound` authorize research or capability creation only.
3. Post-hoc knowledge attribution fails.
4. Production must match the accepted merged revision.
5. Operator-only approvals remain operator-only: prepare evidence and stop at
   the hard gate.

## Definition of met

A user-facing deliverable is met when every originating requirement has a
complete, mutation-tested coverage receipt; every required change is deployed
and live; all originating reviews have evidence-backed dispositions; every
painted-surface cell carries an explicit operator disposition; and the operator
accepts the production result. Anything less is in progress.
