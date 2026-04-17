#!/usr/bin/env bats
# TUNE-0006: Structural tests for optimizer agent's Structured Audit Report

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

@test "optimizer.md contains Structured Audit Report section" {
  grep -q "## Structured Audit Report" "$REPO_ROOT/agents/optimizer.md"
}

@test "optimizer.md contains Health Metrics Dashboard table" {
  grep -q "### Section 1: Health Metrics Dashboard" "$REPO_ROOT/agents/optimizer.md"
}

@test "optimizer.md contains all 6 report sections" {
  for i in 1 2 3 4 5 6; do
    grep -q "### Section $i:" "$REPO_ROOT/agents/optimizer.md"
  done
}

@test "dr-optimize.md references Structured Audit Report" {
  grep -q "Structured Audit Report" "$REPO_ROOT/commands/dr-optimize.md"
}
