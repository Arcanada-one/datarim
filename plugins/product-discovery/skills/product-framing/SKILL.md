---
name: product-framing
description: Structure a bounded product opportunity inquiry and preserve evidence limits.
model: inherit
current_aal: 2
target_aal: 2
---

# Product Framing

Use this skill only when the product-discovery pack is enabled and selected for the task. Work only from the task brief, repository, artifacts and other inputs the caller explicitly supplies. Do not browse, fetch market data, contact people, spend money, publish, deploy or infer demand from absent data. If an input is missing or unavailable, record that state; it does not mean no evidence exists.

Apply the source-family, duplicate, counterevidence, conflict-group, availability, and publication-date rules in [Claim Quality](claim-quality.md). Preserve distinct source records when sources conflict; never combine them into one neutral or majority claim. A source family records common origin, while a duplicate group explicitly groups records that repeat that origin. `unavailable` means the source could not be accessed or checked; it does not mean a completed search found nothing. Use `published_at: null` when publication time is unknown, and do not infer it from retrieval or observation time.

## Modes and routing

Choose one mode from the declared stage. Ask one question at a time, then **STOP and wait** before asking another. Skip a question only when declared inputs already answer it; name the input that answered it.

- **Startup diagnostic** for a pre-product idea, an idea with users, or one with paying customers. Route questions by stage in `startup-diagnostic.md`.
- **Builder brainstorm** when there is working software, a prototype, or a concrete capability to explore. Use `builder-brainstorm.md`; generate possibilities before evaluating the narrowest testable wedge.
- If both descriptions apply, first ask which decision is needed now and STOP; do not blend modes by default.

After the selected mode, use the premise challenge and alternatives in `premise-challenge.md`. Challenge the problem and the proposed solution, not the person. Do not praise, flatter, lead toward a preferred answer, or present speculation as a finding. Explain what input would change a judgment.

## Evidence and actors

Keep user, buyer and payer distinct. Describe the current workflow, its cost, status quo, substitutes and any distribution assumptions using declared inputs only. Unknown values remain unknown; an unavailable source is not a negative finding. A statement reported by a user is `user-reported`; it is never independently `observed` merely because it is specific, repeated, roleplayed, quoted, or written into a synthetic fixture. Mark synthetic evidence explicitly and never promote it to real demand.

## Output

Create an opportunity brief before a research protocol. Capture uncertainty and the next discriminating action. A complete structure does not establish truth, demand, semantic source quality, or permission to act. Use existing task acceptance and evidence gates for completion; artifact labels never authorize spending, contact, publication, deployment, or delivery.

Produce one `opportunity-brief` conforming to the installed `opportunity-brief` template and structural checker. Keep evidence claims with their kind and traceable references, separate assumptions and unknowns, include at least two distinct build alternatives plus an explicit **Stop / do nothing** option, and name the next discriminating action. The action must distinguish between the live alternatives and use only declared or subsequently authorized inputs. A stop recommendation must state its rationale and counterevidence; do not manufacture certainty to force a decision.

The brief records an inquiry and its limits. It does not establish semantic adequacy of sources, independently observed demand, market size, acceptance, authority, or permission to act.

## Fragments

- Startup diagnostic: [startup-diagnostic.md](startup-diagnostic.md)
- Builder brainstorm: [builder-brainstorm.md](builder-brainstorm.md)
- Premise challenge and alternatives: [premise-challenge.md](premise-challenge.md)
