# /dr-plugin — Datarim Plugin System CLI

**Source:** plugin-system core PRD and plan (see workspace `datarim/prd/` and `datarim/plans/` indexes).
**Status:** `list` + first-run bootstrap, `enable`, `disable`, `sync`, and `doctor` are all implemented and covered by `tests/dr-plugin.bats` + `tests/dr-plugin-coverage.bats`. Git-URL clone for `enable` (Phase A4) remains the only deferred path. `enable dr-orchestrate` additionally refuses (exit 1) unless the consumer workspace's `CLAUDE.md` already contains the string "Autonomous Agent Operating Rules" — the plugin ships FB-rules enforcement and assumes the mandate text is already mirrored at rank-1 level.

## Purpose


**Stage Header (mandatory)**: Emit `**{TASK-ID} · {title}**` as the first line of your response, before any tool-call narration. The title is the verbatim one-liner field from `tasks.md` (between `L{N} · ` and ` → tasks/`). Skip this header only for `/dr-help`, `/dr-status`, `/dr-doctor`, and `/dr-init` Steps 1-3 (which emit it immediately after Step 4). See `$HOME/.claude/skills/cta-format/SKILL.md` § Stage Header.
Manage opt-in plugins for the Datarim framework. The current Datarim shipping set (skills, agents, commands, templates) is migrated into a single protected `datarim-core` entry on first run. Third-party plugins are installed as symlinks from `datarim/plugin-storage/<id>/` into `~/.claude/local/{skills,agents,commands,templates}/<plugin-id>/`.

Two manifest layers:
- `plugin-storage/<id>/plugin.yaml` — static, per-plugin (under git in plugin repo).
- `datarim/enabled-plugins.md` — runtime, per-workspace (under git in workspace).

Templates: `${DATARIM_RUNTIME:-$HOME/.claude}/templates/plugin.yaml.template`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/enabled-plugins.md.template`.

## Subcommands

```
/dr-plugin list                  # show active plugins (bootstraps datarim-core on first run)
                                 # plus core-owned default policies (e.g. tdd-enforcement)
/dr-plugin enable <abs-path>     # activate a plugin from an absolute path (git-URL clone deferred — Phase A4)
/dr-plugin enable <default-id>   # restore a core-owned default policy (removes its tombstone)
/dr-plugin disable <id>          # deactivate (refuses datarim-core)
/dr-plugin sync                  # reconcile filesystem with manifest
/dr-plugin doctor [--fix]        # diagnose inconsistent state (10 checks)
/dr-plugin --help                # usage
```

## Default-on policy plugins (tdd-enforcement)

`tdd-enforcement` is a **core-owned, metadata-only, default-on** plugin: it
projects no runtime files and is effectively enabled in every workspace with
no manifest record. Opt-out is an exact tombstone under a
`## Disabled Defaults` section in `datarim/enabled-plugins.md`:

```markdown
## Disabled Defaults

- tdd-enforcement
```

- `/dr-plugin disable tdd-enforcement` adds the tombstone idempotently;
  `/dr-plugin enable tdd-enforcement` removes it. Neither touches symlinks.
- `/dr-plugin list` reports the state as `enabled (default)` or
  `disabled (default)`.
- `/dr-plugin sync` treats the plugin as inventory-free and preserves the
  tombstone; `/dr-plugin doctor` diagnoses malformed sections (check 10).
- Resolution is stateless and fail-safe: only one exact, unindented entry in
  one well-formed section yields the relaxed state; everything else resolves
  to the strict default. Canonical resolver: `scripts/tdd-enforcement-state.sh`
  (prints `required` | `optional`). Consumers: `commands/dr-do.md` Step 4,
  `agents/developer.md`, `skills/testing/tdd-discipline.md` § Enforcement
  Toggle.
- Trust is bound to the core-owned id: `default_enabled: true` in a
  third-party `plugin.yaml` grants nothing, and a path-based plugin claiming
  the reserved id is refused.

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

`tests/dr-plugin.bats` (77+ cases) + `tests/dr-plugin-coverage.bats` (4 reachability/coverage gates) — GREEN on macOS bash 3.2 + Linux bash 5+.

## Roadmap

- **Phase A3** — ✅ done. `enable`/`disable` happy paths + first-run inventory backfill for `datarim-core`.
- **Phase B** — ✅ done. `overrides:` mechanism + conflict pre-scan.
- **Phase C** — ✅ done. snapshot/rollback + `sync`.
- **Phase D** — ✅ done. `doctor` (8 checks).
- **Phase A4** — `enable` from a git URL (clone-and-activate). Deferred.
- **Phase E** — Class B public surface (CLAUDE.md, README, datarim.club).
- **Phase F** — author guide + bats coverage ≥80%.
