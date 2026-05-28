#!/usr/bin/env bats
#
# stage-snapshot writer: `auto` stage acceptance + dr-auto.md ↔ enum guard.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
WRITER_LIB="${REPO_ROOT}/scripts/lib/snapshot-writer.sh"
DR_AUTO_MD="${REPO_ROOT}/commands/dr-auto.md"

setup() {
    export TMPROOT="$BATS_TEST_TMPDIR/fake-repo"
    mkdir -p "$TMPROOT/datarim"
    export OPTIONS="$BATS_TEST_TMPDIR/options.txt"
    cat > "$OPTIONS" <<'OPT'
/dr-status | escape hatch
OPT
    export BODY="$BATS_TEST_TMPDIR/body.txt"
    printf 'autonomous terminal snapshot body\n' > "$BODY"
    # shellcheck source=/dev/null
    . "$WRITER_LIB"
}

# Case A — the writer accepts `--stage auto` and records it in frontmatter.
@test "auto stage accepted: exit 0 + frontmatter carries stage: auto" {
    run write_stage_snapshot \
        --root "$TMPROOT" \
        --task TUNE-0330 \
        --stage auto \
        --command /dr-auto \
        --captured-by agent \
        --recommended-next /dr-archive \
        --options-file "$OPTIONS" \
        --body-file "$BODY"
    [ "$status" -eq 0 ]
    local snap="$TMPROOT/datarim/snapshots/TUNE-0330.snapshot.md"
    [ -f "$snap" ]
    grep -q '^stage: auto$' "$snap"
    grep -q '^command: /dr-auto$' "$snap"
}

# Case B — consistency guard: the stage that commands/dr-auto.md declares it
# emits MUST belong to SNAPSHOT_STAGE_RE. Catches the original drift class
# (a command emitting a stage the writer's enum does not list).
@test "guard: stage declared in dr-auto.md belongs to SNAPSHOT_STAGE_RE" {
    [ -f "$DR_AUTO_MD" ]
    local stage_token
    stage_token="$(grep -oE '`stage`: `[a-z]+`' "$DR_AUTO_MD" \
        | head -1 | sed -E 's/.*`([a-z]+)`$/\1/')"
    [ -n "$stage_token" ]
    [[ "$stage_token" =~ $SNAPSHOT_STAGE_RE ]]
}
