#!/usr/bin/env bats

# TUNE-0016: Tests for curate-runtime.sh

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
SCRIPT_PATH="$REPO_ROOT/scripts/curate-runtime.sh"

# --- Helpers: create temp mock runtime+repo ---------------------------------

setup() {
  MOCK_RUNTIME="$(mktemp -d)"
  MOCK_REPO="$(mktemp -d)"

  # Create repo structure with VERSION, CLAUDE.md, README.md
  for scope in agents skills commands templates; do
    mkdir -p "$MOCK_REPO/$scope"
  done
  echo "1.10.0" > "$MOCK_REPO/VERSION"
  echo '> **Version:** 1.10.0' > "$MOCK_REPO/CLAUDE.md"
  echo '[![Version: 1.10.0](https://img.shields.io/badge/Version-1.10.0-green.svg)](VERSION)' > "$MOCK_REPO/README.md"

  # Create runtime structure (mirror of repo)
  for scope in agents skills commands templates; do
    mkdir -p "$MOCK_RUNTIME/$scope"
  done
}

teardown() {
  rm -rf "$MOCK_RUNTIME" "$MOCK_REPO"
}

# --- T1: --help exits 0 and prints Usage -----------------------------------

@test "curate-runtime.sh --help exits 0 and prints Usage" {
  run "$SCRIPT_PATH" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# --- T2: --dry-run exits 0, prints DRY-RUN, no file changes ----------------

@test "--dry-run prints DRY-RUN and makes no file changes" {
  # Create a differ: same file, different content
  echo "runtime version" > "$MOCK_RUNTIME/skills/test.md"
  echo "repo version" > "$MOCK_REPO/skills/test.md"

  run env CLAUDE_DIR="$MOCK_RUNTIME" DATARIM_REPO_DIR="$MOCK_REPO" bash "$SCRIPT_PATH" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[DRY-RUN]"* ]]
  # Repo file unchanged
  [ "$(cat "$MOCK_REPO/skills/test.md")" = "repo version" ]
}

# --- T3: --auto copies "differ" files --------------------------------------

@test "--auto copies differ files from runtime to repo" {
  echo "updated content" > "$MOCK_RUNTIME/skills/foo.md"
  echo "old content" > "$MOCK_REPO/skills/foo.md"

  run env CLAUDE_DIR="$MOCK_RUNTIME" DATARIM_REPO_DIR="$MOCK_REPO" bash "$SCRIPT_PATH" --auto --no-bump
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_REPO/skills/foo.md")" = "updated content" ]
  [[ "$output" == *"COPY skills/foo.md"* ]]
}

# --- T4: --auto copies new files from runtime --------------------------------

@test "--auto copies new file from runtime to repo" {
  echo "brand new" > "$MOCK_RUNTIME/skills/new-skill.md"
  # No corresponding file in repo

  run env CLAUDE_DIR="$MOCK_RUNTIME" DATARIM_REPO_DIR="$MOCK_REPO" bash "$SCRIPT_PATH" --auto --no-bump
  [ "$status" -eq 0 ]
  [ -f "$MOCK_REPO/skills/new-skill.md" ]
  [ "$(cat "$MOCK_REPO/skills/new-skill.md")" = "brand new" ]
  [[ "$output" == *"NEW"* ]]
}

# --- T5: --auto does NOT delete "Only in repo" files -----------------------

@test "--auto does NOT delete files only in repo" {
  echo "repo only" > "$MOCK_REPO/skills/orphan.md"
  # No corresponding file in runtime

  run env CLAUDE_DIR="$MOCK_RUNTIME" DATARIM_REPO_DIR="$MOCK_REPO" bash "$SCRIPT_PATH" --auto --no-bump
  [ "$status" -eq 0 ]
  [ -f "$MOCK_REPO/skills/orphan.md" ]
  [[ "$output" == *"WARN"* ]]
}

# --- T6: --no-bump skips version increment ----------------------------------

@test "--no-bump skips version increment" {
  echo "changed" > "$MOCK_RUNTIME/agents/test.md"
  echo "original" > "$MOCK_REPO/agents/test.md"

  run env CLAUDE_DIR="$MOCK_RUNTIME" DATARIM_REPO_DIR="$MOCK_REPO" bash "$SCRIPT_PATH" --auto --no-bump
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_REPO/VERSION" | tr -d '[:space:]')" = "1.10.0" ]
}

# --- T7: patch-bump increments VERSION correctly ----------------------------

@test "patch-bump increments VERSION from 1.10.0 to 1.10.1" {
  echo "changed" > "$MOCK_RUNTIME/agents/test.md"
  echo "original" > "$MOCK_REPO/agents/test.md"

  run env CLAUDE_DIR="$MOCK_RUNTIME" DATARIM_REPO_DIR="$MOCK_REPO" bash "$SCRIPT_PATH" --auto
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_REPO/VERSION" | tr -d '[:space:]')" = "1.10.1" ]
}

# --- T8: patch-bump updates CLAUDE.md version line --------------------------

