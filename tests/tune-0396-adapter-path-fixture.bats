#!/usr/bin/env bats
#
# TUNE-0396 E1 — spec-regression for the Adapter-Path Fixture rule in
# skills/testing/SKILL.md (source: reflection-AUTH-0091 § E1).
#
# Contract: the testing skill MUST carry a dedicated `## Adapter-Path Fixture`
# subsection that (a) mandates the real DB-row -> mapper -> output path, (b)
# requires the spec to be red-on-revert (fail if the mapper is reverted), and
# (c) explicitly distinguishes this blind spot from the class-exists-but-not-
# wired pattern, naming the sub-pattern. Wording MUST be stack-neutral (no
# ecosystem-specific project / task-ID / org names).

FRAGMENT="${BATS_TEST_DIRNAME}/../skills/testing/SKILL.md"

@test "testing SKILL.md exists" {
    [ -f "$FRAGMENT" ]
}

@test "'## Adapter-Path Fixture' subsection header is present" {
    run grep -E "^## Adapter-Path Fixture\b" "$FRAGMENT"
    [ "$status" -eq 0 ]
}

# Body spans from the subsection header to the next H2 (or EOF).
_body() {
    local start next
    start=$(grep -n "^## Adapter-Path Fixture\b" "$FRAGMENT" | head -1 | cut -d: -f1)
    [ -n "$start" ] || return 1
    next=$(awk -v s="$start" 'NR>s && /^## / {print NR; exit}' "$FRAGMENT")
    [ -z "$next" ] && next=$(wc -l < "$FRAGMENT")
    sed -n "${start},${next}p" "$FRAGMENT"
}

@test "mandates the real row -> mapper -> output path" {
    _body | grep -qiE "row *(→|->) *mapper *(→|->) *output"
}

@test "requires red-on-revert (revert the mapper -> spec goes red)" {
    body=$(_body)
    printf '%s' "$body" | grep -qiE "revert"
    printf '%s' "$body" | grep -qiE "\bred\b"
}

@test "distinguishes the class-exists-but-not-wired pattern and names the sub-pattern" {
    body=$(_body)
    # Names the sibling pattern it is NOT a duplicate of ...
    printf '%s' "$body" | grep -qiE "class-exists|not-wired|wired in production"
    # ... and names this sub-pattern explicitly.
    printf '%s' "$body" | grep -qiE "hand-built-fixture masks mapper transformation"
}

@test "wording is stack-neutral (no project / task-ID / org names)" {
    ! _body | grep -qiE "Auth Arcana|\b[A-Z]{2,10}-[0-9]{4}\b|Arcanada"
}
