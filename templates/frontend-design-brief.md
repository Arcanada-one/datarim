# Frontend design brief: {TASK-ID}

- Owner: designer
- Status: pre-code
- Product and surface classes: {products-and-routes}
- Atomic Requirement IDs: {requirement-ids}
- Knowledge Contract: {K-id-or-not-issued}
- Source revision: {source-sha}
- Created (UTC): {timestamp}

## Customer intent and measurable outcome

Link each design decision to a verbatim customer remark and atomic Requirement
ID. State the visitor, primary task, observable before-state, and required
visitor-visible after-state.

## Reuse-first inventory

| Artifact | Exact path or ID | Revision | Digest | Lifecycle | Disposition | Reason |
|---|---|---|---|---|---|---|
| {artifact} | {path-or-id} | {revision} | {digest} | {state} | reuse/modify/create/reject | {reason} |

## Research and gaps

- Insights record: {INSIGHTS-path-and-revision}
- Seven-kind gap analysis: {gap-analysis-pointer}
- Missing reusable artifacts and validation evidence: {artifact-ledger}

## Content hierarchy and task flow

Describe the first-screen promise, trust evidence, ordered narrative or task
path, primary and secondary actions, and their visible outcomes.

## Alternatives and selected direction

Compare materially different directions against customer task fit, evidence
clarity, brand continuity, accessibility, responsive behavior, i18n,
performance, and implementation cost. Name the selection and rationale.

## Visual system and component states

Record primitive, semantic, and component/state token decisions; typography;
light/dark mappings; forced-colors and reduced-motion behavior; and required
default, hover, focus, active, disabled, loading, error, empty, and success
states.

## Responsive and input behavior

| Surface | Desktop | Tablet | Mobile | Keyboard | Pointer | Touch |
|---|---|---|---|---|---|---|
| {surface} | {behavior} | {behavior} | {behavior} | {behavior} | {behavior} | {behavior} |

## RU/EN content contract

Record semantic parity, representative EN content, real RU stress content,
overflow or reflow decisions, and any human translation review still pending.

## Accessibility and performance constraints

State the applicable WCAG version and level, manual/assistive checks, contrast
pairs, focus/order/reflow requirements, media/font/motion budgets, and
measurable lab or field targets.

## Evidence matrix plan

For each affected surface, enumerate RU/EN x desktop/tablet/mobile x
light/dark. Every cell must name exact dimensions, route, capture environment,
expected assertions, SHA metadata, and disposition owner.

## Knowledge Contract gate

- K_id and issuance record: {K-id-and-path}
- Pinned roles, skills, blueprints, constraints, policies, success criteria,
  and capability descriptions: {revision-digest-bindings}
- Provenance, lifecycle, and relation validation: {evidence}
- Forward-scenario and mutation evidence: {evidence}
- Gate state: NOT_MET / MET

Implementation may start only when the issued contract is `MET`.

## Implementation handoff and later acceptance

Name implementation owners and boundaries. Final customer-visible closure
still requires merged and deployed SHAs, live evidence, zero-residual review
coverage, and the authorized operator disposition; this brief grants none of
those outcomes.
