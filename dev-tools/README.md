# dev-tools/ — Developer-only tooling for Datarim framework

> **NOT shipped to consumers.** This directory is intentionally excluded
> from `INSTALL_SCOPES` in `install.sh`. Consumer projects
> of Datarim never see it. No supply-chain footprint on user side.

## Purpose

Maintainer-side utilities for keeping the framework itself in shape.
Currently provides one tool: a doc-fanout linter that detects asymmetric
drift between canonical artefacts (`commands/`, `skills/`, `agents/`)
and N consumer surfaces (CLAUDE.md, README.md, docs/, sister-site PHP).

## Why dev-only / not shipped

1. The drift it detects is between **framework-internal** state and
   **framework-internal** documentation/site surfaces. Consumers ship
   their own projects with their own catalogs.
2. The tool reads the entire framework tree at every run. Its
   correctness depends on assumptions that are private to the maintainer
   (relative paths, directory layout, count regexes).
3. Shipping it would create false expectations of public stability for
   a config schema that may evolve fast in v1.

## Files

| File | Role |
|------|------|
| `doc-fanout-lint.sh` | The linter binary (POSIX-ish bash + AWK). |
| `.doc-fanout.yml` | Bundled config covering Datarim's own surfaces. |
| `.docfanoutignore` | Optional baseline (gitignore-style); empty by default. |
| `install-hook.sh` | Idempotent pre-commit hook installer (workspace repo). |
| `tests/doc-fanout-lint.bats` | Self-tests (≥17 fixtures: T1–T17). |
| `tests/fixtures/` | Reserved for ad-hoc fixture configs. |

## Schema (`.doc-fanout.yml v1`)

Block-style YAML, depth ≤ 3. **No flow style, no anchors, no multiline
scalars.**

```yaml
version: 1                       # mandatory; missing/unknown → fatal exit 2

artifacts:
  - glob: <pattern>              # relative to --root, evaluated by shell glob
    name_transform: <enum>       # basename | basename_no_ext | literal
    consumers:
      - id: <stable-id>
        kind: grep_in_file       # one of: grep_in_file | file_must_exist
        file: <relpath>          # for grep_in_file
        path: <relpath>          # for file_must_exist
        pattern: "<template>"    # for grep_in_file: literal text + {name}
        severity: error|warning
        cross_root: true|false   # for file_must_exist; default false

counts:
  - id: <stable-id>
    source_glob: <pattern>
    consumer_file: <relpath>
    pattern: "<regex>"           # one capture group; first match wins
    severity: error|warning
```

## Rule kinds

### `grep_in_file`

Substitutes `{name}` in `pattern`, then asserts that the resulting literal
string appears in `file` (relative to `--root`). Uses `grep -F`.

### `file_must_exist`

Substitutes `{name}` in `path`, then asserts that the canonicalised
absolute target exists. Cross-root targets (paths that resolve outside
`--root`) require both `cross_root: true` in config AND `--allow-cross-root`
on the command line.

### `count_match`

Counts the artefacts matching `source_glob`, then extracts the first
capture group of `pattern` from `consumer_file`. Compares the two integers.

## CLI flags

| Flag | Effect |
|------|--------|
| `--root <DIR>` | Root for artefact + consumer resolution. Default `$PWD`. |
| `--config <PATH>` | Explicit config. Else: `$DOC_FANOUT_CONFIG` → `<root>/.doc-fanout.yml` → `$PWD/.doc-fanout.yml`. |
| `--baseline <PATH>` | Explicit ignore file. Else `<root>/.docfanoutignore`. |
| `--no-baseline` | Paranoid mode (CI strict gate). |
| `--allow-cross-root` | Permit consumer paths outside `--root`. |
| `--strict` | severity:warning → exit 1. |
| `--compact` / `--verbose` | Output verbosity. |
| `--quiet` | Suppress `OK:` summary. |

## Severity / exit codes

| Code | Meaning |
|------|---------|
| 0 | Clean (no errors; warnings ok unless `--strict`) |
| 1 | Errors found (or warnings with `--strict`) |
| 2 | Usage / config / path-traversal / fatal parse |

## Pre-commit installer

Run once on the maintainer's dev machine:

```sh
bash Projects/Datarim/code/datarim/dev-tools/install-hook.sh
```

Idempotent. Detects existing hook content and preserves it. The hook
runs the linter only when staged files match the framework or sister-
site paths. Bypass: `git commit --no-verify`.

## Security boundary

- **S1 hardening:** `set -u`, no `eval`, regex-validated config-sourced
  strings before substitution, `grep -F` for literal patterns,
  `canonicalise_path()` for path-traversal guard.
- **No external dependencies:** pure bash + AWK + standard POSIX tools.
- **Hard caps:** config size 256KB, line length 8KB (T3 mitigation).
- **Class B boundary:** the `.doc-fanout.yml v1` schema is a public
  contract for forward compatibility. The CLI surface is private and
  may change between minor versions.

## Versioning policy

The schema (`version: 1`) is independent of framework VERSION. Schema
changes that are not backwards-compatible bump to `version: 2` and must
be documented in `docs/evolution-log.md` together with a migration note.
