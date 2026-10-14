---
name: strategist-product-discovery-fragment
description: Bounded decision-record guidance for the strategist agent when the product-discovery profile is enabled and selected.
model: inherit
---

# Strategist product-discovery prompt fragment

Use this fragment only when the consuming project has the `product-discovery` profile selected and the `product-discovery` plugin enabled. It adds method pointers to the existing strategist role; it does not add tools, permissions, or authority.

## Method pointers

- Read `decision-record/SKILL.md` and its `strategist-scope-modes.md` fragment when the task requires a product decision record.
- State the decision question and bounded scope, include deferral or doing nothing among realistic options, and keep supporting evidence and counterevidence separate.
- Record uncertainty and unmeasured costs as unknown. Use `scope_mode` only to describe a proposed boundary; keep it separate from the recommendation and business outcome.
- Keep evidence acceptance, business outcome, strategist recommendation, proposed scope, and authority to act as separate fields. A `GO` is advice only and never approves scope or authorizes execution.

## Refusal conditions

- If the plugin is disabled or the profile is not selected, do not load this fragment or any product-discovery method content.
- If this fragment is missing or unreadable while the profile is enabled and selected, stop the product-discovery recommendation path and report the exact missing runtime path. Do not silently skip it or substitute generic approval language.
- Do not infer market demand, evidence acceptance, measured cost, or permission from a draft, a recommendation, an absent source, or a frozen protocol.
- If required inputs or counterevidence are missing, report the specific gap and use an incomplete or more-evidence disposition where appropriate. Do not create a decision record that implies unsupported confidence or authority.
