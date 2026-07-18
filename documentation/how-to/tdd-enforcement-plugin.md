# Configure TDD Enforcement

The `tdd-enforcement` plugin is enabled by default. In its default `required` state, Datarim planning and implementation guidance requires strict RED-GREEN-REFACTOR order. In the `optional` state, the operator or developer may choose when to write tests.

Automated tests, regression coverage, Definition of Done, security checks, QA, compliance, and fresh verification evidence remain mandatory in both states.

## Check the effective state

From the workspace root, run:

```bash
resolver="$(for root in "${DATARIM_RUNTIME:-}" "$HOME/.claude" "$HOME/.codex" "$HOME/.cursor"; do
  [ -n "$root" ] && [ -x "$root/scripts/tdd-enforcement-state.sh" ] && {
    printf '%s\n' "$root/scripts/tdd-enforcement-state.sh"
    break
  }
done)"
[ -n "$resolver" ] || { echo "TDD resolver is not installed" >&2; exit 2; }
bash "$resolver" --workspace "$PWD"
```

The command prints exactly `required` or `optional`. It re-reads the workspace manifest on every invocation.

## Make strict sequencing optional

```bash
dr-plugin disable tdd-enforcement
```

This adds one exact tombstone under `## Disabled Defaults` in `datarim/enabled-plugins.md`. It does not remove skills, commands, agents, or symlinks.

## Require strict sequencing again

```bash
dr-plugin enable tdd-enforcement
```

This removes the tombstone. Both enable and disable are idempotent.

## Diagnose manual edits

```bash
dr-plugin doctor
```

Only one exact `- tdd-enforcement` entry in one well-formed disabled-default section can produce `optional`. Ambiguous or malformed state fails safe to `required`, and doctor reports the defect. Do not add `default_enabled: true` to third-party plugin manifests; the field is reserved for trusted core metadata.

## Runtime notes

Claude and Codex receive the resolver through the normal `scripts/` installation scope. Cursor receives the same resolver and library under its runtime `scripts/` directory. The boundary lookup honors `DATARIM_RUNTIME` first and otherwise checks the default Claude, Codex, and Cursor roots. Set `DATARIM_RUNTIME` only for a non-default runtime location.
