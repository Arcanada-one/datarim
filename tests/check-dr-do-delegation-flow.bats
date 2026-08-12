#!/usr/bin/env bats
#
# Regression for the /dr-do Step 5.5 "Operator-mandated delegation flow"
# section (commands/dr-do.md) and its /dr-qa Layer 3b cross-check.
#
# Step 5.5 is a prose gate (no standalone script), so the regression locks the
# documented contract so a future edit cannot silently drop it. Covers the two
# cases the gate specifies:
#   (a) the delegation invocation is recorded in § Implementation Notes and
#       /dr-qa Layer 3b cross-checks it against the touched files (PASS path);
#   (b) a silent bypass (no recorded delegation line) is a process regression
#       that /dr-compliance surfaces (FAIL path).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    DO="$REPO_ROOT/commands/dr-do.md"
    QA="$REPO_ROOT/commands/dr-qa.md"
}

@test "dr-do: Operator-mandated delegation flow section is present" {
    grep -qF 'OPERATOR-MANDATED DELEGATION FLOW' "$DO"
}

@test "dr-do delegation (a): records the invocation and Layer 3b cross-checks it" {
    grep -qF '§ Implementation Notes' "$DO"
    grep -qF 'Layer 3b cross-checks this line' "$DO"
}

@test "dr-do delegation (b): silent bypass is a flagged process regression" {
    grep -qF 'Silent bypass = process regression' "$DO"
    grep -qF '/dr-compliance' "$DO"
}

@test "dr-qa: Layer 3b verification surface exists to receive the cross-check" {
    grep -qF 'Layer 3b' "$QA"
}