@test "patch-bump updates CLAUDE.md version line" {
  echo "changed" > "$MOCK_RUNTIME/agents/test.md"
  echo "original" > "$MOCK_REPO/agents/test.md"

  run env CLAUDE_DIR="$MOCK_RUNTIME" DATARIM_REPO_DIR="$MOCK_REPO" bash "$SCRIPT_PATH" --auto
  [ "$status" -eq 0 ]
  grep -q '1.10.1' "$MOCK_REPO/CLAUDE.md"
}

# --- T9: patch-bump updates README.md badge ---------------------------------

@test "patch-bump updates README.md badge" {
  echo "changed" > "$MOCK_RUNTIME/agents/test.md"
  echo "original" > "$MOCK_REPO/agents/test.md"

  run env CLAUDE_DIR="$MOCK_RUNTIME" DATARIM_REPO_DIR="$MOCK_REPO" bash "$SCRIPT_PATH" --auto
  [ "$status" -eq 0 ]
  grep -q '1.10.1' "$MOCK_REPO/README.md"
}

# --- T10: exits with error if CLAUDE_DIR missing ---------------------------

@test "exits with error if CLAUDE_DIR missing" {
  run env CLAUDE_DIR="/nonexistent/path" DATARIM_REPO_DIR="$MOCK_REPO" bash "$SCRIPT_PATH" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR"* ]]
}

# --- T11: after --auto, in-sync scopes stay in sync (integration) ----------

@test "after --auto run on mock, all diffs are resolved" {
  echo "v2" > "$MOCK_RUNTIME/skills/a.md"
  echo "v1" > "$MOCK_REPO/skills/a.md"
  echo "new" > "$MOCK_RUNTIME/agents/b.md"

  env CLAUDE_DIR="$MOCK_RUNTIME" DATARIM_REPO_DIR="$MOCK_REPO" bash "$SCRIPT_PATH" --auto --no-bump

  # Verify no differ or Only-in-runtime lines remain
  for scope in agents skills commands templates; do
    if [ -d "$MOCK_RUNTIME/$scope" ] && [ -d "$MOCK_REPO/$scope" ]; then
      diff_out=$(diff -rq "$MOCK_RUNTIME/$scope/" "$MOCK_REPO/$scope/" 2>/dev/null || true)
      [ -z "$diff_out" ]
    fi
  done
}

# --- T12: interactive mode rejects non-TTY stdin (TUNE-0030) ----------------

@test "interactive mode rejects non-TTY stdin with exit 1" {
  echo "v2" > "$MOCK_RUNTIME/skills/test.md"
  echo "v1" > "$MOCK_REPO/skills/test.md"

  # Pipe stdin → non-TTY
  run bash -c 'echo "" | CLAUDE_DIR="'"$MOCK_RUNTIME"'" DATARIM_REPO_DIR="'"$MOCK_REPO"'" bash "'"$SCRIPT_PATH"'"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"TTY"* ]]
}

# --- T13: --auto works without TTY (TUNE-0030) -----------------------------

@test "--auto works even without TTY" {
  echo "v2" > "$MOCK_RUNTIME/skills/test.md"
  echo "v1" > "$MOCK_REPO/skills/test.md"

  run bash -c 'echo "" | CLAUDE_DIR="'"$MOCK_RUNTIME"'" DATARIM_REPO_DIR="'"$MOCK_REPO"'" bash "'"$SCRIPT_PATH"'" --auto --no-bump'
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_REPO/skills/test.md")" = "v2" ]
}

# --- T14: symlink runtime dirs detected and reported (TUNE-0030) -----------

@test "symlink runtime dir → repo detected as SYMLINK" {
  # Replace real runtime skills dir with symlink to repo skills
  rm -rf "$MOCK_RUNTIME/skills"
  ln -s "$MOCK_REPO/skills" "$MOCK_RUNTIME/skills"

  run env CLAUDE_DIR="$MOCK_RUNTIME" DATARIM_REPO_DIR="$MOCK_REPO" bash "$SCRIPT_PATH" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"SYMLINK"* ]]
  [[ "$output" == *"drift detection impossible"* ]]
}

# --- T15: portable sed in version bump (TUNE-0030) -------------------------

@test "version bump uses portable sed (no sed -i)" {
  echo "changed" > "$MOCK_RUNTIME/agents/test.md"
  echo "original" > "$MOCK_REPO/agents/test.md"

  # Verify no sed -i '' in the script (would break GNU sed on RedHat)
  run grep -c "sed -i ''" "$SCRIPT_PATH"
  [ "$output" = "0" ]

  # Verify version bump still works
  run env CLAUDE_DIR="$MOCK_RUNTIME" DATARIM_REPO_DIR="$MOCK_REPO" bash "$SCRIPT_PATH" --auto
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_REPO/VERSION" | tr -d '[:space:]')" = "1.10.1" ]
  grep -q '1.10.1' "$MOCK_REPO/CLAUDE.md"
  grep -q '1.10.1' "$MOCK_REPO/README.md"
}
