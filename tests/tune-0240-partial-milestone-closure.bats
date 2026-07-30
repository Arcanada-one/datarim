#!/usr/bin/env bats
# tune-0240-partial-milestone-closure.bats — TUNE-0240
#
# Verifies the shipped framework entry file (CLAUDE.md) documents the
# Partial Milestone Closure Pattern for AAL milestones split across child
# tasks. Prose-content assertions (V-AC-1..5) plus an English-only gate
# on the shipped root surface (V-AC-6).
#
# Contract under test: PRD-TUNE-0240 § 3 (pattern definition) + § 4 (V-AC).

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
ENGLISH="$REPO_ROOT/dev-tools/check-body-english.sh"

# Byte range of the pattern section (heading -> next `## ` heading), so token
# assertions are scoped to the new section and cannot be satisfied by
# incidental matches elsewhere in CLAUDE.md.
section() {
    awk '
        /^## Partial Milestone Closure Pattern/ { grab=1; print; next }
        grab && /^## / { exit }
        grab { print }
    ' "$CLAUDE_MD"
}

@test "T1 (V-AC-1): CLAUDE.md has a Partial Milestone Closure Pattern section" {
    grep -qE '^## Partial Milestone Closure Pattern' "$CLAUDE_MD"
}

@test "T1b (V-AC-1): section sits in the shipped surface (above Project-Specific Configuration)" {
    local sec_line cfg_line
    sec_line="$(grep -nE '^## Partial Milestone Closure Pattern' "$CLAUDE_MD" | head -1 | cut -d: -f1)"
    cfg_line="$(grep -nE '^## Project-Specific Configuration' "$CLAUDE_MD" | head -1 | cut -d: -f1)"
    [ -n "$sec_line" ]
    [ -n "$cfg_line" ]
    [ "$sec_line" -lt "$cfg_line" ]
}

@test "T2 (V-AC-2): defines the append-log heading format + cross-link" {
    section | grep -qF 'Partial M{N} closure via {CHILD-ID}'
    section | grep -qiF 'Append-log'
}

@test "T3 (V-AC-2): canonical status word set (closed / deferred glyph tokens)" {
    section | grep -qF '✓ closed'
    section | grep -qF '✗ deferred'
}

@test "T4 (V-AC-2 + V-AC-3): AAL bump is deferred and parent owns the ledger" {
    section | grep -qiF 'AAL bump deferred'
    section | grep -qiF 'last closing child'
    section | grep -qi 'current_aal'
}

@test "T5 (V-AC-4): reopen-on-fallback reverts the bump and tags aal_gap" {
    section | grep -qiE 'reopen'
    section | grep -qiE 'revert|lower'
    section | grep -qF 'aal_gap'
}

@test "T6 (V-AC-5): cross-links the ecosystem AAL Mandate, does not restate L0-L5" {
    section | grep -qiE 'cross-link|AAL Mandate'
}

@test "T7 (V-AC-6): shipped root surface stays English-only" {
    run "$ENGLISH" --root "$REPO_ROOT" --scope root
    [ "$status" -eq 0 ]
}
