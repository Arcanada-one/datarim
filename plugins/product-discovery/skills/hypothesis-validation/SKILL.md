---
name: hypothesis-validation
description: Use when a product decision depends on an uncertain claim and needs a bounded, falsifiable check.
model: inherit
---

# Hypothesis Validation

Use this method when a product or research decision depends on an uncertain, observable claim. This task-skill inherits the caller's model to follow Datarim's vendor-default assignment policy for structured research and content work. It helps a researcher state what would change their mind and choose a proportionate way to learn. It does not run experiments, grant permission, establish market demand, or make a result transferable beyond its recorded scope.

## When to use it

Use this method after the problem and relevant segment are stated, when a consequential assumption needs a discriminating check. A check can be a desk review, usability task, interview protocol, prototype walkthrough, log analysis, or controlled comparison. Not every test is an A/B test. Select a design that can observe the claim without implying stronger causal evidence than it can provide.

Stop at a draft when the outcome is not observable, the disconfirming observation is missing, required inputs are unresolved, or a necessary side-effect grant is absent. Do not invent probabilities, participant access, observations, or permission. Keep all examples in this skill synthetic.

## Method

1. Map the assumptions that must hold for the proposed decision. For each, state its evidence, uncertainty, consequence if false, and the cheapest safe observation that could change the decision. Prioritize by decision impact and reversibility; do not manufacture precise likelihoods.
2. Write a falsifiable hypothesis for one segment and context. Specify a measurable prediction or explicit qualitative observation rule, the measurement unit, an alternative explanation, and an observation that would disconfirm it. List assumptions and applicability limits. An aspiration such as “improve the experience” is not test-ready.
3. Draft an experiment protocol against the exact hypothesis revision. Preregister the method, sampling and recruitment constraints, analysis unit, primary and secondary outcomes, sample rule, threshold-to-decision map, exclusions, missing-data rule, stopping rule, duration and budget caps, privacy disclosure, raw observation format, and analysis-code pin. State `side_effect_grant: none` unless a separate grant is supplied and checked; the template's `grant_ref: null` records no grant and authorizes no action.
4. Review the method and the observation path. Freeze the protocol before collecting observations. A frozen protocol is an immutable plan, not execution authorization. If any planned field changes after freeze, create a new protocol revision with `supersedes` pointing to the exact prior revision and digest; retain the prior bytes. Never silently edit a frozen revision.
5. Analyze only supplied observations that resolve through exact raw references. Confirm the protocol and analysis-code pins, enumerate expected and received units, and preserve missing, excluded, and invalid rows explicitly. Report raw counts before rates or model-generated interpretation.
6. Apply only the frozen decision map. Set a hypothesis to `supported`, `refuted`, or `inconclusive` with linked observation evidence and bounded cohort/context limits. Missing required observations always produce `inconclusive`; they are never imputed as successes or treated as proof of no effect. Model prose may explain the arithmetic but cannot replace or alter it.

## Hypothesis states

Follow the `hypothesis-card` template and its contract:

- `draft`: shape or inputs are incomplete; no evidence claim follows.
- `test_ready`: the prediction, alternative, disconfirming observation, assumptions, unit, and applicability are explicit. This means falsifiable, not supported.
- `under_test`: the exact hypothesis is linked to an accepted, frozen protocol and observations are being gathered under separately authorized execution.
- `supported`, `refuted`, or `inconclusive`: a bounded result from the pinned protocol and referenced observations. A changed conclusion requires a superseding revision, not an edit to the old result.

Do not advance a state because a protocol was drafted or frozen. The structural artifact checker validates fields and references; it cannot establish that a source is semantically adequate or that an observation was honestly recorded.

## Protocol freeze

Use the `experiment-protocol` template as-is. Record a finite sample rule and a stop rule that can be applied without interpreting model prose. A sample rule can be a fixed number of cases, a coverage condition, or a justified qualitative stopping condition. It need not be a statistical power calculation when the method is descriptive. Specify whether randomization applies; when it does not, state why and limit causal claims accordingly.

Before freeze, check that each outcome has a raw observation format, the missing-data rule cannot turn missing into success, exclusions are defined in advance, the budget and duration are bounded, and the decision map includes conditions for `supported`, `refuted`, and `inconclusive`. `grant_ref: null` and `side_effect_grant: none` mean no side-effect authority. Do not recruit, contact, spend, publish, deploy, or otherwise act under this skill.

## Deterministic analysis

Use the rules in [analysis-rules.md](analysis-rules.md). Include a raw observation reference for every count used in a conclusion. If references are absent, unresolved, or do not cover the frozen sample rule, reject the proposed analysis as unsupported; where required observations are missing, the result is `inconclusive`. Show integer counts and denominators first, then any derived rates and the exact decision-map comparison. Keep model-generated narrative separate from those values.

## Output

Produce a hypothesis card and, when a check is warranted, a linked protocol. For a completed synthetic or authorized analysis, report the protocol revision and digest, observation references, raw counts, calculation, mapped state, and the cohort/context limits. Label synthetic examples as synthetic. Do not claim a live adapter, grant, KC admission, production result, or broad product improvement.

Read [assumption-map.md](assumption-map.md) for the mapping method, [experiment-design.md](experiment-design.md) for preregistration and freeze rules, and [analysis-rules.md](analysis-rules.md) for computation and worked examples.
