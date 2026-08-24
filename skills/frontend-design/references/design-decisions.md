# Frontend design decisions

Read this reference only when a frontend-design task needs concrete design
decisions. Preserve the project's brand and stack; external design systems are
evidence sources, not visual themes to copy.

## Start from the visitor decision

State the visitor, the decision or task the surface supports, the first-screen
promise, and the evidence required to trust that promise. Order content before
decoration. Every primary or secondary action needs a visible outcome and an
owner.

Build the hierarchy from real customer remarks and representative content.
Place proof next to the claim it supports. Separate navigation, explanation,
evidence, action, and status so the hierarchy remains understandable without
color or motion.

## Reuse before replacement

Inspect the current brand assets, tokens, typography, layout primitives,
components, states, and page patterns at exact source revisions. Reuse or extend compatible tokens, components, and page patterns before proposing replacements.
Record what is reused unchanged, extended, replaced, or rejected and why.

A current design system is a constraint and an asset, not automatic proof that
the requested surface is already designed. Reject a pattern only for a named
requirement conflict, accessibility failure, i18n failure, or measured product
constraint.

## Choose a defensible direction

When the brief is sparse, derive a defensible first direction from customer
intent, the reuse inventory, research, and observable success criteria. Do not pause for preliminary taste approval. Expose assumptions, alternatives, and
reasons so later feedback can produce a precise follow-up instead of erasing
the first result.

When alternatives are materially different, compare at least two across user
task fit, evidence clarity, brand continuity, accessibility, responsive
behavior, i18n risk, implementation cost, and performance risk. Select one;
do not blend incompatible directions into an untestable compromise.

## Define semantic visual rules

Prefer a bounded three-layer token model:

1. Primitive scales for color, space, type, radius, elevation, and motion.
2. Semantic roles such as `text-primary`, `surface-raised`, `border-focus`,
   `action-primary`, and `status-danger`.
3. Component/state aliases only where a component needs a distinct contract.

Specify light and dark values for every color role and test contrast against
the actual composited background. Include default, hover, focus, active,
disabled, loading, error, empty, success, forced-colors, and reduced-motion
behavior where applicable. Color must not be the sole carrier of meaning.

Typography must include Latin and Cyrillic glyph coverage, relative units,
deliberate weights and line heights, and a bounded responsive scale. Use
consistent spacing instead of arbitrary one-off values.

## Design responsive and input behavior

Describe content priority and component transformation at desktop, tablet, and
mobile rather than merely scaling a desktop screenshot. Preserve logical DOM
and focus order, visible focus, keyboard operation, touch targets, zoom/reflow,
and reduced-motion behavior. Avoid hover-only information and layout changes
that move essential actions unpredictably.

Use representative EN copy and real RU stress copy before handoff. When the RU
variant no longer fits, redesign the container or flow; do not shrink critical text below the applicable policy. Semantic parity means equivalent claims,
evidence, actions, and states, not only equal translation keys.

## Resolve accessibility and performance conflicts

WCAG 2.2 Level AA is the minimum accessibility baseline unless a stricter
project policy applies. When a requested treatment conflicts with contrast,
keyboard, reflow, motion, or assistive-technology requirements, preserve the customer intent through an accessible alternative and record the constraint and
rationale. Never silently implement a known failure.

Declare performance-aware design constraints before implementation: critical
content priority, image dimensions and formats, font strategy, animation
budget, script or interaction cost, and measurable lab/field targets where the
product can support them. A score alone is not a design rationale, and lab
evidence does not become production field evidence.
