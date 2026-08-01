# How-to Guides — Problem-Solving Documentation

How-to guides are task-oriented. The reader already knows which problem they
want to solve and wants a direct, working answer: a sequence of steps, commands,
and configuration. No teaching, no digressions.

## When to write here

- Release, deployment, and environment-provisioning recipes.
- Migration procedures between framework schema versions.
- Recovery and rollback runbooks for when something has gone wrong.
- Integration steps — wiring hooks, CLIs, or external runtimes into Datarim.

## When NOT to write here

- A first end-to-end learning experience for a newcomer →
  [`tutorials/`](../tutorials/)
- Factual lookup — flags, schemas, catalogues → [`reference/`](../reference/)
- Rationale, background, or design trade-offs → [`explanation/`](../explanation/)

## Naming convention

Kebab-case `.md` filenames named after the task, for example
`release-rollback.md`, `recover-datarim-files.md`.

## Contents

| File | Task it solves |
|------|----------------|
| [`backlog-workflow.md`](backlog-workflow.md) | Manage tasks, priorities, and the backlog. |
| [`codex-cli-coworker-hooks.md`](codex-cli-coworker-hooks.md) | Wire the coworker delegation hooks into Codex CLI. |
| [`cross-kb-evolution-digest.md`](cross-kb-evolution-digest.md) | Produce a cross-knowledge-base evolution digest. |
| [`datarim-harness.md`](datarim-harness.md) | Run the framework's own test harness. |
| [`dr-output-hook.md`](dr-output-hook.md) | Install and configure the `/dr-*` output hook. |
| [`evolution-log.md`](evolution-log.md) | The append-only ledger of accepted framework evolutions. |
| [`fleet-hook-sync.md`](fleet-hook-sync.md) | Keep fleet hooks in sync across machines. |
| [`migrate-to-skill-md-layout.md`](migrate-to-skill-md-layout.md) | Migrate flat skills to the directory-per-skill `SKILL.md` layout. |
| [`multi-runtime.md`](multi-runtime.md) | Run Datarim under Claude Code, Codex CLI, and Cursor. |
| [`provision-release-environment.md`](provision-release-environment.md) | Prepare the environment a release is cut from. |
| [`pypi-first-publish.md`](pypi-first-publish.md) | Publish a package to PyPI for the first time. |
| [`recover-datarim-files.md`](recover-datarim-files.md) | Recover damaged or deleted `datarim/` state files. |
| [`release-process.md`](release-process.md) | Cut a signed, attested release. |
| [`release-rollback.md`](release-rollback.md) | Roll a released version back. |
| [`release-verification.md`](release-verification.md) | Verify a release before installing it (sha256 → cosign → attestation). |
| [`stage-snapshots.md`](stage-snapshots.md) | Use per-task stage snapshots to survive a cleared context window. |
| [`version-0x-policy.md`](version-0x-policy.md) | Apply the 0.x versioning policy. |

---

Category definition: `skills/diataxis-docs/SKILL.md`. See also the
[Documentation Taxonomy Mandate](../../CLAUDE.md) in `CLAUDE.md`.
