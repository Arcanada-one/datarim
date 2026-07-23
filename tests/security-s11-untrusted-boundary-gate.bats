#!/usr/bin/env bats
#
# Regression test for security-baseline S11 — untrusted-content boundary
# review gate (TUNE-0515, from ARAS-0029 Phase-E / ARAS-0049 fence review).
#
# S9 obligation: a new rule ships with a regression test. This asserts the
# S11 rule text, its six probing dimensions, the CI-green-insufficient
# clause, and the ARAS-0049 source citation are present across the three
# artefacts that carry the gate — the canonical rule (security-baseline),
# the review vehicle (self-verification), and the entry point (CLAUDE.md).
#
# Exit codes: 0 PASS, 1 FAIL.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
SB="${REPO_ROOT}/skills/security-baseline/SKILL.md"
SV="${REPO_ROOT}/skills/self-verification/SKILL.md"
CM="${REPO_ROOT}/CLAUDE.md"

# ---------------------------------------------------------------------------
# security-baseline/SKILL.md — canonical S11 rule
# ---------------------------------------------------------------------------

@test "S11: security-baseline defines the S11 section" {
    grep -qE "^## S11 — Untrusted-content boundary review gate" "$SB"
}

@test "S11: rule is a MANDATORY pre-merge gate" {
    grep -q "MANDATORY pre-merge gate" "$SB"
}

@test "S11: CI-green alone does not clear the gate" {
    grep -q "green CI run does NOT clear this gate" "$SB"
}

@test "S11: all six probing dimensions are named" {
    grep -q "Fence-escape" "$SB"
    grep -q "Nonce-predictability" "$SB"
    grep -q "Trust-class cross-promotion" "$SB"
    grep -q "Provenance-forgery" "$SB"
    grep -q "Size-guard-bypass" "$SB"
    grep -q "Fail-open" "$SB"
}

@test "S11: source incident evidence is present (history-agnostic)" {
    grep -q "three L1 hardening items that every CI check had passed over" "$SB"
    # skills/ are history-agnostic — no ecosystem task-ID may leak in (task-id-gate T11)
    ! grep -qE '\b[A-Z]{2,10}-[0-9]{4}\b' "$SB"
}

@test "S11: appears in the Quick reference table" {
    grep -qE "^\| \*\*S11\*\*" "$SB"
}

@test "S11: title is bumped to S1-S11" {
    grep -q "# Security Baseline (S1–S11)" "$SB"
}

# ---------------------------------------------------------------------------
# self-verification/SKILL.md — review vehicle (Layer 3 dispatch)
# ---------------------------------------------------------------------------

@test "S11: self-verification carries the mandatory trigger" {
    grep -qE "^## Mandatory trigger — untrusted-content boundary \(S11\)" "$SV"
}

@test "S11: self-verification mandates Layer 3 dispatch for the boundary" {
    grep -q "Layer 3 native-runtime dispatch MUST run" "$SV"
}

@test "S11: self-verification scopes the frame to the six dimensions" {
    grep -q "fence-escape, nonce-predictability, trust-class cross-promotion, provenance-forgery, size-guard-bypass, fail-open" "$SV"
}

# ---------------------------------------------------------------------------
# CLAUDE.md — Security Mandate entry point
# ---------------------------------------------------------------------------

@test "S11: CLAUDE.md rule clusters include S11" {
    grep -qE "^- \*\*S11\*\* — Untrusted-content boundary review gate" "$CM"
}

@test "S11: CLAUDE.md single-source-of-truth pointer bumped to S1-S11" {
    grep -q "§ S1–S11" "$CM"
}
