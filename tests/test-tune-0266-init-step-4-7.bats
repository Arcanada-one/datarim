#!/usr/bin/env bats
# test-tune-0266-init-step-4-7.bats — Phase 2 /dr-init Step 4.7 contract tests.
#
# These are CONTRACT tests (grep-based against markdown command files), not
# executable tests of /dr-init itself — /dr-init is agent-consumed markdown,
# not a binary. The actual wish-extraction is LLM-driven (per creative
# decision Option B in creative-TUNE-0266-algorithm-wish-extraction.md);
# its quality is verified at /dr-qa Layer 3b via the qa-report per-wish
# block contract.
#
# Covers:
#   - dr-init.md Step 4.7 presence + key contract markers
#   - dr-prd.md Step 5.5b demoted to append-merge-only (TUNE-0266 contract)
#   - dr-plan.md Step 5b demoted to append-merge-only (TUNE-0266 contract)
#   - Mandate scope L1-L4 declared explicitly in dr-init.md
#
# Companion plan: datarim/plans/TUNE-0266-plan.md § Phase 2.

CMDS_DIR="$BATS_TEST_DIRNAME/../commands"

# --- dr-init.md Step 4.7 -----------------------------------------------------

@test "dr-init.md contains Step 4.7 WRITE EXPECTATIONS SKELETON" {
    grep -q "^4\.7\. \*\*WRITE EXPECTATIONS SKELETON\*\*" "$CMDS_DIR/dr-init.md"
}

@test "dr-init.md Step 4.7 references expectations-checklist.md skill" {
    grep -A 1 "^4\.7\. \*\*WRITE EXPECTATIONS SKELETON\*\*" "$CMDS_DIR/dr-init.md" \
        | grep -q "expectations-checklist/SKILL.md"
}

@test "dr-init.md Step 4.7 mandates all complexity levels L1-L4" {
    # Search the body of Step 4.7 (between heading line and next top-level step)
    awk '/^4\.7\./{flag=1} /^5\.  /{flag=0} flag' "$CMDS_DIR/dr-init.md" \
        | grep -q "L1-L4"
}

@test "dr-init.md Step 4.7 references schema_version 2" {
    awk '/^4\.7\./{flag=1} /^5\.  /{flag=0} flag' "$CMDS_DIR/dr-init.md" \
        | grep -q "schema_version: 2"
}

@test "dr-init.md Step 4.7 references evidence_type default empirical" {
    awk '/^4\.7\./{flag=1} /^5\.  /{flag=0} flag' "$CMDS_DIR/dr-init.md" \
        | grep -E "evidence_type.*empirical" >/dev/null
}

@test "dr-init.md Step 4.7 declares skip-if-exists guard" {
    awk '/^4\.7\./{flag=1} /^5\.  /{flag=0} flag' "$CMDS_DIR/dr-init.md" \
        | grep -iE "skip silently|already exists" >/dev/null
}

@test "dr-init.md Step 4.7 declares fallback for empty/diffuse brief" {
    awk '/^4\.7\./{flag=1} /^5\.  /{flag=0} flag' "$CMDS_DIR/dr-init.md" \
        | grep -iE "fallback|TBD|оператор уточняет" >/dev/null
}

@test "dr-init.md Step 4.7 invokes check-expectations-checklist.sh probe" {
    awk '/^4\.7\./{flag=1} /^5\.  /{flag=0} flag' "$CMDS_DIR/dr-init.md" \
        | grep -q "check-expectations-checklist.sh"
}

# --- dr-prd.md Step 5.5b demoted to append-merge-only ------------------------

@test "dr-prd.md Step 5.5b retitled to Append-merge (TUNE-0266 contract)" {
    grep -q "^5\.5b\. \*\*Append-merge expectations checklist" "$CMDS_DIR/dr-prd.md"
}

@test "dr-prd.md Step 5.5b explicitly defers creation to /dr-init Step 4.7" {
    awk '/^5\.5b\./{flag=1} /^5\.5\. /{flag=0} flag' "$CMDS_DIR/dr-prd.md" \
        | grep -q "Step 4.7"
}

@test "dr-prd.md Step 5.5b removes 'create or update' language (no scratch creation)" {
    awk '/^5\.5b\./{flag=1} /^5\.5\. /{flag=0} flag' "$CMDS_DIR/dr-prd.md" \
        | grep -qv "MUST create or update"
}

@test "dr-prd.md Step 5.5b preserves Append-merge contract reference" {
    awk '/^5\.5b\./{flag=1} /^5\.5\. /{flag=0} flag' "$CMDS_DIR/dr-prd.md" \
        | grep -iE "append-merge|append at the bottom" >/dev/null
}

# --- dr-plan.md Step 5b demoted to append-merge-only -------------------------

@test "dr-plan.md Step 5b retitled to Append-merge (TUNE-0266 contract)" {
    grep -q "^5b\. \*\*Append-merge expectations checklist" "$CMDS_DIR/dr-plan.md"
}

@test "dr-plan.md Step 5b explicitly defers creation to /dr-init Step 4.7" {
    awk '/^5b\./{flag=1} /^6\.  /{flag=0} flag' "$CMDS_DIR/dr-plan.md" \
        | grep -q "Step 4.7"
}

@test "dr-plan.md Step 5b removes 'create or update' scratch language" {
    awk '/^5b\./{flag=1} /^6\.  /{flag=0} flag' "$CMDS_DIR/dr-plan.md" \
        | grep -qv "MUST create or update"
}

# --- Cross-command consistency ----------------------------------------------

@test "Steps 5.5b and 5b consistently reference Step 4.7 in /dr-init" {
    # Both files MUST cite Step 4.7 as the creation moment.
    grep -lq "Step 4.7" "$CMDS_DIR/dr-prd.md"
    grep -lq "Step 4.7" "$CMDS_DIR/dr-plan.md"
}
