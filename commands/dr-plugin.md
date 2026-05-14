# /dr-plugin — Datarim Plugin System CLI

**Source:** plugin-system core PRD and plan (see workspace `datarim/prd/` and `datarim/plans/` indexes).
**Status (Phase A scaffold):** `list` + first-run bootstrap implemented; `enable`/`disable`/`sync`/`doctor` deferred to next iterations.

## Purpose

Manage opt-in plugins for the Datarim framework. The current Datarim shipping set (skills, agents, commands, templates) is migrated into a single protected `datarim-core` entry on first run. Third-party plugins are installed as symlinks from `datarim/plugin-storage/<id>/` into `~/.claude/local/{skills,agents,commands,templates}/<plugin-id>/`.

Two manifest layers:
- `plugin-storage/<id>/plugin.yaml` — static, per-plugin (under git in plugin repo).
- `datarim/enabled-plugins.md` — runtime, per-workspace (under git in workspace).

Templates: `templates/plugin.yaml.template`, `templates/enabled-plugins.md.template`.

## Subcommands

```
/dr-plugin list                  # show active plugins (bootstraps datarim-core on first run)
/dr-plugin enable <id|path|url>  # activate a plugin (Phase A3 — pending)
/dr-plugin disable <id>          # deactivate (Phase A3 — pending; refuses datarim-core)
/dr-plugin sync                  # reconcile filesystem with manifest (Phase C — pending)
/dr-plugin doctor [--fix]        # diagnose inconsistent state (Phase D — pending)
/dr-plugin --help                # usage
```

## Implementation

Slash command resolves to `scripts/dr-plugin.sh <subcommand>` (executable bash, POSIX-friendly, bash 3.2 compatible).

Helpers in `scripts/lib/plugin-system.sh`:
- `validate_plugin_id` — kebab-case, `[a-z][a-z0-9-]{0,31}`
- `validate_source` — `builtin` | abs path | https URL (no embedded credentials, no path traversal)
- `parse_plugin_yaml <file> <field>` — awk-based scalar extraction; rejects CRLF
- `parse_yaml_list <file> <key>` — awk-based list extraction

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | success |
| 1 | validation/conflict error |
| 2 | I/O / filesystem error |
| 3 | concurrent invocation (lock held; Phase A3+) |
| 64 | usage error |

## Environment overrides (testing)

| Variable | Purpose | Default |
|----------|---------|---------|
| `DR_PLUGIN_WORKSPACE` | Workspace root containing `datarim/` | walk-up from cwd |
| `DR_PLUGIN_RUNTIME_ROOT` | Symlink target root | `$HOME/.claude/local` |

## Tests

`tests/dr-plugin.bats` — 28 cases, GREEN on macOS bash 3.2 + Linux bash 5+.

## Roadmap

- **Phase A3** — `enable`/`disable` happy paths + first-run inventory backfill for `datarim-core`.
- **Phase B** — `overrides:` mechanism + conflict pre-scan.
- **Phase C** — snapshot/rollback + `sync`.
- **Phase D** — `doctor` (8 checks).
- **Phase E** — Class B public surface (CLAUDE.md, README, datarim.club).
- **Phase F** — author guide + bats coverage ≥80%.
