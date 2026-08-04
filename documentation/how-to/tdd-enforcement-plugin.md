# How to toggle strict test-first sequencing (tdd-enforcement)

Datarim ships strict test-first (RED-before-production-code) sequencing as a
**default-on workspace policy** managed by the core-owned, metadata-only
`tdd-enforcement` plugin. This guide shows how to inspect, disable, and
restore it.

## Check the current state

```bash
scripts/tdd-enforcement-state.sh
# -> required   (default: strict test-first sequencing applies)
# -> optional   (operator opted out: test timing is your choice)
```

The resolver re-reads `datarim/enabled-plugins.md` on every invocation —
state is never cached. It resolves the workspace like `/dr-plugin`
(`DR_PLUGIN_WORKSPACE`, else walk-up from the current directory) and fails
closed: no workspace, no manifest, or malformed policy content all print
`required`.

`/dr-plugin list` shows the same state as `enabled (default)` /
`disabled (default)` under "Default policies".

## Disable strict sequencing for this workspace

```bash
/dr-plugin disable tdd-enforcement
```

This records one exact tombstone line in `datarim/enabled-plugins.md`:

```markdown
## Disabled Defaults

- tdd-enforcement
```

The command is idempotent and touches no runtime symlinks — the plugin has no
projected files.

**What `optional` does and does not change.** You may write tests after the
implementation instead of before. Nothing else is relaxed: meaningful
automated tests for every behavior change, the anti-tautological test gate,
Definition of Done, security review, QA, and compliance gates remain
mandatory. The toggle relaxes ordering only, never test existence.

## Restore the strict default

```bash
/dr-plugin enable tdd-enforcement
```

Removes the tombstone (idempotent). The next planning, implementation, or
developer-agent boundary resolves `required` again; already-loaded model
context is not dynamically unloaded.

## Fail-safe rules and troubleshooting

Only one exact, unindented `- tdd-enforcement` entry in one well-formed
`## Disabled Defaults` section yields `optional`. These all resolve to
`required`:

- missing manifest or absent section,
- an indented entry or trailing whitespace,
- a substring id (e.g. `- tdd-enforcement-strict`),
- duplicate `## Disabled Defaults` headings or duplicate entries,
- any unsupported content inside the section.

Run `/dr-plugin doctor` to diagnose a malformed section (check 10,
`disabled-defaults`); fix it with the enable/disable commands rather than
manual edits.

## Trust boundary

`default_enabled: true` appears only in the core-owned
`plugins/tdd-enforcement/plugin.yaml` and is descriptive metadata. Third-party
manifests cannot acquire default-on behavior by declaring the field, and
`/dr-plugin enable <path>` refuses a plugin whose manifest claims the reserved
id.
