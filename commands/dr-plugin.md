# /dr-plugin — Datarim Plugin System CLI

**Source:** plugin-system core PRD and plan (see workspace `datarim/prd/` and `datarim/plans/` indexes).
**Status:** `list` + first-run bootstrap, `enable`, `disable`, `sync`, and `doctor` are implemented and covered by the plugin and TDD-toggle Bats suites. Git-URL clone for ordinary plugin enable remains deferred.

## Purpose


**Stage Header (mandatory)**: Emit `**{TASK-ID} · {title}**` as the first line of your response, before any tool-call narration. The title is the verbatim one-liner field from `tasks.md` (between `L{N} · ` and ` → tasks/`). Skip this header only for `/dr-help`, `/dr-status`, `/dr-doctor`, and `/dr-init` Steps 1-3 (which emit it immediately after Step 4). See `$HOME/.claude/skills/cta-format/SKILL.md` § Stage Header.
Manage plugins for the Datarim framework. The current shipping set is represented by a protected `datarim-core` entry. Ordinary third-party plugins are opt-in and install as runtime symlinks. The trusted metadata-only `tdd-enforcement` plugin is enabled by default and uses a workspace tombstone instead of symlinks.

Two manifest layers:
- `plugin-storage/<id>/plugin.yaml` — static, per-plugin (under git in plugin repo).
- `datarim/enabled-plugins.md` — runtime, per-workspace (under git in workspace).

Templates: `${DATARIM_RUNTIME:-$HOME/.claude}/templates/plugin.yaml.template`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/enabled-plugins.md.template`.

## Subcommands

```
/dr-plugin list                  # show active plugins (bootstraps datarim-core on first run)
/dr-plugin enable <abs-path>     # activate a plugin from an absolute path (git-URL clone deferred — Phase A4)
/dr-plugin enable tdd-enforcement # require strict RED-GREEN-REFACTOR sequencing
/dr-plugin disable <id>          # deactivate (refuses datarim-core)
/dr-plugin disable tdd-enforcement # make test timing optional; tests remain mandatory
/dr-plugin sync                  # reconcile filesystem with manifest
/dr-plugin doctor [--fix]        # diagnose inconsistent state (10 checks)
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
| 3 | concurrent invocation (lock held) |
| 64 | usage error |

## Environment overrides (testing)

| Variable | Purpose | Default |
|----------|---------|---------|
| `DR_PLUGIN_WORKSPACE` | Workspace root containing `datarim/` | walk-up from cwd |
| `DR_PLUGIN_RUNTIME_ROOT` | Symlink target root | `$HOME/.claude/local` |

## Tests

`tests/dr-plugin.bats` (77+ cases), `tests/dr-plugin-coverage.bats` (4 reachability/coverage gates), and the TDD-enforcement suites cover the ordinary and default-on paths on macOS Bash 3.2-compatible syntax and Linux Bash 5+.

## Default-on TDD enforcement

`/dr-plugin disable tdd-enforcement` adds the exact `- tdd-enforcement` tombstone under `## Disabled Defaults`; `/dr-plugin enable tdd-enforcement` removes it. No runtime files are installed or removed. Missing or malformed state fails safe to strict sequencing. Automated tests and all downstream quality gates remain mandatory in either state. See `documentation/how-to/tdd-enforcement-plugin.md`.

## Roadmap

- **Phase A3** — ✅ done. `enable`/`disable` happy paths + first-run inventory backfill for `datarim-core`.
- **Phase B** — ✅ done. `overrides:` mechanism + conflict pre-scan.
- **Phase C** — ✅ done. snapshot/rollback + `sync`.
- **Phase D** — ✅ done. `doctor` (10 checks, including disabled-default policy validation).
- **Phase A4** — `enable` from a git URL (clone-and-activate). Deferred.
- **Phase E** — Class B public surface (CLAUDE.md, README, datarim.club).
- **Phase F** — author guide + bats coverage ≥80%.
