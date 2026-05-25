# dev-tools/ — Maintainer-stewarded tooling, runtime-shipped (no user CLI)

> **Runtime-shipped since v2.15.0 (TUNE-0259).** `dev-tools/` is included
> in `INSTALL_SCOPES` and symlinked into `~/.claude/dev-tools/` on default
> installs (copy-mode also copies it). However, the directory remains
> **maintainer-stewarded** — it does NOT expose a user-facing CLI surface.
> Scripts here are invoked exclusively by `/dr-*` commands at runtime (see
> § Runtime consumers below). Treat any direct operator invocation as a
> defect signal.

## Purpose

Maintainer-side utilities for keeping the framework itself in shape, plus
runtime helpers that `/dr-*` commands shell out to (input validation,
schema checks, presence gates, network-exposure verifier, peer-provider
resolver, etc.). Originally a doc-fanout linter only; expanded over
v1.21+ to a broader set of orthogonal pure-shell tools (see § Validation
Discipline in `code/datarim/CLAUDE.md`).

## Runtime consumers (incomplete list)

| Script | Invoked by |
|--------|-----------|
| `check-init-task-presence.sh` | `commands/dr-init.md` Step 4.6 |
| `check-expectations-checklist.sh` | `commands/dr-qa.md`, `commands/dr-compliance.md`, `commands/dr-archive.md` |
| `check-stage-snapshot-on-exit.sh` | `commands/dr-continue.md`, `commands/dr-archive.md`, validator suite |
| `check-skill-frontmatter.sh` | `/dr-plugin doctor` § skill-registry check |
| `check-security-policy.sh` | `/dr-qa` ecosystem security gate, `/dr-compliance` |
| `check-topic-overlap.py` | `commands/dr-init.md` Step 3.5 (backlog similarity) |
| `network-exposure-check.sh`, `network-exposure-gate.sh` | `commands/dr-do.md` Step 8.5 |
| `resolve-peer-provider.sh` | `commands/dr-verify.md` Layer 2 |
| `dr-verify-floor.sh` | `commands/dr-verify.md` Layer 1 |
| `append-init-task-qa.sh` | `commands/dr-{init,prd,plan,design,do,qa,compliance}.md` § Q&A round-trip |

## Why runtime-shipped but no user CLI

1. The scripts encode framework invariants — argument shapes, regex
   schemas, exit-code contracts — that are co-versioned with the `/dr-*`
   commands invoking them. Operator-direct invocation of a stale script
   against a newer command (or vice versa) is a contract-breakage class
   we do not want to expose.
2. Each script self-documents its target scope in its header and is
   pure shell (no runtime deps beyond bash + grep + dev-tools sibling
   scripts). Per § Validation Discipline in `CLAUDE.md`, orthogonal
   concerns get orthogonal tools — no `dev-tools/` script is added as a
   branch inside `datarim-doctor.sh`.
3. Shipping the directory closes a defect class where consumer installs
   via `curl | bash` or `./install.sh --copy` would lack scripts that
   `/dr-*` commands cite as required (e.g. TUNE-0259: 7+ commands
   referenced `dev-tools/check-*` but the directory was unreachable on
   consumer disks).
4. Schema stability is **still** maintainer-internal — relative paths,
   directory layout, count regexes evolve under TUNE-* changes without
   semver guarantees. Consumers MUST NOT script against these tools
   directly.

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
