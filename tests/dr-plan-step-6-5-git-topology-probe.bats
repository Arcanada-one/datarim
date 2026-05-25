#!/usr/bin/env bats
# TUNE-0269 — Step 6.5 git topology probe contract regression guard.
# Anchor-based extraction (robust to bullet relocation, BSD vs GNU sed/awk).

DR_PLAN="$BATS_TEST_DIRNAME/../commands/dr-plan.md"

# Extract the bullet block: from header "Git topology probe" to next sibling
# bullet (line starting with 4-space-indent `-   **`). Case-insensitive via
# tolower() — portable across BSD awk (macOS) and GNU awk (Linux/CI).
bullet_block() {
    awk 'tolower($0) ~ /git topology probe/ {flag=1; print; next}
         flag && /^    -   \*\*/ {exit}
         flag {print}' "$DR_PLAN"
}

@test "Step 6.5 contains 'Git topology probe' bullet" {
    run grep -ci 'Git topology probe' "$DR_PLAN"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "Git topology probe bullet prescribes 'git check-ignore' WITHIN the bullet" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"git check-ignore"* ]]
}

@test "Git topology probe bullet quotes path and uses -- separator (S1/S5 hardening)" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *'-- "$path"'* ]]
}

@test "Git topology probe bullet disambiguates gitignored vs non-git via rev-parse" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"rev-parse --is-inside-work-tree"* ]]
}

@test "Git topology probe bullet ties result to non-git restore mechanism in Rollback Strategy" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"Rollback Strategy"* ]]
    # Body-depth assertion: non-git mechanism must be named explicitly AND bound to
    # the "gitignored" trigger context (mechanism words appearing in isolation are
    # insufficient — they must be the documented response to a gitignored path).
    # Flatten newlines before regex match: bash 3.2 `=~` does not match `.` across
    # newlines portably; flattening is the cross-version (macOS / Linux) safe path.
    local block_flat; block_flat=$(printf '%s' "$block" | tr '\n' ' ')
    [[ "$block_flat" =~ gitignored.*(backup-then-overwrite|cp[[:space:]]+from[[:space:]]+snapshot|deploy-script[[:space:]]+re-run) ]]
}
