#!/usr/bin/env bats
# Tests for dev-tools/rename-task-prefix.sh + lib/prefix-rename-classify.py (TUNE-0368).
# Usage: bats dev-tools/tests/rename-task-prefix.bats
#
# Covers V-AC-01..07 from PRD-TUNE-0368: content rename, collision-safe anchoring,
# literal (slash / middle-dot) handling, file rename + orphan-free, dry-run no-op,
# verify pass/fail exit codes, and an ASCII-clean shipped surface.

ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SH="$ROOT/dev-tools/rename-task-prefix.sh"
PY="$ROOT/dev-tools/lib/prefix-rename-classify.py"

setup() {
    TMP="$(mktemp -d)"
    cd "$TMP"
    git init -q
    git config user.email t@example.com
    git config user.name tester
    mkdir -p datarim/tasks documentation/architecture
    MDOT="$(printf '\xc2\xb7')"   # U+00B7 middle dot, kept out of this .bats as raw bytes

    # Unambiguous-prefix scenario (OLD-0007) + a collision scenario (ADR-0001 homograph).
    {
        printf -- '- OLD-0007 %s pending %s P3 %s L2 %s Some task -> tasks/OLD-0007-x.md\n' \
            "$MDOT" "$MDOT" "$MDOT" "$MDOT"
        printf -- '- ADR-0001 %s pending %s P1 %s L2 %s Adsessor bootstrap -> tasks/ADR-0001-y.md\n' \
            "$MDOT" "$MDOT" "$MDOT" "$MDOT"
        printf 'See architecture/ADR-0001-file-sync-policy for the sync mandate.\n'
    } > datarim/backlog.md

    printf '# OLD-0007\nBody referencing OLD-0007 again.\n' > datarim/tasks/OLD-0007-x.md

    printf -- '---\nid: ADR-0001\n---\nArchitecture Decision Record ADR-0001 file-sync-policy.\n' \
        > documentation/architecture/ADR-0001-file-sync-policy.md

    printf 'See OLD-0007 for details.\n| OLD | Foo project | foo |\n' > CLAUDE.md
    git add -A
    git commit -qm init
}

teardown() {
    cd /
    rm -rf "$TMP"
}

@test "V-AC-01 content rename of unambiguous prefix across scope" {
    run "$SH" --old OLD --new NEW --path datarim --path CLAUDE.md --apply
    [ "$status" -eq 0 ]
    grep -q 'NEW-0007' datarim/backlog.md
    ! grep -q 'OLD-0007' datarim/backlog.md
    grep -q 'NEW-0007' CLAUDE.md
    # registry row (bare `OLD`, not a token) stays untouched -- out of scope by design
    grep -q '| OLD | Foo project | foo |' CLAUDE.md
}

@test "V-AC-02 exclude-anchor protects homograph; collision+include renames index" {
    run "$SH" --old ADR --new ADSR --path datarim --path documentation \
        --collision-number 0001 --include-anchor "$MDOT" --exclude-anchor file-sync --apply
    [ "$status" -eq 0 ]
    # index line has the include-anchor and no exclude-anchor -> renamed
    grep -q "ADSR-0001 $MDOT pending" datarim/backlog.md
    # backlog file-sync reference line kept (exclude-anchor wins on the whole line)
    grep -q 'architecture/ADR-0001-file-sync-policy' datarim/backlog.md
    # homograph doc untouched (no include-anchor on id line; file-sync on prose line)
    grep -q '^id: ADR-0001' documentation/architecture/ADR-0001-file-sync-policy.md
}

@test "V-AC-03 classifier handles slash and middle-dot literally; py_compile clean" {
    python3 -m py_compile "$PY"
    run python3 "$PY" --old ADR --new ADSR --path datarim \
        --collision-number 0001 --include-anchor "$MDOT" --exclude-anchor file-sync --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'KEEP'
    echo "$output" | grep -q 'RENAME'
}

@test "V-AC-04 --rename-files git-mv + no orphan cross-link" {
    run "$SH" --old OLD --new NEW --path datarim --rename-files --apply
    [ "$status" -eq 0 ]
    [ -f datarim/tasks/NEW-0007-x.md ]
    [ ! -f datarim/tasks/OLD-0007-x.md ]
    grep -q 'NEW-0007' datarim/tasks/NEW-0007-x.md
    ! grep -rq 'tasks/OLD-0007' .
    git status --porcelain | grep -qE '^R'
}

@test "V-AC-05 --dry-run (default) writes nothing and prints plan" {
    run "$SH" --old OLD --new NEW --path datarim --path CLAUDE.md
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'RENAME'
    [ -z "$(git status --porcelain)" ]
}

@test "V-AC-06 verify passes clean, fails on half-rename residue" {
    "$SH" --old OLD --new NEW --path datarim --path CLAUDE.md --apply
    run "$SH" --old OLD --new NEW --path datarim --path CLAUDE.md --verify
    [ "$status" -eq 0 ]
    printf -- '- OLD-0009 stray residue\n' >> datarim/backlog.md
    run "$SH" --old OLD --new NEW --path datarim --path CLAUDE.md --verify
    [ "$status" -eq 1 ]
    echo "$output" | grep -q 'OLD-0009'
}

@test "V-AC-07 shipped surface (script + lib) is ASCII-clean" {
    ! grep -qP '[^\x00-\x7F]' "$SH"
    ! grep -qP '[^\x00-\x7F]' "$PY"
}
