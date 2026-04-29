#!/usr/bin/env bats
#
# Tests for scripts/check-doc-refs.sh (TUNE-0054)
#
# Contract under test:
#   Recursively walk markdown files under ROOT and verify that every markdown
#   link `[text](relative/path)` and bare path mention matching
#   `(skills|agents|commands|templates|docs)/.../*.md` resolves to an existing
#   file. Orphans report as "ORPHAN: <file>:<line>: <target>" on stderr and
#   exit 1. Whitelist precedence: inline `<!-- doc-ref:allow path=... -->` on
#   same line > `.docrefignore` glob > orphan. Path traversal rejected with
#   exit 2.
#
# Source: TUNE-0054 plan in datarim/tasks.md, ACs 1-11.

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/check-doc-refs.sh"

setup() {
    cd "$BATS_TEST_TMPDIR"
    mkdir -p tree/skills tree/agents tree/commands tree/templates tree/docs
    cat > tree/CLAUDE.md <<'EOF'
# Root entry point.
EOF
}

# T1: clean tree → exit 0
@test "T1 clean tree with valid markdown link → exit 0" {
    cat > tree/skills/a.md <<'EOF'
# A skill.
See [helper](b.md) for details.
EOF
    cat > tree/skills/b.md <<'EOF'
# B helper.
EOF
    run "$SCRIPT" --root tree --no-baseline
    [ "$status" -eq 0 ]
}

# T2: planted orphan markdown link → exit 1, orphan reported
@test "T2 planted orphan markdown link → exit 1 + orphan listed" {
    cat > tree/skills/a.md <<'EOF'
# A skill.
See [missing](does-not-exist.md) for details.
EOF
    run "$SCRIPT" --root tree --no-baseline
    [ "$status" -eq 1 ]
    echo "$output" | grep -E 'ORPHAN.*skills/a\.md.*does-not-exist\.md'
}

# T3: orphan + matching .docrefignore glob → exit 0
@test "T3 .docrefignore glob suppresses orphan → exit 0" {
    cat > tree/skills/a.md <<'EOF'
# A skill.
See [missing](does-not-exist.md) for details.
EOF
    cat > tree/.docrefignore <<'EOF'
# baseline
skills/does-not-exist.md
EOF
    run "$SCRIPT" --root tree
    [ "$status" -eq 0 ]
}

# T4: orphan + inline marker on same line → exit 0
@test "T4 inline doc-ref:allow marker suppresses orphan → exit 0" {
    cat > tree/skills/a.md <<'EOF'
# A skill.
See [missing](future.md) for details. <!-- doc-ref:allow path=skills/future.md -->
EOF
    run "$SCRIPT" --root tree --no-baseline
    [ "$status" -eq 0 ]
}

# T5 bonus: bare-path mention without markdown brackets → orphan
@test "T5 bare-path mention without brackets → orphan detected" {
    cat > tree/skills/a.md <<'EOF'
# A skill.
Reference: skills/missing-bare.md somewhere in prose.
EOF
    run "$SCRIPT" --root tree --no-baseline
    [ "$status" -eq 1 ]
    echo "$output" | grep -E 'ORPHAN.*skills/missing-bare\.md'
}

# T6 bonus: nested relative path resolves correctly when target exists
@test "T6 nested relative path resolves when target exists → exit 0" {
    mkdir -p tree/skills/sub
    cat > tree/skills/sub/inner.md <<'EOF'
# inner.
See [parent template](../../templates/x.md) for ref.
EOF
    cat > tree/templates/x.md <<'EOF'
# template x.
EOF
    run "$SCRIPT" --root tree --no-baseline
    [ "$status" -eq 0 ]
}

# T7 security: path traversal outside ROOT → exit 2
@test "T7 path traversal outside ROOT → exit 2" {
    cat > tree/skills/a.md <<'EOF'
# A skill.
[escape](../../../../etc/passwd)
EOF
    run "$SCRIPT" --root tree --no-baseline
    [ "$status" -eq 2 ]
}

# T8 hygiene: external links and anchors are skipped
@test "T8 external http(s)/mailto and anchor-only links skipped → exit 0" {
    cat > tree/skills/a.md <<'EOF'
# A skill.
See [docs](https://example.com/x.md) and [mail](mailto:a@b.c) and [section](#anchor).
EOF
    run "$SCRIPT" --root tree --no-baseline
    [ "$status" -eq 0 ]
}

# T9 hygiene: fenced code blocks ignored
@test "T9 markdown links inside fenced code blocks are ignored → exit 0" {
    cat > tree/skills/a.md <<'EOF'
# A skill.
Example:
```
[fake](does-not-exist.md)
```
EOF
    run "$SCRIPT" --root tree --no-baseline
    [ "$status" -eq 0 ]
}

# T10 usage error: missing root → exit 2
@test "T10 missing --root path → exit 2" {
    run "$SCRIPT" --root nonexistent-dir --no-baseline
    [ "$status" -eq 2 ]
}
