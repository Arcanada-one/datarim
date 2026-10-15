---
name: decision-record
description: Record bounded product decisions with counterevidence, uncertainty, and explicit reversal conditions.
model: inherit
---

# Decision Record

Use this method when a product or research question needs an explicit choice under uncertainty. It structures the reasoning and its evidence; it does not establish demand, accept evidence on behalf of an owner, change task scope, or grant authority to act.

Use the [strategist scope-modes fragment](strategist-scope-modes.md) when a strategist recommendation includes a proposed scope boundary.

## Keep three decisions independent

Record these as separate values. Do not infer one from another:

- **Evidence acceptance** says whether the named evidence meets the stated evidence criteria. Use `pending`, `accepted`, `rejected`, or `insufficient`. This describes the evidence review only.
- **Business outcome** says what to do with the question: `continue`, `pivot`, `stop`, or `more-evidence`.
- **Authority to act** says whether a separately authorized actor may perform an action. Default to `status: none` and `authority_ref: null`. A strategist `GO` is a recommendation; it never changes this field or grants execution authority.

The strategist recommendation is recorded separately as `GO`, `NO_GO`, `PIVOT`, `INCOMPLETE`, or `NOT_APPLICABLE`. A recommendation may inform the business outcome, but does not determine evidence acceptance or authority.

## Method

1. State one decision question and the scope it concerns. List realistic options, including deferral or doing nothing when relevant. Give each option a stable ID, a concise description, a disposition (`selected`, `rejected`, or `deferred`), and a reason. Select exactly one option except when the outcome is `more-evidence`, where the selected option may be `null`.
2. Record supporting evidence and counterevidence separately. Pin each reference to its source revision and digest. Do not omit information that weakens the preferred option. For a `GO` recommendation, at least one counterevidence reference is required; if none is available, do not issue `GO` from this record.
3. State uncertainty explicitly, including unknowns, assumptions, measurement limits, and any unmeasured cost of doing nothing. Never turn an unmeasured quantity into zero or a confident estimate.
4. Set the business outcome independently of the strategist recommendation. `more-evidence` identifies the missing evidence and the next bounded observation needed; it does not imply that research has permission to run.
5. State the scope delta, including `none` when the decision changes no scope. A scope delta records a proposal, not an approved change.
6. Write reversal conditions as observable events that would change the decision. Name an owner responsible for monitoring those conditions and revisiting the record.
7. Set `supersedes` to the exact prior record when replacing one, or `null` for the first revision. Preserve the prior record and explain the change in its successor.

## Record and validate

Use the [`decision-record` template](../../templates/decision-record.md) for `product-artifact/2` DecisionRecords. Its strict reader checks required fields, option dispositions, independent status fields, and references. The reader proves structure and local reference integrity only; it does not judge evidence quality, truth, business value, independent acceptance, or authority.

Keep examples synthetic and label them as such. Do not include real customer information or imply that a fixture demonstrates demand or production readiness.
