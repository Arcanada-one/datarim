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
| [`agents.md`](agents.md) | Every shipped agent — role, tier, primary stages, consilium panels. |
| [`skills.md`](skills.md) | Every shipped skill — type, model, purpose, and what loads it. |
| [`commands.md`](commands.md) | Every `/dr-*` slash command with arguments and outputs. |
| [`cli.md`](cli.md) | The standalone `datarim` CLI — subcommands, flags, environment. |
| [`complexity.md`](complexity.md) | The L1-L4 complexity levels and the pipeline each one routes through. |
| [`standards-mapping.md`](standards-mapping.md) | Security-baseline clusters mapped to ASVS, SOC 2, ISO 27001, and CIS. |
| [`validator-contract.md`](validator-contract.md) | The contract every `dev-tools/check-*.sh` validator must satisfy. |

---

Category definition: `skills/diataxis-docs/SKILL.md`. See also the
[Documentation Taxonomy Mandate](../../CLAUDE.md) in `CLAUDE.md`.
