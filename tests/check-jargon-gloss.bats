#!/usr/bin/env bats
#
# Contract test for dev-tools/check-jargon-gloss.sh.
#
# Verifies the validator enforces inline gloss on first use of every
# framework-internal jargon term enumerated in dev-tools/data/jargon-bank.txt.
# Three cases per acceptance criterion (V-AC-5 of PRD-TUNE-0308):
#   (a) term + parenthetical gloss within 80 chars → exit 0
#   (b) term + markdown-link gloss within 80 chars → exit 0
#   (c) term without any gloss on first use         → exit 1

setup() {
    REPO_ROOT="$(git -C "$BATS_TEST_DIRNAME/.." rev-parse --show-toplevel)"
    SCRIPT="$REPO_ROOT/dev-tools/check-jargon-gloss.sh"
    [ -x "$SCRIPT" ] || skip "check-jargon-gloss.sh not executable"

    TMPDIR_TEST="$(mktemp -d)"
    git init --quiet "$TMPDIR_TEST"
    mkdir -p "$TMPDIR_TEST/commands" "$TMPDIR_TEST/dev-tools/data"
    cat > "$TMPDIR_TEST/dev-tools/data/jargon-bank.txt" <<'EOF'
# Test manifest
CTA block
Stage Header
EOF
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

@test "term followed by parenthetical gloss within 80 chars passes" {
    cat > "$TMPDIR_TEST/commands/sample.md" <<'EOF'
# Sample command

The CTA block (the standard call-to-action paragraph) appears at the end.
The Stage Header (bold task ID prefix) opens the response.
EOF
    run "$SCRIPT" --root "$TMPDIR_TEST" --scope commands --manifest "$TMPDIR_TEST/dev-tools/data/jargon-bank.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT: PASS"* ]]
}

@test "term followed by markdown-link gloss within 80 chars passes" {
    cat > "$TMPDIR_TEST/commands/sample.md" <<'EOF'
# Sample command

Emit a CTA block ([defined here](cta-format.md)) at the end of the response.
Open with a Stage Header ([source](cta-format.md)) per the contract.
EOF
    run "$SCRIPT" --root "$TMPDIR_TEST" --scope commands --manifest "$TMPDIR_TEST/dev-tools/data/jargon-bank.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT: PASS"* ]]
}

@test "term without any gloss on first use fails" {
    cat > "$TMPDIR_TEST/commands/sample.md" <<'EOF'
# Sample command

Emit a CTA block at the end of the response without any inline gloss text.
Open with a Stage Header per the contract without any gloss text.
EOF
    run "$SCRIPT" --root "$TMPDIR_TEST" --scope commands --manifest "$TMPDIR_TEST/dev-tools/data/jargon-bank.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"CTA block"* ]]
    [[ "$output" == *"Stage Header"* ]]
}

@test "manifest comments and blank lines are ignored" {
    cat > "$TMPDIR_TEST/dev-tools/data/jargon-bank.txt" <<'EOF'
# Comment line

CTA block

# Another comment
EOF
    cat > "$TMPDIR_TEST/commands/sample.md" <<'EOF'
# Sample

The CTA block (the call-to-action paragraph) is fine here.
EOF
    run "$SCRIPT" --root "$TMPDIR_TEST" --scope commands --manifest "$TMPDIR_TEST/dev-tools/data/jargon-bank.txt"
    [ "$status" -eq 0 ]
}

@test "missing manifest file returns usage error" {
    run "$SCRIPT" --root "$TMPDIR_TEST" --scope commands --manifest "$TMPDIR_TEST/does-not-exist.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"manifest not found"* ]]
}

@test "frontmatter is skipped" {
    cat > "$TMPDIR_TEST/commands/sample.md" <<'EOF'
---
title: CTA block reference in frontmatter
---

The CTA block (the call-to-action paragraph) appears here in the body.
EOF
    run "$SCRIPT" --root "$TMPDIR_TEST" --scope commands --manifest "$TMPDIR_TEST/dev-tools/data/jargon-bank.txt"
    [ "$status" -eq 0 ]
}

@test "fenced code blocks are skipped for first-use detection" {
    cat > "$TMPDIR_TEST/commands/sample.md" <<'EOF'
# Sample

Inside the fence the term should not count as first-use:

```
# CTA block — inside a fence, must not trigger the validator
```

The CTA block (the call-to-action paragraph) appears here in real prose.
EOF
    run "$SCRIPT" --root "$TMPDIR_TEST" --scope commands --manifest "$TMPDIR_TEST/dev-tools/data/jargon-bank.txt"
    [ "$status" -eq 0 ]
}
