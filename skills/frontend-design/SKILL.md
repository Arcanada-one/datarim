---
name: frontend-design
description: Design a research-backed pre-code packet for rendered customer-facing frontend work; excludes backend, implementation, and final acceptance.
metadata:
  current_aal: 1
  target_aal: 2
---

<!-- fd-rule: FD-SKILL-TITLE; polarity: inform; semantics: scope.title -->
# Frontend Design

<!-- fd-rule: FD-SKILL-SCOPE; polarity: inform; semantics: scope.definition -->
Use this skill before product code when a task creates or materially changes a
rendered customer-facing surface. It turns atomic customer requirements into a
designer-owned design packet and a Knowledge Contract-ready handoff. It does
not implement HTML/CSS/components, capture final browser evidence, or grant
customer acceptance.

<!-- fd-rule: FD-SKILL-EXCLUDES; polarity: forbid; semantics: scope.exclusions -->
For backend-only, data-only, infrastructure-only, or non-rendered work, do not invoke this skill.
Content-only work uses this skill only when hierarchy, layout, interaction, or
visual treatment changes materially.

<!-- fd-rule: FD-SKILL-INPUTS; polarity: require; semantics: inputs.required -->
## Required inputs

<!-- fd-rule: FD-SKILL-INPUTS; polarity: require; semantics: inputs.required -->
- Verbatim customer remarks mapped to stable atomic Requirement IDs.
- Affected routes or surface classes, locales, viewport classes, and themes.
- Current product screenshots or renderable source, brand assets, tokens,
  components, content, and known constraints.
- The applicable project authority, lifecycle, and Knowledge Contract rules.

<!-- fd-rule: FD-SKILL-ASSUME; polarity: permit; semantics: inputs.sparse_assumptions -->
If an input is sparse, make the smallest safe assumption that preserves the
customer's stated outcome, label it, and continue. A missing preliminary taste
review is not a routine implementation gate.

<!-- fd-rule: FD-SKILL-SEQUENCE; polarity: require; semantics: workflow.pre_code_sequence -->
## Pre-code sequence

<!-- fd-rule: FD-SKILL-SEQUENCE; polarity: require; semantics: workflow.pre_code_sequence -->
Perform these steps in order and preserve their evidence:

<!-- fd-rule: FD-SKILL-SEQUENCE; polarity: require; semantics: workflow.pre_code_sequence -->
1. Inventory reusable artifacts in the product, its design system, the Datarim
   runtime, and the applicable knowledge graph. Record exact paths, revisions,
   digests, lifecycle state, and reuse/modify/create/reject disposition.
2. Research the unresolved design questions with current primary standards,
   official documentation, and strong maintained reference implementations.
   Record URL, UTC access date, authority, applicability, selected use, and
   rejected alternatives in `INSIGHTS-{TASK-ID}.md`.
3. Analyze gaps across all seven managed kinds: `Role`, `Skill`, `Blueprint`,
   `Constraint`, `SuccessCriterion`, `Policy`, and `CapabilityDescription`.
   `Competency` is not a managed kind; express competency-shaped needs through
   `CapabilityDescription`, `provides`, and pinned dependency relations.
4. Create and validate every missing reusable artifact. Run its schema,
   frontmatter, lifecycle, provenance, relation, forward-scenario, and mutation
   checks before any product implementation.
5. Issue the Knowledge Contract with immutable artifact revisions and digests,
   pre-work timestamps, requirement bindings, and red-capable evidence.
   Product code is forbidden until the contract is `MET`.

<!-- fd-rule: FD-SKILL-BINDING; polarity: forbid; semantics: binding.invalid_states -->
`Gap` and `Unbound` authorize research or artifact creation only. They cannot
be delivery bindings. Never select an artifact after implementation starts and
present the selection as if it governed that implementation.

<!-- fd-rule: FD-SKILL-PACKET; polarity: require; semantics: design.packet -->
## Design packet

<!-- fd-rule: FD-SKILL-PACKET; polarity: require; semantics: design.packet -->
The designer owns the following pre-code decisions:

<!-- fd-rule: FD-SKILL-PACKET; polarity: require; semantics: design.packet -->
- visitor, primary task, first-screen promise, trust evidence, and ordered
  content hierarchy;
- primary and secondary actions with visible outcomes;
- two or more viable directions when the choice is material, with a selected
  direction and explicit reasons;
- semantic design tokens and component states for light and dark themes;
- responsive behavior for desktop, tablet, and mobile, including keyboard,
  pointer, and touch intent;
- RU/EN semantic parity and realistic long-copy stress behavior;
- accessibility and performance constraints expressed as observable criteria;
- a route/surface evidence plan covering the complete required matrix.

<!-- fd-rule: FD-SKILL-PACKET; polarity: require; semantics: design.packet -->
Use `${DATARIM_RUNTIME:-$HOME/.claude}/templates/frontend-design-brief.md` for
the reusable packet structure.

<!-- fd-rule: FD-SKILL-DISCLOSURE; polarity: require; semantics: routing.progressive_disclosure -->
## Progressive disclosure

<!-- fd-rule: FD-SKILL-DISCLOSURE; polarity: require; semantics: routing.progressive_disclosure -->
- Read `references/decision-contract.yaml` before routing or handoff. It is the
  deterministic authority for activation, stage order, ownership, evidence
  axes, and safe conflict resolution; prose may explain but never override it.
- Read `references/design-decisions.md` when choosing hierarchy, visual
  direction, tokens, responsive behavior, theme behavior, i18n treatment,
  accessibility, or performance constraints.
- Read `references/handoff-and-evidence.md` when assembling the design packet,
  checking Knowledge Contract readiness, or handing work to implementation and
  browser QA.

<!-- fd-rule: FD-SKILL-HANDOFF; polarity: inform; semantics: routing.post_contract -->
After the contract is `MET`, route implementation hygiene to
`skills/frontend-ui/SKILL.md` and browser capture to
`skills/playwright-qa/SKILL.md`. Those skills verify implementation and output;
they do not replace this pre-code design decision surface.

<!-- fd-rule: FD-SKILL-BOUNDARY; polarity: forbid; semantics: completion.customer_acceptance -->
## Completion boundary

<!-- fd-rule: FD-SKILL-BOUNDARY; polarity: forbid; semantics: completion.customer_acceptance -->
This skill completes when the design packet is internally consistent, all
missing reusable artifacts are validated, and the issued Knowledge Contract is
`MET`. The designer may recommend a direction but MUST NOT claim customer or
operator acceptance. Final qualitative disposition remains with the authorized
operator after production evidence exists.
