# Experiment Design

Use the existing `experiment-protocol` template; do not create a competing card. A protocol is a preregistration for a bounded observation plan. It must pin the exact hypothesis revision and specify:

- method, sampling and recruitment constraints, and analysis unit;
- randomization unit or why randomization does not apply;
- primary outcome and any secondary or exploratory outcomes;
- sample rule, thresholds and a decision map for supported, refuted, and inconclusive;
- exclusions, missing-data handling, and a stopping rule;
- duration and budget caps, privacy/disclosure, and raw observation format;
- analysis-code pin when available, source references, and protocol revision lineage;
- `side_effect_grant: none` unless a separate, applicable grant is independently supplied. The template's `grant_ref` is a reference only and never grants authority.

Choose the method before choosing a metric. A usability walkthrough can answer whether a task path is findable; it cannot by itself establish a population conversion rate. An interview can surface explanations, not prevalence. A desk review can test whether supplied records contain a claim, not whether the claim is true. Use an A/B comparison only when the question, assignment, sample, and outcome support that design.

## Freeze and amendments

While `status: draft`, revise the plan as needed. Before observations begin, review the protocol inputs and freeze it by using `status: protocol_frozen`. Hash and retain the frozen bytes. Freeze does not authorize collection or side effects.

After freeze, any change to a method, outcome, sample, exclusion, threshold, missing-data rule, stopping rule, privacy terms, or analysis code pin requires a new revision. Increment `revision`, preserve the prior artifact, and set `supersedes` to its exact ID, revision, and digest. The new revision is a new plan; do not retroactively apply it to observations collected under the old plan. Record the change and its reason. Do not silently edit frozen bytes or relabel the old plan as draft.

## Synthetic fixture protocol

The fixtures use a fixed eight-row synthetic comparison: four rows per variant, one binary primary outcome, and a predeclared descriptive rule. Raw observations are compact, key-sorted JSON Lines; each line has its own exact-byte digest reference. The method is deterministic and has no participants, random sampling, outreach, or external effects. The example's `grant_ref` is null and its side-effect grant is none. These choices demonstrate only how to write a bounded protocol; they are not universal sample-size or decision-threshold recommendations.
