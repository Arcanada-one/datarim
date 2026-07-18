# /dr-plugin — Datarim Plugin System CLI

**Source:** plugin-system core PRD and plan (see workspace `datarim/prd/` and `datarim/plans/` indexes).
**Status:** `list` + first-run bootstrap, `enable`, `disable`, `sync`, and `doctor` are implemented and covered by the plugin, TDD-toggle, and LTM-toggle Bats suites. Git-URL clone for ordinary plugin enable remains deferred.

## Purpose


**Stage Header (mandatory)**: Emit `**{TASK-ID} · {title}**` as the first line of your response, before any tool-call narration. The title is the verbatim one-liner field from `tasks.md` (between `L{N} · ` and ` → tasks/`). Skip this header only for `/dr-help`, `/dr-status`, `/dr-doctor`, and `/dr-init` Steps 1-3 (which emit it immediately after Step 4). See `$HOME/.claude/skills/cta-format/SKILL.md` § Stage Header.
Manage plugins for the Datarim framework. The current shipping set is represented by a protected `datarim-core` entry. Ordinary third-party plugins are opt-in and install as runtime symlinks. Trusted metadata-only policies use no symlinks: `tdd-enforcement` and `coworker-delegation` are default-on with workspace tombstones, while `ltm-graph-memory` is default-off with a strict built-in active record.

Two manifest layers:
- `plugin-storage/<id>/plugin.yaml` — static, per-plugin (under git in plugin repo).
- `datarim/enabled-plugins.md` — runtime, per-workspace (under git in workspace).

Templates: `${DATARIM_RUNTIME:-$HOME/.claude}/templates/plugin.yaml.template`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/enabled-plugins.md.template`.

## Subcommands

```
/dr-plugin list                  # show active plugins (bootstraps datarim-core on first run)
/dr-plugin enable <abs-path>     # activate a plugin from an absolute path (git-URL clone deferred — Phase A4)
/dr-plugin enable tdd-enforcement # require strict RED-GREEN-REFACTOR sequencing
/dr-plugin enable coworker-delegation # require coworker delegation policy
/dr-plugin enable ltm-graph-memory # permit a separately configured LTM adapter
/dr-plugin disable <id>          # deactivate (refuses datarim-core)
/dr-plugin disable tdd-enforcement # make test timing optional; tests remain mandatory
/dr-plugin disable coworker-delegation # permit native agent I/O
/dr-plugin disable ltm-graph-memory # forbid graph-memory operations
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
- `manifest_builtin_metadata_status <manifest> <id>` — exact `enabled|disabled|invalid` trusted-record state
- `manifest_set_builtin_metadata_state <manifest> <id> <version> <timestamp> <state>` — section-safe metadata-only mutation

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

`tests/dr-plugin.bats`, `tests/dr-plugin-coverage.bats`, the TDD-enforcement suites, and the LTM graph-memory suites cover ordinary, default-on, and default-off paths on macOS Bash 3.2-compatible syntax and Linux Bash 5+.

## Default-on TDD enforcement

`/dr-plugin disable tdd-enforcement` adds the exact `- tdd-enforcement` tombstone under `## Disabled Defaults`; `/dr-plugin enable tdd-enforcement` removes it. No runtime files are installed or removed. Missing or malformed state fails safe to strict sequencing. Automated tests and all downstream quality gates remain mandatory in either state. See `documentation/how-to/tdd-enforcement-plugin.md`.

## Default-on coworker delegation

`/dr-plugin disable coworker-delegation` adds the exact `- coworker-delegation` tombstone under `## Disabled Defaults`; `/dr-plugin enable coworker-delegation` removes it. Disabled state permits native agent I/O and skips delegation-specific hook denials and the SessionStart provider probe. Critical-KB backups and explicit branch start-point enforcement remain active. Missing or malformed state fails safe to enabled delegation. See `documentation/how-to/coworker-delegation-toggle.md`.

## Default-off LTM graph memory

`/dr-plugin enable ltm-graph-memory` adds one exact built-in metadata record; `/dr-plugin disable ltm-graph-memory` removes it. Missing, duplicate, incomplete, wrong-source, protected, or non-empty-inventory records fail safe to disabled. The toggle installs no runtime file and does not prove an adapter exists. See `documentation/how-to/ltm-graph-memory-adapter.md`.

## Roadmap

- **Phase A3** — ✅ done. `enable`/`disable` happy paths + first-run inventory backfill for `datarim-core`.
- **Phase B** — ✅ done. `overrides:` mechanism + conflict pre-scan.
- **Phase C** — ✅ done. snapshot/rollback + `sync`.
- **Phase D** — ✅ done. `doctor` (10 checks, including trusted policy-state validation).
- **Phase A4** — `enable` from a git URL (clone-and-activate). Deferred.
- **Phase E** — Class B public surface (CLAUDE.md, README, datarim.club).
- **Phase F** — author guide + bats coverage ≥80%.
