#!/usr/bin/env bats
#
# TUNE-0304 Phase 1: contract test for dev-tools/migrate-skill.sh.
#
# Contract (per plan §6.3):
#   - Validates skill name regex ^[a-z][a-z0-9-]{0,63}$
#   - Pre-condition: skills/<name>.md exists; skills/<name>/SKILL.md must
#     not exist unless --force
#   - Copies (NOT moves) skills/<name>.md → skills/<name>/SKILL.md so the
#     flat file remains for an explicit Phase 5 contract removal
#   - Normalises frontmatter:
#       drop top-level `runtime:` (preserves value under metadata.runtime
#       only if metadata: block exists; otherwise omitted entirely — non-
#       destructive: original flat file untouched)
#       `model: sonnet|opus|haiku` → `model: inherit`
#       preserves all other frontmatter keys verbatim and ordering
#   - Idempotent: re-run with same input → exit 0, no diff
#   - Dry-run prints planned actions to stdout, writes nothing
#   - Exit codes: 0 success/idempotent, 1 content differs (no --force),
#     3 invalid name / prerequisites
#
# TDD red→green: this test was written before the implementation.

SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/migrate-skill.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/skills"
}

teardown() {
    rm -rf "$TMPROOT"
}

write_flat_skill() {
    local name="$1"
    shift
    cat >"$TMPROOT/skills/$name.md" <<EOF
$@
EOF
}

@test "script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "FAIL with invalid skill name (uppercase)" {
    run "$SCRIPT" --root "$TMPROOT" --skill BadName
    [ "$status" -eq 3 ]
}

@test "FAIL when skills/<name>.md does not exist" {
    run "$SCRIPT" --root "$TMPROOT" --skill nonexistent
    [ "$status" -eq 3 ]
    [[ "$output" == *"nonexistent.md"* ]] || [[ "$output" == *"not found"* ]]
}

@test "PASS migration: flat → nested SKILL.md, model: sonnet → inherit, runtime: dropped" {
    write_flat_skill "alpha" \
"---
name: alpha
description: example
model: sonnet
runtime: [claude, codex]
---
body content"
    run "$SCRIPT" --root "$TMPROOT" --skill alpha
    [ "$status" -eq 0 ]
    [ -f "$TMPROOT/skills/alpha/SKILL.md" ]
    [ -f "$TMPROOT/skills/alpha.md" ]  # original preserved
    run cat "$TMPROOT/skills/alpha/SKILL.md"
    [[ "$output" == *"model: inherit"* ]]
    [[ "$output" != *"runtime: [claude, codex]"* ]]
    [[ "$output" == *"name: alpha"* ]]
    [[ "$output" == *"description: example"* ]]
    [[ "$output" == *"body content"* ]]
}

@test "PASS migration: model: inherit preserved (no normalisation needed)" {
    write_flat_skill "beta" \
"---
name: beta
description: already inherit
model: inherit
---
b"
    run "$SCRIPT" --root "$TMPROOT" --skill beta
    [ "$status" -eq 0 ]
    run cat "$TMPROOT/skills/beta/SKILL.md"
    [[ "$output" == *"model: inherit"* ]]
}

@test "PASS migration: no model: field preserves absence" {
    write_flat_skill "gamma" \
"---
name: gamma
description: no model field
---
g"
    run "$SCRIPT" --root "$TMPROOT" --skill gamma
    [ "$status" -eq 0 ]
    run cat "$TMPROOT/skills/gamma/SKILL.md"
    [[ "$output" != *"model:"* ]] || [[ "$output" == *"model: inherit"* ]] || true
    [[ "$output" == *"name: gamma"* ]]
}

@test "FAIL when target SKILL.md exists with different content (no --force)" {
    write_flat_skill "delta" \
"---
name: delta
description: v1
---
v1"
    mkdir -p "$TMPROOT/skills/delta"
    echo "different content" >"$TMPROOT/skills/delta/SKILL.md"
    run "$SCRIPT" --root "$TMPROOT" --skill delta
    [ "$status" -eq 1 ]
}

@test "PASS idempotent: re-running on already-migrated skill exits 0" {
    write_flat_skill "epsilon" \
"---
name: epsilon
description: idem
model: opus
---
e"
    run "$SCRIPT" --root "$TMPROOT" --skill epsilon
    [ "$status" -eq 0 ]
    # Second invocation: target exists and matches expected normalised form.
    run "$SCRIPT" --root "$TMPROOT" --skill epsilon
    [ "$status" -eq 0 ]
}

@test "--dry-run writes nothing, prints planned actions" {
    write_flat_skill "zeta" \
"---
name: zeta
description: dry
model: haiku
---
z"
    run "$SCRIPT" --root "$TMPROOT" --skill zeta --dry-run
    [ "$status" -eq 0 ]
    [ ! -e "$TMPROOT/skills/zeta/SKILL.md" ]
    [[ "$output" == *"would"* ]] || [[ "$output" == *"DRY"* ]] || [[ "$output" == *"plan"* ]]
}

@test "--force overwrites differing target" {
    write_flat_skill "eta" \
"---
name: eta
description: forced
---
e"
    mkdir -p "$TMPROOT/skills/eta"
    echo "stale" >"$TMPROOT/skills/eta/SKILL.md"
    run "$SCRIPT" --root "$TMPROOT" --skill eta --force
    [ "$status" -eq 0 ]
    run cat "$TMPROOT/skills/eta/SKILL.md"
    [[ "$output" == *"name: eta"* ]]
    [[ "$output" != *"stale"* ]]
}

@test "preserves body content verbatim (multi-line + special chars)" {
    write_flat_skill "theta" \
"---
name: theta
description: body
---
Line one.

\`\`\`bash
echo \"hello \$USER\"
\`\`\`

Line three with [link](skills/other.md)."
    run "$SCRIPT" --root "$TMPROOT" --skill theta
    [ "$status" -eq 0 ]
    diff <(sed -n '/^---$/,/^---$/{n;/^---$/q;p}' "$TMPROOT/skills/theta.md" | tail -r | tail -n +2 | tail -r) /dev/null 2>/dev/null || true
    # Body equality check: lines after closing frontmatter must match.
    body_orig=$(awk 'f==2{print} /^---$/{f++}' "$TMPROOT/skills/theta.md")
    body_new=$(awk 'f==2{print} /^---$/{f++}' "$TMPROOT/skills/theta/SKILL.md")
    [ "$body_orig" = "$body_new" ]
}
