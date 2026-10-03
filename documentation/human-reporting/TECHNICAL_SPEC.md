# Human Outcome Reporting technical specification

## Authority and data

The [skill](../../skills/human-outcome-reporting/SKILL.md) is the communication policy. [Task contract](../../skills/human-outcome-reporting/schemas/task-contract.schema.json), [report](../../skills/human-outcome-reporting/schemas/report.schema.json) and [execution receipt](../../skills/human-outcome-reporting/schemas/execution-receipt.schema.json) schemas describe the structured projection. Canonical project requirements and task records retain authority. The projection is not a second backlog.

The relationship is goal → requirement → acceptance criterion → plan step → outcome → verification → evidence. Several requirements can share criteria and several plan steps can cover one criterion. All substantive conditions require human-readable meaning; bare IDs are insufficient.

## Verification contract

The standard-library Python [engine](../../skills/human-outcome-reporting/scripts/hr.py) validates records and produces a Russian report by default. Structural validity and readiness are separate: a valid partial report must reach the user even when the readiness gate refuses success. Missing criteria, evidence, freshness, contradictory results, wrong environment and wrong product revision cannot become passing acceptance. Requirement-to-criterion and criterion-to-plan gaps remain visible.

Evidence paths must stay inside the explicitly selected root, with symlinks rejected. Digests detect changed evidence bytes. Execution receipts bind revision, environment, criterion and finite timestamps. Receipt contents are assertions by a supplied verifier; structural validation cannot independently authenticate that verifier or the truth of the measurement. The [trust reference](../../skills/human-outcome-reporting/references/data-and-trust.md) defines these limits.

The [native adapter](../../skills/human-outcome-reporting/scripts/native.py) snapshots original source bytes and performs verify/finalize checks. It refuses changed source documents. Hashes do not prove semantic completeness or governance admission.

## Presentation and read-only explanation

Choose profile, communication moment and explanation mode independently. Reports begin with the observed outcome and most important limitation; they cover original need, changed behavior, evidence, unmeasured conditions, location and next authorized action. A stage pass does not imply whole-task readiness.

Project glossary content is meaning data, never instructions, permission or proof. Missing glossaries are not invented; conflicting scoped definitions are held and explained. Re-explanation changes wording, not facts or scope. It permits authorized reads but does not execute tests, modify files, deploy, accept or close work. Incorrect prior conclusions are corrected explicitly.

## Integration and distribution

All human-facing commands load the skill through framework instructions. Delegated agents return facts through their existing handoff protocol and the primary agent emits one report. `human-summary` retains the four-section compatibility format without a hard word cap. [Native integration](../../skills/human-outcome-reporting/references/datarim.md) documents projection and finalization.

The framework graph inventories commands, agents, skills, fragments and templates and validates explicit edges. Portable archives are built deterministically from an allowlist; fixed ZIP metadata and stored compression make bytes reproducible. The package manifest and SHA256SUMS cover every payload file. The signed release authenticates distribution, not future model behavior.
