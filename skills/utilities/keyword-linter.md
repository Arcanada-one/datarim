# Keyword-Denylist Linter Recipe

Reusable bash recipe for building a keyword-denylist linter — a script that
scans markdown (or any text) for forbidden terms and exits non-zero on
match. Source pattern: `scripts/stack-agnostic-gate.sh` (TUNE-0039).

Use when promoting a recurring user-memory rule to an executable gate at
an apply step (see `skills/evolution.md` § Pattern: Memory Rule →
Executable Gate at Apply Step).

## Anatomy

1. **Denylist as a top-of-file array literal** — single source of truth.
   Extending the rule = editing one literal.
2. **Whitelist as a default array + repeatable `--whitelist` flag** —
   files / paths exempt by design (e.g. the rule's own contract document).
   Whitelist match should be path-suffix based, not glob — predictable for
   reviewers.
3. **`grep -wEi` for matching** — `-w` (whole-word) prevents the classic
   <!-- gate:example-only -->
   false-positive trap (e.g. `RSpec` matching inside `perspective`). `-E`
   <!-- /gate:example-only -->
   for ERE regex (literal dot escapes `\.` work). `-i` for case-insensitive.
4. **Per-block escape hatch** — HTML-comment fence pair like
   `<!-- gate:example-only -->` ... `<!-- /gate:example-only -->` skipped
   by an `awk` strip pass. Preserves line numbers by emitting blank lines
   for skipped content (so `grep -n` output still maps to the original).
5. **Exit codes:** `0` clean / `1` matches found / `2` invocation error.
   Stable contract for CI.
6. **Recursive directory mode** — `find <dir> -type f -name '*.md'` with
   exclusions for `tests/fixtures/`, `node_modules/`, `.git/`. Fixtures
   are intentionally violations and must not self-trigger.

## Skeleton

```bash
#!/usr/bin/env bash
set -euo pipefail

DENYLIST=(
    "Foo"
    "bar baz"
)

WHITELIST=("path/to/contract.md")

# Argument parsing: <target> + repeated --whitelist <path> + --reset-whitelist + --help

is_whitelisted() {
    local path="$1"
    for entry in "${WHITELIST[@]:-}"; do
        [ -n "$entry" ] || continue
        case "$path" in *"$entry") return 0 ;; esac
    done
    return 1
}

strip_example_blocks() {
    awk '
        /<!-- gate:example-only -->/ { skip=1; print ""; next }
        /<!-- \/gate:example-only -->/ { skip=0; print ""; next }
        { if (skip) print ""; else print }
    ' "$1"
}

scan_file() {
    local file="$1"
    is_whitelisted "$file" && return 0
    local stripped; stripped="$(strip_example_blocks "$file")"
    local hits=0
    for kw in "${DENYLIST[@]}"; do
        while IFS= read -r match; do
            [ -n "$match" ] || continue
            local line_no="${match%%:*}"
            local context="${match#*:}"
            printf '%s:%s:%s: %s\n' "$file" "$line_no" "$kw" "$context" >&2
            hits=$((hits + 1))
        done < <(printf '%s\n' "$stripped" | grep -n -w -i -E -- "$kw" || true)
    done
    return "$hits"
}

# main: scan_path "$TARGET" → tally → exit 0/1
```

## Bats fixture pattern

Three fixtures + one regression invariant test minimum:

- `tests/fixtures/<linter>/golden-fail.md` — golden FAIL fixture
  reproducing the original incident verbatim. Asserts `exit 1`.
- `tests/fixtures/<linter>/legitimate-pass.md` — golden PASS fixture
  for a non-trivial valid case. Asserts `exit 0`.
- `tests/fixtures/<linter>/whitelist-test.md` — fixture full of denylist
  hits + invoked with the whitelist flag pointing at it. Asserts `exit 0`.
- **Regression invariant:** assert the linter passes on its own host
  command/skill file. If a future edit re-introduces the violation, the
  test sets the alarm before review.

## Gotchas

- **`-w` is non-negotiable for single-word patterns.** Without it,
  any short keyword false-positives inside longer English words.
  Multi-word patterns (`npm install`) still benefit — `-w` requires word
  boundaries on both ends.
- **macOS BSD `grep` differs from GNU.** Test on macOS default bash
  (3.2.x) before claiming portability. Avoid `\b`, `[[:<:]]`, `[[:>:]]` —
  use `-w` instead.
- **Don't shellcheck-ignore `SC2086` blindly** when scanning user-supplied
  paths. The linter is read-only by contract — no `eval`, no command
  substitution on file content.
- **Symlink runtime:** if the rule guards `~/.claude/{skills,agents,...}`
  and they are symlinks to a repo, the linter sees one logical surface.
  No need to scan twice.

## When NOT to use this pattern

- The rule is a one-off, not recurring. A code review comment is enough.
- The rule needs semantic understanding (typing, control flow, dependency
  resolution) — promote to a real linter (eslint plugin, ruff rule, etc.),
  not a grep-script.
- The rule produces frequent false-positives that cannot be resolved by
  word-boundary + whitelist + escape-hatch — abandon the gate, document
  the rule textually instead.
