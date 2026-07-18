# Toggle Coworker Delegation Per Workspace

The bundled `coworker-delegation` plugin is a trusted, metadata-only workspace policy. It is enabled by default. Disable it when a workspace should allow native agent reads, writes, and bulk diff or log inspection without routing those operations through `coworker`.

## Change the state

Run the command from the target workspace:

```bash
dr-plugin disable coworker-delegation
dr-plugin enable coworker-delegation
```

The change takes effect on the next resolver or hook invocation. No runtime reinstall or agent restart is required.

## Inspect the effective state

Locate `scripts/coworker-delegation-state.sh` under `${DATARIM_RUNTIME:-$HOME/.claude}`, `$HOME/.codex`, or `$HOME/.cursor`, then run:

```bash
bash /path/to/coworker-delegation-state.sh --workspace /path/to/workspace
```

The resolver prints `enabled` or `disabled`. One exact `- coworker-delegation` entry under the single `## Disabled Defaults` heading resolves `disabled`. Missing, duplicate, malformed, indented, whitespace-altered, misplaced, or substring state resolves `enabled`.

## What disabled changes

Disabled state deactivates the coworker delegation instruction boundary and its hook denials for bulk reads, protected first drafts, and large diff or log output. It also skips the SessionStart provider and balance probe.

Critical-KB pre-overwrite backups and the explicit branch start-point gate remain active because they are unrelated safety controls.

## Boundaries

This toggle does not install, remove, configure, discover, or call `coworker` or any provider. It does not change credentials, profiles, endpoints, hook registration, `VERSION`, or release state. Claude, Codex, and Cursor receive the same resolver and state semantics during normal framework installation.
