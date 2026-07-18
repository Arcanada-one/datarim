# TDD Enforcement Plugin

`tdd-enforcement` is a trusted, metadata-only Datarim plugin. It is enabled by default and controls only whether strict RED-GREEN-REFACTOR sequencing is mandatory.

Automated tests remain mandatory in both states. Disabling this plugin does not relax regression coverage, Definition of Done, security, QA, compliance, or verification evidence.

## Change the workspace state

Run these commands from the target workspace:

```bash
dr-plugin disable tdd-enforcement  # test timing becomes optional
dr-plugin enable tdd-enforcement   # strict test-first sequencing is required
```

The command updates `datarim/enabled-plugins.md`. It does not reinstall files or alter runtime symlinks. The new state applies at the next planning, implementation, or developer-agent boundary; it cannot remove instructions already loaded into a model context.

## State model

- No disabled-default entry: `required`.
- One exact `- tdd-enforcement` entry under `## Disabled Defaults`: `optional`.
- Missing, duplicate, malformed, indented, whitespace-altered, or substring state: `required` (fail-safe).

Inspect the effective state directly:

```bash
resolver="$(for root in "${DATARIM_RUNTIME:-}" "$HOME/.claude" "$HOME/.codex" "$HOME/.cursor"; do
  [ -n "$root" ] && [ -x "$root/scripts/tdd-enforcement-state.sh" ] && {
    printf '%s\n' "$root/scripts/tdd-enforcement-state.sh"
    break
  }
done)"
[ -n "$resolver" ] || { echo "TDD resolver is not installed" >&2; exit 2; }
bash "$resolver" --workspace /path/to/workspace
```

Third-party plugin manifests cannot opt into trusted default-on behavior by declaring `default_enabled: true`.
