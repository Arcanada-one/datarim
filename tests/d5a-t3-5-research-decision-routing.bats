#!/usr/bin/env bats
# D5A-T3.5 — research decision routing stays within existing lifecycle.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

@test "profile-active PRD route requires current accepted DecisionRecord, ProductBrief, and explicit scope authorization" {
    grep -q 'D5A research decision handoff' "$REPO_ROOT/commands/dr-prd.md"
    grep -q 'authorization_ref' "$REPO_ROOT/commands/dr-prd.md"
    grep -q 'ProductBrief' "$REPO_ROOT/commands/dr-prd.md"
    grep -q 'superseded' "$REPO_ROOT/commands/dr-prd.md"
}

@test "research routing preserves outcomes and never lets snapshots grant authority" {
    grep -q 'stop.*archive' "$REPO_ROOT/commands/dr-auto.md"
    grep -q 'more-evidence' "$REPO_ROOT/commands/dr-auto.md"
    grep -q 'delivery_authorized' "$REPO_ROOT/skills/stage-snapshot-writer/SKILL.md"
    grep -q 'context, not authority' "$REPO_ROOT/skills/dr-next-snapshot-replay/SKILL.md"
    grep -q 'revalidate' "$REPO_ROOT/commands/dr-next.md"
}

@test "missing DecisionRecord or scope-advance storage convention is disclosed for review" {
    grep -q 'reviewer confirmation' "$REPO_ROOT/commands/dr-prd.md"
    grep -q 'proposes, pending reviewer confirmation' "$REPO_ROOT/plugins/product-discovery/README.md"
}
