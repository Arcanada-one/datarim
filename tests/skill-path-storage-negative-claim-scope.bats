#!/usr/bin/env bats
#
# Anti-decay spec-regression: skills/datarim-system/path-and-storage.md must
# carry the Negative-Claim Scope Precondition — negative claims about the
# knowledge base must be grounded in the canonical KB root, never in the
# partial datarim/ skeleton inside a git worktree — plus the two companion
# rules (literal-term search; canonical accepted doc outranks local note).

FRAGMENT="${BATS_TEST_DIRNAME}/../skills/datarim-system/path-and-storage.md"

@test "fragment file exists" {
    [ -f "$FRAGMENT" ]
}

@test "Negative-Claim Scope Precondition section header present" {
    run grep -cE "^## Negative-Claim Scope Precondition" "$FRAGMENT"
    [ "$status" -eq 0 ]
}

@test "section explains the worktree partial-skeleton trap" {
    run grep -ciE "git worktree" "$FRAGMENT"
    [ "$status" -eq 0 ]
    run grep -ciE "gitignored" "$FRAGMENT"
    [ "$status" -eq 0 ]
    run grep -ciE "partial skeleton" "$FRAGMENT"
    [ "$status" -eq 0 ]
}

@test "cheap precondition command (subdirectory-count comparison) present" {
    run grep -cF 'ls -d datarim/*/ | wc -l' "$FRAGMENT"
    [ "$status" -eq 0 ]
}

@test "lower count declares the scope unfit for negative claims" {
    run grep -ciE "unfit for negative claims" "$FRAGMENT"
    [ "$status" -eq 0 ]
}

@test "companion rule (a): search the literal term" {
    run grep -ciE "literal term" "$FRAGMENT"
    [ "$status" -eq 0 ]
}

@test "companion rule (b): canonical status: accepted outranks local note" {
    run grep -cE "status: accepted" "$FRAGMENT"
    [ "$status" -eq 0 ]
    run grep -ciE "outranks" "$FRAGMENT"
    [ "$status" -eq 0 ]
}

@test "section carries no personal absolute paths" {
    sec_line=$(grep -nE "^## Negative-Claim Scope Precondition" "$FRAGMENT" | head -1 | cut -d: -f1)
    [ -n "$sec_line" ]
    next_h2=$(awk -v start="$sec_line" 'NR>start && /^## / {print NR; exit}' "$FRAGMENT")
    [ -n "$next_h2" ] || next_h2=$(wc -l < "$FRAGMENT")
    body=$(sed -n "${sec_line},${next_h2}p" "$FRAGMENT")
    count=$(printf '%s\n' "$body" | grep -cE "/home/[a-z]|/Users/[a-z]" || true)
    [ "$count" -eq 0 ]
}
