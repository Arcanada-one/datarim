# Module Manifest (`module.yaml`) — Reference

> **Status:** schema + example + validator stub. This is the declarative
> content-manifest for a Datarim **skill pack** (a plugin's `skills/` set). It
> is a follow-up to the Plugin System: `plugin.yaml` declares the plugin
> *source* (id, categories, overrides, symlink policy); `module.yaml` declares
> the *contents* of that source's skill pack — per-skill version, dependencies,
> one-line help, and stability — so the pack can be versioned, dependency-
> checked, deterministically indexed, and linted without opening every
> `SKILL.md`.

`plugin.yaml` and `module.yaml` are orthogonal and both optional:

| File | Declares | Consumed by |
|------|----------|-------------|
| `plugin.yaml` | plugin source identity + symlink/override policy | `/dr-plugin enable/sync/doctor` |
| `module.yaml` | the skill pack's per-skill catalogue (version, deps, help) | manifest validator + (future) deterministic index + lint |

A plugin MAY ship a `module.yaml` beside its `plugin.yaml`. Absence is not an
error — a pack without `module.yaml` is simply un-indexed and un-versioned at
the pack level, exactly as today.

## Schema (schema_version 1)

```yaml
schema_version: 1            # int, required, currently 1

module:                      # required — the pack's own identity
  id: <kebab-case>           # required, ^[a-z][a-z0-9-]{0,63}$ (unique per plugin)
  title: <string>            # required, human-readable
  version: <semver>          # required, MAJOR.MINOR.PATCH
  description: <string>      # required, one sentence

skills:                      # required, non-empty list — one entry per shipped skill
  - name: <kebab-case>       # required, MUST match a skills/<name>/SKILL.md dir
    version: <semver>        # required, MAJOR.MINOR.PATCH
    summary: <string>        # required — one-line help (the module-help.csv analog)
    stability: <enum>        # optional — stable | beta | experimental (default: stable)
    requires:                # optional — other skills this one depends on (by name)
      - <kebab-case>
```

### Field rules

- `schema_version` — integer literal `1`. Any other value is a hard error.
- `module.id`, every `skills[].name`, and every `requires[]` entry match
  `^[a-z][a-z0-9-]{0,63}$` (same kebab rule as the skill-layout gate).
- `module.version` and every `skills[].version` match semver
  `^[0-9]+\.[0-9]+\.[0-9]+$`.
- `skills` MUST be non-empty — an empty pack has no reason to declare a manifest.
- `skills[].name` SHOULD resolve to a real `skills/<name>/SKILL.md` in the pack;
  the validator warns (not errors) on a name with no matching directory, because
  the manifest may be authored before the skill file lands.
- `requires[]` entries SHOULD name skills declared in the same `skills` list; a
  dependency on a name absent from the list is a warning (it may be satisfied by
  the core pack or another enabled plugin, which this stub does not resolve).
- `stability` ∈ {`stable`, `beta`, `experimental`}. Omitted ⇒ `stable`.

## Validation

`dev-tools/check-module-manifest.sh <path-to-module.yaml>` validates a manifest
against the rules above. It is a **stub** by design — a dependency-free
(`grep`/`sed`, no `yq`) structural check, not a full YAML parser or a
cross-plugin dependency resolver. Exit codes:

- `0` — manifest is structurally valid (warnings may still print to stderr).
- `1` — a hard-error rule was violated (missing required field, bad
  `schema_version`, malformed id/version, empty `skills`).
- `2` — usage error (no path / file not found).

The deterministic-index build and the lint-integration wiring are the larger
Plugin-System follow-up; this reference + the validator stub establish the
contract they will consume.

## Example

A complete example ships at `templates/module.yaml` — copy it into a plugin's
skill pack and edit. See also `plugins/*/plugin.yaml` for the orthogonal source
manifest.
