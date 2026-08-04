# tdd-enforcement — workspace toggle for strict test-first sequencing

A **core-owned, metadata-only, default-on** plugin. It ships no skills,
agents, commands, or templates and projects no symlinks — its whole job is to
give the strict test-first (RED-before-production-code) sequencing rule a
visible, workspace-local on/off switch with a fail-safe default.

## States

| State | Meaning |
|-------|---------|
| `required` (default) | Strict test-first sequencing applies in full: failing test first, then minimal code, then refactor. |
| `optional` | The implementer may choose test timing (tests may follow the code). Everything else is unchanged: meaningful automated tests for every behavior change, the anti-tautological test gate, Definition of Done, security, QA, and compliance gates **remain mandatory**. Optional relaxes ordering only, never test existence. |

## Usage

```bash
/dr-plugin disable tdd-enforcement   # record the opt-out tombstone
/dr-plugin enable tdd-enforcement    # restore the strict default
/dr-plugin list                      # shows enabled (default) / disabled (default)
scripts/tdd-enforcement-state.sh     # prints "required" or "optional"
```

Disable records one exact `- tdd-enforcement` line under a
`## Disabled Defaults` section in `datarim/enabled-plugins.md`; enable removes
it. Neither touches runtime symlinks. State is re-resolved from the workspace
manifest at each planning/implementation boundary — never cached.

## Fail-safe parsing

Only one exact, unindented tombstone in one well-formed section yields
`optional`. Missing manifest, absent section, duplicate headings or entries,
indentation, trailing whitespace, substring ids, or any unsupported content
in the section all resolve to `required`. `/dr-plugin doctor` diagnoses
malformed sections.

## Trust boundary

`default_enabled: true` in this manifest is descriptive metadata. Trust is
bound to the core-owned plugin id: third-party manifests cannot acquire
default-on behavior by declaring the field, and a path-based plugin claiming
the reserved id is refused at enable time.
