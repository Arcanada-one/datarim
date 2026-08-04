#!/usr/bin/env bats
# check-wiki-raw-orphans.bats — regression suite for the wiki/_raw_ semantic
# orphan-content check (dev-tools/check-wiki-raw-orphans.sh).
#
# Contract pinned here:
#   - no-op exit 0 with a note when the target dir does not exist
#   - matching basename ↔ first-heading passes
#   - unrelated basename ↔ heading is flagged as ORPHAN (exit 1 in --check)
#   - substring overlap counts as a match (token stem vs longer heading token)
#   - files without headings fall back to the first non-empty line
#   - empty / token-less files are SKIPPED, never flagged
#   - --report always exits 0; missing mode is a usage error (exit 2)

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPT="$REPO_ROOT/dev-tools/check-wiki-raw-orphans.sh"
  FIX="$(mktemp -d)"
  RAW="$FIX/wiki/_raw_"
  mkdir -p "$RAW"
}

teardown() {
  rm -rf "$FIX"
}

@test "no-op exit 0 with note when target dir does not exist" {
  run bash "$SCRIPT" --dir "$FIX/does-not-exist" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"no-op"* ]]
}

@test "missing mode is a usage error" {
  run bash "$SCRIPT" --dir "$RAW"
  [ "$status" -eq 2 ]
}

@test "matching basename and heading passes" {
  printf '# Syncthing retirement notes\n\nbody\n' > "$RAW/syncthing-retirement.md"
  run bash "$SCRIPT" --dir "$RAW" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT: PASS"* ]]
}

@test "unrelated basename is flagged as orphan (exit 1)" {
  printf '# Quarterly finance overview\n\nbody\n' > "$RAW/kubernetes-ingress-debug.md"
  run bash "$SCRIPT" --dir "$RAW" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ORPHAN"* ]]
  [[ "$output" == *"kubernetes-ingress-debug.md"* ]]
}

@test "substring token overlap counts as a match" {
  # basename token "sync" is a substring of heading token "syncthing"
  printf '# Syncthing migration\n' > "$RAW/sync-notes.md"
  run bash "$SCRIPT" --dir "$RAW" --check
  [ "$status" -eq 0 ]
}

@test "file without heading falls back to first non-empty line" {
  printf '\nrelease pipeline hardening checklist\nmore\n' > "$RAW/release-pipeline.md"
  run bash "$SCRIPT" --dir "$RAW" --check
  [ "$status" -eq 0 ]
}

@test "numeric-only and short basename tokens carry no signal (skip, not orphan)" {
  # basename yields no usable tokens (all numeric/short) → SKIP
  printf '# Anything at all\n' > "$RAW/2026-01-02.md"
  run bash "$SCRIPT" --dir "$RAW" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped=1"* ]]
}

@test "empty file is skipped, never flagged" {
  : > "$RAW/completely-empty-file.md"
  run bash "$SCRIPT" --dir "$RAW" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped=1"* ]]
}

@test "mixed corpus: one orphan among matches fails --check and names only the orphan" {
  printf '# Syncthing retirement notes\n' > "$RAW/syncthing-retirement.md"
  printf '# Quarterly finance overview\n' > "$RAW/kubernetes-ingress-debug.md"
  run bash "$SCRIPT" --dir "$RAW" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ORPHAN  "*"kubernetes-ingress-debug.md"* ]]
  [[ "$output" != *"ORPHAN  "*"syncthing-retirement.md"* ]]
  [[ "$output" == *"orphans=1"* ]]
}

@test "--report mode always exits 0 even with orphans" {
  printf '# Quarterly finance overview\n' > "$RAW/kubernetes-ingress-debug.md"
  run bash "$SCRIPT" --dir "$RAW" --report
  [ "$status" -eq 0 ]
  [[ "$output" == *"ORPHAN"* ]]
}

@test "nested subdirectories are scanned" {
  mkdir -p "$RAW/imports"
  printf '# Quarterly finance overview\n' > "$RAW/imports/kubernetes-ingress-debug.md"
  run bash "$SCRIPT" --dir "$RAW" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"imports/kubernetes-ingress-debug.md"* ]]
}
