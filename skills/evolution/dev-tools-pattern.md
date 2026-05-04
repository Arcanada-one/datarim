---
name: evolution/dev-tools-pattern
description: Pattern for framework maintainer-only tooling — lives in dev-tools/, structurally excluded from INSTALL_SCOPES, never shipped to consumers. Load before adding any maintainer-side linter, generator, or audit script.
---

# Dev-Tools Pattern — Maintainer-Only Tooling

The Datarim framework is operated by a single maintainer who occasionally
writes tools used **only** by the framework's own development workflow —
linters that check internal consistency, audit scripts that compare framework
state against sibling repos, generators for boilerplate. These tools must
exist somewhere in the framework checkout (so changes land atomically with the
artefacts they audit) but must **never** appear on consumers' machines.

This skill defines the pattern that satisfies both constraints.

## When to apply

Load this skill when a reflection proposal, optimisation task, or new feature
asks for any of:

- A linter that runs on framework files (skills/agents/commands/templates,
  docs, CLAUDE.md, README.md) before merge.
- An audit script comparing framework state to sibling repos (e.g. a sister
  documentation site, a project-level CLAUDE.md).
- A generator that produces boilerplate for new framework artefacts.
- A pre-commit hook the maintainer wants installed locally.
- Any tool that has no value for downstream Datarim consumers.

If the tool is useful to consumers (e.g. a project-init helper they would run
themselves), this skill does **not** apply — that tool belongs in
`scripts/` (shipped) or `templates/` (consumer-installable).

## The pattern (4 contracts)

### 1. Location: `code/datarim/dev-tools/`

A single top-level directory in the framework repo. Layout convention:

```
code/datarim/
├── skills/, agents/, commands/, templates/    ← shipped (in INSTALL_SCOPES)
├── docs/, scripts/, tests/                    ← shipped
└── dev-tools/                                 ← NOT shipped
    ├── <tool-name>.sh
    ├── <tool-config>.<ext>           (if config-driven)
    ├── tests/
    │   └── <tool-name>.bats
    └── README.md                     (purpose + boundary statement)
```

Multiple tools share `dev-tools/` flat or grouped by function (`dev-tools/lint/`,
`dev-tools/audit/`); the parent directory itself is the unit of exclusion.

### 2. Structural exclusion from `INSTALL_SCOPES`

The framework's installer uses a **whitelist**, not a denylist. Look at
`install.sh` for the line declaring `INSTALL_SCOPES=(...)` — `dev-tools` is
absent by construction, therefore the directory is never symlinked or copied
to `~/.claude/`.

**Add a one-line comment** near `INSTALL_SCOPES` documenting the intentional
absence:

```
# Note: 'dev-tools' is intentionally NOT in this list — see
# dev-tools/README.md (developer-only tooling, not shipped).
```

**Add a regression test** in `tests/install.bats` asserting that
`~/.claude/dev-tools/` does NOT exist after both symlink-mode and copy-mode
installs. The exclusion is a contract; a regression silently shipping
dev-tools/ to a consumer is a security finding.

### 3. Inside the framework's security gate

`dev-tools/` is in the public framework repo. Bots scanning the repo will see
it. Treat its files with the **same** rigor as shipped artefacts:

- Shell scripts pass the framework's shellcheck warning level clean.
- Embedded code blocks in `dev-tools/README.md` extracted by the framework's
  code-block extractor and linted by the same security gates as shipped
  documentation.
- Secrets scanner (gitleaks/trufflehog) runs on `dev-tools/` — zero leaks.
- Action workflows for dev-tools (e.g. CI lint of the linter itself) use
  pinned action SHAs and minimal `permissions:`.

The boundary is **shipped artefacts run on consumers** vs **dev-tools run only
on the maintainer**. SOC 2 / supply-chain scope cares about the former; the
latter must still be safe code, but its blast radius stops at the maintainer's
machine.

### 4. Bundle config + tests + README

A dev-tool is shipped as a self-contained subtree:

- The script itself.
- A bundled default config (if config-driven) at `dev-tools/<tool>.<ext>` —
  framework defaults that work out of the box for the maintainer.
- Bats coverage at `dev-tools/tests/` — fixtures live next to the tool, not in
  the shipped `tests/` directory.
- A README documenting: purpose, why it's not shipped, schema (if applicable),
  CLI flags, exit codes, security boundary statement.

The boundary statement in the README is mandatory. A reader (or auditor)
opening `dev-tools/README.md` must learn within the first paragraph: «this
directory is intentionally not shipped to consumers; it exists for the
framework maintainer».

## Why this pattern

| Force | Resolution |
|---|---|
| **Atomic edits** — renaming a runtime artefact must update its linter config in the same PR | One repo, one feature branch, one tag, one changelog. |
| **Zero consumer footprint** — SOC 2 audits scan consumer install output, not framework repo content | Whitelist install (structural exclusion); install.bats regression. |
| **No supply-chain backdoor in public repo** — bots and security researchers DO scan the framework repo | Same security gate as shipped artefacts; no relaxation. |
| **Single maintainer, near-zero overhead** | One CI, one tag, one changelog. No second repo. |
| **Discoverability for the maintainer** | `dev-tools/` next to the artefacts it audits; README explains itself. |

## Anti-patterns (rejected alternatives)

- **Separate repo `<framework>-dev-tools`.** Forces 2 PRs, 2 CIs, 2 tags for any
  rename/refactor; high overhead vs single-maintainer benefit.
- **Branch `dev-tools` in framework repo.** Pre-commit hook breaks on
  `git checkout main`; ongoing rebase burden; not an established OSS pattern.
- **Inline in `tests/` or `scripts/`.** Couples maintainer tooling with shipped
  artefacts; consumer install brings the linter onto their machine; SOC 2
  audit flags maintainer scripts as part of consumer runtime.
- **Inline in shipped `skills/` or `agents/`.** Same as above plus the AI agent
  loads them as part of consumer's runtime context — wastes tokens, confuses
  the agent.

## Apply checklist

Before merging a new dev-tool:

- [ ] Lives entirely under `code/datarim/dev-tools/`
- [ ] `INSTALL_SCOPES` whitelist UNCHANGED (add only the comment, not the
      directory)
- [ ] `tests/install.bats` regression asserting `~/.claude/<tool-dir>` absent
      after symlink-mode and copy-mode installs
- [ ] Tool's own bats coverage at `dev-tools/tests/<tool>.bats`
- [ ] Shellcheck warning-level clean on every `*.sh`
- [ ] Secrets scanner (gitleaks) clean on `dev-tools/`
- [ ] CI workflow (if any) uses pinned action SHAs and minimal `permissions:`
- [ ] `dev-tools/README.md` opens with the boundary statement (not shipped to
      consumers)
- [ ] No task IDs (`TUNE-XXXX`/etc.) inline in `dev-tools/{*.sh,*.yml,*.md}` —
      provenance lives in PRD/archive/git log, not runtime artefacts
      (sibling rule: `skills/evolution/history-agnostic-gate.md`)

## Sibling skills

- `skills/evolution/stack-agnostic-gate.md` — runtime artefacts must not
  embed language/framework-stack terms.
- `skills/evolution/history-agnostic-gate.md` — runtime artefacts must not
  embed task-ID provenance.
- `skills/evolution/class-ab-gate.md` — Class A vs Class B classification
  for evolution proposals.

This skill is the third sibling: maintainer tooling lives under `dev-tools/`,
structurally excluded from the install.
