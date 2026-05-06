# Plugin Author Guide (v1.23.0+)

## 1. What is a plugin

A Datarim plugin is a versioned, opt-in bundle of framework assets. The framework ships a protected builtin plugin called `datarim-core` that cannot be disabled; everything else is third-party and must be explicitly enabled per workspace.

Plugins contain assets in up to four categories:

- `skills` — reusable skill definitions
- `agents` — agent configurations
- `commands` — slash-command implementations
- `templates` — document templates

When you enable a plugin, `dr-plugin` symlinks its assets from `datarim/plugin-storage/<id>/` into `~/.claude/<category>/<plugin-id>/`. Disabling removes the symlinks and restores any shadowed core files. Third-party plugins are never loaded automatically.

## 2. Plugin layout

A plugin is a directory with a mandatory `plugin.yaml` in the root and one subdirectory per declared category.

```
hello-plugin/
├── plugin.yaml
├── skills/
│   └── hello-world.md
└── commands/
    └── hello.md
```

Only create subdirectories for categories you actually declare in `plugin.yaml`. Extra directories are ignored by the sync engine, but missing directories for declared categories trigger a validation warning during `dr-plugin doctor`. The runtime `file_inventory` (recorded in `datarim/enabled-plugins.md`) is derived automatically by `dr-plugin enable` from a filesystem scan of each declared category — authors do not list files in `plugin.yaml`.

## 3. Manifest schema

`plugin.yaml` uses `schema_version: 1`. Fields are case-sensitive.

| Field | Required | Format |
|---|---|---|
| `schema_version` | yes | `1` |
| `id` | yes | kebab-case, `^[a-z][a-z0-9-]{0,31}$` |
| `title` | yes | plain text |
| `version` | yes | semantic version |
| `author` | yes | plain text |
| `license` | yes | SPDX identifier or license name |
| `description` | yes | one-line summary |
| `categories` | yes | list from `{skills, agents, commands, templates}` |
| `homepage` | no | HTTPS URL |
| `overrides` | no | list of core file basenames (no extension) to shadow |
| `depends_on` | no | list of plugin ids that must be enabled first |

`file_inventory` is populated by `dr-plugin enable` from a filesystem scan and stored in the runtime manifest (`datarim/enabled-plugins.md`). Authors do not declare it.

Full example:

```yaml
schema_version: 1

id: hello-plugin
title: Hello Plugin
version: 1.0.0
author: Jane Doe
license: MIT
description: Minimal example plugin for Datarim.

categories:
  - skills
  - commands

# Optional
homepage: https://github.com/janedoe/hello-plugin

# overrides:
#   - some-core-file

# depends_on:
#   - another-plugin
```

## 4. Working example: hello-plugin

Create the directory tree above with the following files.

`plugin.yaml`:

```yaml
schema_version: 1

id: hello-plugin
title: Hello Plugin
version: 1.0.0
author: Jane Doe
license: MIT
description: Minimal example plugin for Datarim.

categories:
  - skills
  - commands
```

`skills/hello-world.md`:

```markdown
---
name: hello-world
category: skills
---

# hello-world

Say hello from a plugin.
```

`commands/hello.md`:

```markdown
---
name: hello
category: commands
---

# /hello

Plugin-provided command stub.
```

Enable and verify:

```bash
# from your workspace root
dr-plugin enable /absolute/path/to/hello-plugin
dr-plugin list
dr-plugin disable hello-plugin
```

## 5. Override etiquette

The `overrides` list lets a plugin replace a core file by basename (without extension). When enabled, `dr-plugin` renames the active core symlink to `<name>.datarim-core.disabled` and installs your file in its place.

Rules:

- Only override files that exist in the root of a category directory inside `datarim-core`. Overrides are matched by basename; namespaced subpaths are not supported.
- Provide a documented rationale in your plugin README or as a YAML comment.
- Keep overrides single and targeted. Do not blanket-override core assets.
- If core updates the overridden file, your plugin continues to shadow it until disabled or the override is removed.

## 6. Dependencies

`depends_on` declares hard prerequisites. `dr-plugin` enforces the following rules:

- `enable` refuses to activate a plugin if any dependency is missing or disabled.
- `disable` refuses to deactivate a plugin if another active plugin lists it in `depends_on`.
- Circular dependency chains are detected by `dr-plugin doctor` and reported as a validation error.

Dependency resolution is not transitive for URL or path sources; each dependency must be explicitly enabled by its id before the dependent plugin.

## 7. Security warnings

The plugin system applies strict input validation:

- CRLF line endings are rejected in `plugin.yaml` and in all files under `file_inventory`. Use LF only.
- Path traversal sequences (`../`, `\..`) are rejected in plugin ids, source paths, and any URL path component.
- Embedded credentials (`user:pass@host`) in git or HTTPS source URLs are rejected.
- The runtime `file_inventory` is filesystem-derived at enable time. Files added to plugin source after enable are not picked up until you re-enable or run `dr-plugin sync`.

All symlinks created by `dr-plugin` are verified to point inside the resolved plugin storage directory.

## 8. Testing your plugin locally

You can test without polluting your production `~/.claude/local` tree.

```bash
export DR_PLUGIN_WORKSPACE=/tmp/test-workspace
export DR_PLUGIN_RUNTIME_ROOT=/tmp/test-claude-local

mkdir -p "$DR_PLUGIN_WORKSPACE/datarim"
cd "$DR_PLUGIN_WORKSPACE"

dr-plugin enable /path/to/your-plugin
dr-plugin list
dr-plugin doctor
dr-plugin disable your-plugin-id
```

Unset the variables to return to normal operation.

## 9. Publishing

Distribution is git-based.

1. Ensure `plugin.yaml` is in the repository root and committed.
2. Tag releases with the version declared in `plugin.yaml` (for example, `v1.0.0`).
3. Users install directly from the URL:

```bash
dr-plugin enable https://github.com/yourname/your-plugin.git
```

No additional build step or registry upload is required. Version resolution uses the tag that matches the `version` field at the repository HEAD.

## 10. Troubleshooting

Top five failure modes and their exit codes:

| Symptom | Exit | Cause / Fix |
|---|---|---|
| `invalid id` | `1` | Plugin id violates `^[a-z][a-z0-9-]{0,31}$`. Use kebab-case, start with a letter, max 32 chars. |
| `schema drift` | `1` | `file_inventory` does not match files on disk. Run `dr-plugin sync` or correct the manifest. |
| `conflict pre-scan` | `1` | Two plugins declare the same override or the same symlink target exists. Disable the conflicting plugin first. |
| `lock contention` | `3` | Another `dr-plugin` process is running. Wait and retry. |
| `doctor errors` | `2` | Filesystem inconsistency (broken symlink, missing dependency, cycle). Run `dr-plugin doctor --fix` or repair manually. |

## 11. References

- `datarim/prd/PRD-TUNE-0101-plugin-system-core.md` — Product requirements
- `datarim/commands/dr-plugin.md` — CLI reference and exit codes
- `datarim/templates/plugin.yaml.template` — Blank manifest template
- `datarim/docs/getting-started.md` — Workspace onboarding