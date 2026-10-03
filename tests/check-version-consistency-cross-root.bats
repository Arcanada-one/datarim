#!/usr/bin/env bats
# The cross-root surfaces are read relative to the framework's own location
# inside the workspace: Projects/Datarim/code/datarim. When the checkout moved
# one level down, every one of them resolved to a missing file and was skipped
# in silence, so 2.67.0 in the workspace and 78 skills on the site went unseen.

SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/check-version-consistency.sh"

setup() {
    ws="$BATS_TEST_TMPDIR/ws"
    fw="$ws/Projects/Datarim/code/datarim"
    mkdir -p "$fw" "$ws/Projects/Websites/datarim.club/content" "$ws/Projects/Websites/datarim.club/pages"
    cp -R "${BATS_TEST_DIRNAME}/../agents" "${BATS_TEST_DIRNAME}/../commands" \
          "${BATS_TEST_DIRNAME}/../skills" "${BATS_TEST_DIRNAME}/../templates" "$fw/"
    cp "${BATS_TEST_DIRNAME}/../VERSION" "${BATS_TEST_DIRNAME}/../AGENTS.md" "${BATS_TEST_DIRNAME}/../README.md" "$fw/"
    v=$(tr -d '[:space:]' < "$fw/VERSION")
    printf 'Текущая версия: **%s**.\n' "$v" > "$ws/Projects/Datarim/AGENTS.md"
    printf -- '- **Версия:** %s\n' "$v" > "$ws/Projects/Datarim/README.md"
    printf "<?php return ['version'     => '%s',];\n" "$v" > "$ws/Projects/Websites/datarim.club/config.php"
}

@test "a workspace surface behind VERSION fails the check" {
    printf 'Текущая версия: **0.0.1**.\n' > "$ws/Projects/Datarim/AGENTS.md"
    run bash "$SCRIPT" --root "$fw"
    [ "$status" -eq 1 ]
    [[ "$output" == *"../../AGENTS.md — found 0.0.1"* ]]
}

@test "the site version is read from Projects/Websites" {
    printf "<?php return ['version' => '0.0.2',];\n" > "$ws/Projects/Websites/datarim.club/config.php"
    run bash "$SCRIPT" --root "$fw"
    [ "$status" -eq 1 ]
    [[ "$output" == *"datarim.club/config.php — found 0.0.2"* ]]
}

@test "surfaces that are absent are counted, not silently passed" {
    rm -rf "$ws/Projects/Websites" "$ws/Projects/Datarim/AGENTS.md" "$ws/Projects/Datarim/README.md"
    run bash "$SCRIPT" --root "$fw"
    [ "$status" -eq 0 ]
    [[ "$output" == *"12 cross-root surface(s) absent, not checked"* ]]
}
