<!-- fd-rule: FD-HANDOFF-TITLE; polarity: inform; semantics: handoff.title -->
# Frontend design handoff and evidence

<!-- fd-rule: FD-HANDOFF-SCOPE; polarity: inform; semantics: handoff.scope -->
Read this reference when completing the pre-code design packet or deciding
whether it may enter implementation.

<!-- fd-rule: FD-HANDOFF-PACKET; polarity: require; semantics: handoff.packet -->
## Minimum handoff packet

<!-- fd-rule: FD-HANDOFF-PACKET; polarity: require; semantics: handoff.packet -->
The packet must identify:

<!-- fd-rule: FD-HANDOFF-PACKET; polarity: require; semantics: handoff.packet -->
- atomic Requirement IDs and verbatim source pointers;
- designer owner, affected product, routes or surface classes, and audience;
- exact reuse inventory and external-research ledger;
- seven-kind gap dispositions and every created or revised artifact;
- content hierarchy, task flow, selected direction, alternatives, and reasons;
- token, typography, component/state, theme, responsive, i18n, accessibility,
  and performance contracts;
- implementation boundaries and code/content owners;
- acceptance methods and the planned production evidence cells;
- the issued Knowledge Contract identifier and validation evidence.

<!-- fd-rule: FD-HANDOFF-PACKET; polarity: require; semantics: handoff.packet -->
Use `${DATARIM_RUNTIME:-$HOME/.claude}/templates/frontend-design-brief.md` and
link supporting artifacts rather than duplicating them.

<!-- fd-rule: FD-HANDOFF-KC-REQUIRE; polarity: require; semantics: handoff.knowledge_contract_gate -->
## Knowledge Contract entry gate

<!-- fd-rule: FD-HANDOFF-KC-REQUIRE; polarity: require; semantics: handoff.knowledge_contract_gate -->
Implementation may start only when all applicable managed kinds are bound to
immutable approved revisions and content digests selected before the recorded
implementation start. Provenance and typed relations must resolve; required
artifacts must pass their independent forward scenarios and meaningful
mutations.

<!-- fd-rule: FD-HANDOFF-KC-FORBID; polarity: forbid; semantics: handoff.invalid_bindings -->
Reject post-hoc attribution, mutable `latest` references, missing digests,
deprecated or rejected revisions, and selection after implementation starts.
`Gap` or `Unbound` may describe why research or artifact creation continues,
but either state makes a delivery-bound contract `NOT_MET`.

<!-- fd-rule: FD-HANDOFF-AUTONOMY; polarity: permit; semantics: handoff.autonomous_first_result -->
No taste-approval checkpoint is required before producing the first strong
design packet when the operator has authorized autonomous execution. This does
not transfer final visual acceptance to the designer.

<!-- fd-rule: FD-HANDOFF-EVIDENCE; polarity: require; semantics: handoff.evidence_matrix -->
## Evidence plan

<!-- fd-rule: FD-HANDOFF-EVIDENCE; polarity: require; semantics: handoff.evidence_matrix -->
For every affected painted surface, plan the full RU/EN x desktop/tablet/mobile x light/dark matrix. That is twelve cells per surface class; any absent cell keeps the Knowledge Contract `NOT_MET` when the matrix is required.

<!-- fd-rule: FD-HANDOFF-EVIDENCE; polarity: require; semantics: handoff.evidence_matrix -->
Each planned cell names locale, viewport dimensions and class, theme, route,
browser/runtime version, source and deployed SHA, screenshot path, structural
checks, accessibility result, performance result where applicable, and
customer disposition state. A screenshot without revision and environment
metadata is not production evidence.

<!-- fd-rule: FD-HANDOFF-AUTOMATION-LIMIT; polarity: forbid; semantics: handoff.automated_acceptance -->
The pre-code packet defines this evidence contract. After implementation,
`frontend-ui` checks implementation hygiene and `playwright-qa` captures
browser artifacts. Automated checks cannot supply qualitative operator
acceptance.

<!-- fd-rule: FD-HANDOFF-OUTCOMES; polarity: inform; semantics: handoff.outcomes -->
## Handoff outcomes

<!-- fd-rule: FD-HANDOFF-OUTCOMES; polarity: inform; semantics: handoff.outcomes -->
- `READY_FOR_CONTRACT`: design packet complete; reusable artifacts validated;
  contract not yet issued or not yet `MET`.
- `READY_FOR_IMPLEMENTATION`: issued contract is `MET`; implementation may
  begin at the recorded timestamp.
- `NOT_MET`: any required binding, relation, lifecycle approval, forward test,
  mutation, locale, viewport, theme, or evidence plan cell is missing.

<!-- fd-rule: FD-HANDOFF-ACCEPTANCE; polarity: forbid; semantics: handoff.customer_acceptance -->
The designer reports one of these states with evidence. The designer never
reports the customer-visible requirement delivered; delivery additionally
requires merged and deployed revisions, live proof, zero-residual review
coverage, and authorized customer disposition.
