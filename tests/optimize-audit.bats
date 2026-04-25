#!/usr/bin/env bats
# TUNE-0006: Structural tests for optimizer agent's Structured Audit Report
# TUNE-0034: removed 3 stale assertions on agents/optimizer.md schema
# (file restructured pre-2026, "## Structured Audit Report" + "### Section 1..6"
# layout no longer exists — the assertions encoded a snapshot, not a live contract).
# Surviving test below covers the remaining live invariant: dr-optimize.md
# command continues to reference Structured Audit Report semantics.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

@test "dr-optimize.md references Structured Audit Report" {
  grep -q "Structured Audit Report" "$REPO_ROOT/commands/dr-optimize.md"
}
