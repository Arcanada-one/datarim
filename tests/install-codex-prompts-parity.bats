#!/usr/bin/env bats
# tests/install-codex-prompts-parity.bats — Codex /prompts:<name> parity (TUNE-0306).
#
# install.sh --enable-codex-prompts (opt-in, default off) flat-copies each
# commands/dr-*.md into ~/.codex/prompts/dr-<name>.md so Codex CLI exposes them
# as /prompts:dr-<name>. Flat copy (not symlink): Windows/FAT + R8
# deferred-validation posture. Namespace-conflict guard leaves non-Datarim
# prompt files untouched.
#
# Tests:
#   T51 — flag mirrors commands into ~/.codex/prompts/ with provenance marker
#   T52 — default (no flag) is opt-out: no prompts/ dir created
#   T53 — namespace conflict: a foreign prompts/dr-*.md is left untouched
#   T54 — idempotent re-run refreshes managed files; --dry-run mutates nothing

load 'helpers/install_fixture'

setup() {
    setup_fixture
    FAKE_CODEX="$FAKE_HOME/.codex"
    # A second Datarim command in the fixture so mirroring covers >1 file.
    echo "# dr-status" > "$FAKE_REPO/commands/dr-status.md"
}

@test "T51: --enable-codex-prompts mirrors commands into ~/.codex/prompts with marker" {
    run env HOME="$FAKE_HOME" CODEX_DIR="$FAKE_CODEX" \
        "$FAKE_REPO/install.sh" --with-codex --no-codex-ux --enable-codex-prompts --yes
    [ "$status" -eq 0 ]
    [ -f "$FAKE_CODEX/prompts/dr-init.md" ]
    [ -f "$FAKE_CODEX/prompts/dr-status.md" ]
    # First line carries the provenance marker; body carries the command text.
    run head -n 1 "$FAKE_CODEX/prompts/dr-init.md"
    [[ "$output" == *"datarim-managed prompt mirror"* ]]
    run grep -F "# dr-init" "$FAKE_CODEX/prompts/dr-init.md"
    [ "$status" -eq 0 ]
    # It is a flat copy, not a symlink.
    [ ! -L "$FAKE_CODEX/prompts/dr-init.md" ]
}

@test "T52: default (no flag) is opt-out — no prompts/ directory" {
    run env HOME="$FAKE_HOME" CODEX_DIR="$FAKE_CODEX" \
        "$FAKE_REPO/install.sh" --with-codex --no-codex-ux --yes
    [ "$status" -eq 0 ]
    [ ! -e "$FAKE_CODEX/prompts" ]
}

@test "T53: namespace conflict leaves a non-Datarim prompt file untouched" {
    mkdir -p "$FAKE_CODEX/prompts"
    printf 'a users own prompt, not ours\n' > "$FAKE_CODEX/prompts/dr-init.md"
    run env HOME="$FAKE_HOME" CODEX_DIR="$FAKE_CODEX" \
        "$FAKE_REPO/install.sh" --with-codex --no-codex-ux --enable-codex-prompts --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"namespace conflict"* ]]
    # Foreign file preserved byte-for-byte.
    run cat "$FAKE_CODEX/prompts/dr-init.md"
    [ "$output" = "a users own prompt, not ours" ]
    # A different (non-conflicting) command was still mirrored.
    [ -f "$FAKE_CODEX/prompts/dr-status.md" ]
}

@test "T54: re-run is idempotent; --dry-run mutates nothing" {
    env HOME="$FAKE_HOME" CODEX_DIR="$FAKE_CODEX" \
        "$FAKE_REPO/install.sh" --with-codex --no-codex-ux --enable-codex-prompts --yes >/dev/null
    run env HOME="$FAKE_HOME" CODEX_DIR="$FAKE_CODEX" \
        "$FAKE_REPO/install.sh" --with-codex --no-codex-ux --enable-codex-prompts --yes
    [ "$status" -eq 0 ]
    run head -n 1 "$FAKE_CODEX/prompts/dr-init.md"
    [[ "$output" == *"datarim-managed prompt mirror"* ]]

    # Dry-run against a fresh HOME creates no prompts/ directory.
    local dry_home="$BATS_TEST_TMPDIR/dry-home"
    mkdir -p "$dry_home"
    run env HOME="$dry_home" CODEX_DIR="$dry_home/.codex" \
        "$FAKE_REPO/install.sh" --with-codex --no-codex-ux --enable-codex-prompts --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY:"*"prompts"* ]]
    [ ! -e "$dry_home/.codex/prompts" ]
}
