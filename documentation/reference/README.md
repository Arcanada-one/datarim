# Reference — Information-Oriented Documentation

Reference documentation is for precise lookup. The reader already knows what
they are after and needs a trustworthy, complete, compact answer. Content is
structured — tables, lists, signatures, schemas — with no teaching and no
rationale.

## When to write here

- Catalogues of shipped artefacts: agents, skills, commands.
- CLI signatures — flags, arguments, exit codes.
- Schemas and contracts: configuration keys, validator contracts, findings shapes.
- Classification tables and standards mappings.

## When NOT to write here

- A first end-to-end learning experience → [`tutorials/`](../tutorials/)
- A recipe for accomplishing a task → [`how-to/`](../how-to/)
- Motivation, rationale, or architectural trade-offs →
  [`explanation/`](../explanation/)

## Naming convention

Kebab-case `.md` filenames named after the subject, for example `agents.md`,
`standards-mapping.md`.

## Contents

| File | What it catalogues |
|------|--------------------|
| [`language-preferences.md`](language-preferences.md) | Language keys, precedence, resolver and native limits. |
| [`agents.md`](agents.md) | Every shipped agent — role, tier, primary stages, consilium panels. |
| [`skills.md`](skills.md) | Every shipped skill — type, model, purpose, and what loads it. |
| [`commands.md`](commands.md) | Every `/dr-*` slash command with arguments and outputs. |
| [`cli.md`](cli.md) | The standalone `datarim` CLI — subcommands, flags, environment. |
| [`complexity.md`](complexity.md) | The L1-L4 complexity levels and the pipeline each one routes through. |
| [`standards-mapping.md`](standards-mapping.md) | Security-baseline clusters mapped to ASVS, SOC 2, ISO 27001, and CIS. |
| [`validator-contract.md`](validator-contract.md) | The contract every `dev-tools/check-*.sh` validator must satisfy. |

### Saved CLI input manifests

| File | What it covers |
|------|----------------|
| [`cli-input-manifest.md`](cli-input-manifest.md) | Hash selected files and follow the saved-manifest workflow. |
| [`cli-input-manifest-select.md`](cli-input-manifest-select.md) | Select declarations from a saved manifest. |
| [`cli-input-manifest-merge.md`](cli-input-manifest-merge.md) | Merge saved declarations and handle conflicts. |
| [`cli-input-manifest-diff.md`](cli-input-manifest-diff.md) | Compare two saved manifest declarations. |
| [`cli-input-manifest-verify.md`](cli-input-manifest-verify.md) | Verify selected current bytes against a saved declaration. |
| [`cli-input-manifest-conflicts.md`](cli-input-manifest-conflicts.md) | Inspect conflicts between saved declarations. |
| [`input-verification-report-text.md`](input-verification-report-text.md) | Render a saved verification result as text. |
| [`cli-input-manifest-diff-text.md`](cli-input-manifest-diff-text.md) | Render a saved manifest comparison as text. |
| [`cli-input-manifest-schema.md`](cli-input-manifest-schema.md) | Producer output contract and manifest schema. |
| [`cli-input-manifest-diff-schema.md`](cli-input-manifest-diff-schema.md) | Comparison output contract and diff schema. |
| [`cli-input-manifest-verify-schema.md`](cli-input-manifest-verify-schema.md) | Verification output contract and schema. |

### Machine-readable summaries

| File | What it covers |
|------|----------------|
| [`init-task-presence-summary.md`](init-task-presence-summary.md) | Versioned task-presence checker summary. |
| [`qa-charter-coverage-summary.md`](qa-charter-coverage-summary.md) | Versioned QA charter coverage summary. |
| [`qa-append-io-failures.md`](qa-append-io-failures.md) | Fixed diagnostics for QA append I/O outcomes. |
| [`module-manifest-summary-schema.md`](module-manifest-summary-schema.md) | Portable module-manifest summary schema. |
| [`self-verification-findings-summary-schema.md`](self-verification-findings-summary-schema.md) | Portable self-verification findings summary schema. |
| [`product-artifact-validation-summary.md`](product-artifact-validation-summary.md) | Opt-in ProductArtifact checker summary. |
| [`ui-dx-evidence-summary.md`](ui-dx-evidence-summary.md) | Versioned UI/DX evidence checker summary. |
| [`qa-contract-version-summary.md`](qa-contract-version-summary.md) | Opt-in fixed outcome for QA contract-version binding. |
| [`security-finding-labels-summary.md`](security-finding-labels-summary.md) | Security finding-label checker summary. |
| [`skill-frontmatter-summary.md`](skill-frontmatter-summary.md) | Skill frontmatter checker summary. |
| [`test-value-card-summary.md`](test-value-card-summary.md) | Test-value-card checker summary. |
| [`summary-exit-rollup.md`](summary-exit-rollup.md) | Aggregate declared exits from saved summary objects. |
| [`summary-exit-rollup-schema.md`](summary-exit-rollup-schema.md) | Portable schema for the exit rollup. |
| [`summary-exit-relay.md`](summary-exit-relay.md) | Validate and relay a saved summary result. |
| [`summary-schema-catalog.md`](summary-schema-catalog.md) | List public summary schemas and bounded literal metadata. |
| [`summary-schema-resolver.md`](summary-schema-resolver.md) | Resolve a declared summary schema from a saved catalog. |
| [`topic-overlap-summary-schema.md`](topic-overlap-summary-schema.md) | Portable topic-overlap summary schema. |
| [`schemas/live-evidence-summary.v1.schema.json`](schemas/live-evidence-summary.v1.schema.json) | Portable schema for the maintainer/CI live-evidence summary. |

---

Category definition: `skills/diataxis-docs/SKILL.md`. See also the
[Documentation Taxonomy Mandate](../../AGENTS.md) in `AGENTS.md`.
