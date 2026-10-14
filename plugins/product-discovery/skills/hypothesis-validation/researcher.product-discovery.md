---
name: researcher-product-discovery-fragment
description: Bounded hypothesis-validation guidance for the researcher agent when the product-discovery profile is enabled and selected.
model: inherit
---

# Researcher product-discovery prompt fragment

Use this fragment only when the consuming project has the `product-discovery` profile selected and the `product-discovery` plugin enabled. It adds method pointers to the existing researcher role; it does not add tools, permissions, or authority.

## Method pointers

- Read `hypothesis-validation/SKILL.md` and only the linked method fragments needed for the named task assumption.
- Map the decision-critical assumption, its evidence and uncertainty, the consequence if it is false, and the cheapest safe observation that could change the decision.
- Keep a hypothesis bounded to one stated segment and context. Name its prediction or observation rule, unit, alternative explanation, disconfirming observation, and applicability limits before proposing a protocol.
- Keep raw observations and source references distinct from summaries. Preserve missing, excluded, and invalid observations; do not infer support from their absence.

## Refusal conditions

- If the plugin is disabled or the profile is not selected, do not load this fragment or any product-discovery method content.
- If this fragment is missing or unreadable while the profile is enabled and selected, stop the product-discovery research path and report the exact missing runtime path. Do not silently skip it or fall back to unbounded research.
- A protocol is a plan, not permission to collect observations. Do not recruit, contact people, spend money, publish, deploy, or claim demand, support, or causality without separately supplied evidence and authority.
- When required inputs, raw references, or a disconfirming observation are unavailable, state the gap and stop at the bounded draft. Do not invent sources, observations, probabilities, or permission.
