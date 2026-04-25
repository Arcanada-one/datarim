#!/usr/bin/env bats
#
# Tests for v1.17 deprecation banners on curate-runtime.sh and check-drift.sh
# (TUNE-0033 AC-8).

load 'helpers/install_fixture'

setup() {
    setup_fixture
    setup_full_scripts
}

@test "DEP1 AC-8 curate-runtime.sh emits DEPRECATED banner referencing TUNE-0033" {
    seed_existing_copy_install
    run bash -c "HOME='$FAKE_HOME' CLAUDE_DIR='$FAKE_CLAUDE' DATARIM_REPO_DIR='$FAKE_REPO' '$FAKE_REPO/scripts/curate-runtime.sh' --dry-run 2>&1"
    [[ "$output" == *"DEPRECATED"* ]]
    [[ "$output" == *"TUNE-0033"* ]]
}

@test "DEP2 AC-8 check-drift.sh emits DEPRECATED banner referencing TUNE-0033" {
    seed_existing_copy_install
    run bash -c "HOME='$FAKE_HOME' CLAUDE_DIR='$FAKE_CLAUDE' DATARIM_REPO_DIR='$FAKE_REPO' '$FAKE_REPO/scripts/check-drift.sh' 2>&1"
    [[ "$output" == *"DEPRECATED"* ]]
    [[ "$output" == *"TUNE-0033"* ]]
}
