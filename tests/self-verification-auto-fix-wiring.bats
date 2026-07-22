#!/usr/bin/env bats
#
# Guarded Auto-Fix Policy documentation wiring (TUNE-0140).
#
# The guarded deterministic auto-fix policy layers onto the shipped TUNE-0138
# automatic post-step self-verification hook. The mutation runner
# (`dev-tools/self-verify-auto-fix.sh`) and the read-only floor extension are
# exercised by `tests/self-verification-auto-fix-policy.bats`. These checks pin
# the SHIPPED DOC SURFACE so the bounded policy cannot silently drift into an
# unbounded or manual-command auto-fix:
#   (a) the canonical skill spec carries the closed eligibility, immutable
#       history authority, bounded loop, and audit-visibility contract,
#   (b) every hooked stage command names the runner and the one-at-a-time loop,
#   (c) the peer reviewer can never author or invoke a mutation,
#   (d) manual `/dr-verify` stays findings-only and cannot reach the runner,
#   (e) the Class B operator surface (CLAUDE.md, README, commands reference)
#       distinguishes the guarded automatic path from manual findings-only.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SKILL="${REPO_ROOT}/skills/self-verification/SKILL.md"
MANUAL="${REPO_ROOT}/commands/dr-verify.md"

# Commands that carry the automatic post-step self-verification hook.
HOOK_COMMANDS=(
    "dr-prd"
    "dr-plan"
    "dr-do"
)

@test "TUNE-0140: skill orders floor, guarded auto-fix, then reviewers via the runner" {
    grep -Fq 'deterministic floor → guarded auto-fix loop → model reviewer dispatch' "$SKILL"
    grep -Fq 'dev-tools/self-verify-auto-fix.sh' "$SKILL"
}

@test "TUNE-0140: skill closes eligibility to low-risk classes and excludes sensitive ones" {
    grep -Fq 'Security, authentication, secrets, production data, model-authored fixes, unknown classes, and unverified evidence are never auto-fixed' "$SKILL"
}

@test "TUNE-0140: history authority is a fixed namespace no caller or finding can substitute" {
    grep -Fq 'datarim/qa/self-verification-auto-fix-history/records/' "$SKILL"
    grep -Fq 'cannot substitute a history path' "$SKILL"
    grep -Fq 'strict `10 * false_positive < 3 * total`' "$SKILL"
    grep -Fq 'strictly below 30 percent' "$SKILL"
}

@test "TUNE-0140: mutation loop is bounded and refreshes stale preimages" {
    grep -Fq '32 total runner invocations' "$SKILL"
    grep -Fq 'Never select a second finding from a pre-mutation floor result' "$SKILL"
    grep -Fq 'attempted-finding set for that unchanged floor generation' "$SKILL"
}

@test "TUNE-0140: transaction uncertainty is incomplete and non-advancing" {
    grep -Fq 'rollback_integrity_failure' "$SKILL"
    grep -Fq 'journal_conflict' "$SKILL"
    grep -Fq 'auto-fix transaction uncertainty' "$SKILL"
    grep -Fq 'launch no model reviewers and take the parent non-advancing route' "$SKILL"
}

@test "TUNE-0140: original finding and every runner result stay audit-visible" {
    grep -Fq 'retain every original floor finding unchanged' "$SKILL"
    grep -Fq 'one structured result for every runner invocation' "$SKILL"
    grep -Fq '`auto_fix_applied` is a derived count' "$SKILL"
}

@test "TUNE-0140: every hooked stage command names the runner and the one-at-a-time loop" {
    for base in "${HOOK_COMMANDS[@]}"; do
        grep -Fq 'dev-tools/self-verify-auto-fix.sh' "${REPO_ROOT}/commands/${base}.md" \
            || { echo "missing runner reference in ${base}.md"; return 1; }
        grep -Fq 'one finding, then rerun the stage validators and deterministic floor' "${REPO_ROOT}/commands/${base}.md" \
            || { echo "missing one-at-a-time loop clause in ${base}.md"; return 1; }
    done
}

@test "TUNE-0140: peer reviewer prose never becomes executable authority" {
    grep -Fq 'Reviewer prose is never executable authority' "${REPO_ROOT}/agents/peer-reviewer.md"
    grep -Fq 'cannot invoke the deterministic auto-fix runner' "${REPO_ROOT}/agents/peer-reviewer.md"
}

@test "TUNE-0140: manual verify stays findings-only and cannot reach the runner" {
    grep -Fq 'Manual `/dr-verify` remains findings-only' "$MANUAL"
    ! grep -Fq 'self-verify-auto-fix.sh' "$MANUAL"
}

@test "TUNE-0140: root guidance distinguishes automatic auto-fix from manual findings-only" {
    grep -Fq 'strictly below 30%' "${REPO_ROOT}/CLAUDE.md"
    grep -Fq '`/dr-verify` remains findings-only' "${REPO_ROOT}/CLAUDE.md"
    grep -Fq 'dev-tools/self-verify-auto-fix.sh' "${REPO_ROOT}/CLAUDE.md"
}

@test "TUNE-0140: README documents the bounded policy and manual exclusion" {
    grep -Fq 'strictly below 30%' "${REPO_ROOT}/README.md"
    grep -Fq 'Manual `/dr-verify` never auto-fixes' "${REPO_ROOT}/README.md"
}

@test "TUNE-0140: commands reference exposes the same bounded policy" {
    grep -Fq 'guarded deterministic auto-fix' "${REPO_ROOT}/documentation/reference/commands.md"
    grep -Fq 'manual `/dr-verify` remains findings-only' "${REPO_ROOT}/documentation/reference/commands.md"
}
