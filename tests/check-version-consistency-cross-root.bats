#!/usr/bin/env bats
# The cross-root surfaces are read relative to the framework's own location
# inside the workspace: Projects/Datarim/code/datarim. When the checkout moved
# one level down, every one of them resolved to a missing file and was skipped
# in silence, so 2.67.0 in the workspace and 78 skills on the site went unseen.
#
# The workspace wrappers announce the release as "Текущий стабильный релиз:
# **X.Y.Z**" (they said "Текущая версия:" before commit a0ec95d8b). Both
# phrasings must be read, and a wrapper that announces a different release must
# still fail the gate. The datarim.club surfaces are checked the way the site
# builds them: pages/about.php and pages/home.php derive the catalogue counts
# at render time, and the hero copy states the three counts in one sentence.

SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/check-version-consistency.sh"

setup() {
    ws="$BATS_TEST_TMPDIR/ws"
    fw="$ws/Projects/Datarim/code/datarim"
    mkdir -p "$fw" "$ws/Projects/Websites/datarim.club/content" "$ws/Projects/Websites/datarim.club/pages"
    cp -R "${BATS_TEST_DIRNAME}/../agents" "${BATS_TEST_DIRNAME}/../commands" \
          "${BATS_TEST_DIRNAME}/../skills" "${BATS_TEST_DIRNAME}/../templates" "$fw/"
    cp "${BATS_TEST_DIRNAME}/../VERSION" "${BATS_TEST_DIRNAME}/../AGENTS.md" "${BATS_TEST_DIRNAME}/../README.md" "$fw/"
    v=$(tr -d '[:space:]' < "$fw/VERSION")
    printf 'Текущий стабильный релиз: **%s**.\n' "$v" > "$ws/Projects/Datarim/AGENTS.md"
    printf 'Текущий стабильный релиз: **%s**.\n' "$v" > "$ws/Projects/Datarim/README.md"
    printf "<?php return ['version'     => '%s',];\n" "$v" > "$ws/Projects/Websites/datarim.club/config.php"

    # Ground truth, measured the same way the gate measures it.
    n_agents=$(find "$fw/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d '[:space:]')
    n_commands=$(find "$fw/commands" -maxdepth 1 -name '*.md' | wc -l | tr -d '[:space:]')
    n_skills=$(find "$fw/skills" -mindepth 2 -maxdepth 3 -type f -iname 'SKILL.md' ! -path "$fw/skills/.*" | wc -l | tr -d '[:space:]')

    printf '<p>counts: %s agents, %s commands, %s skills</p>\n' \
        "$n_agents" "$n_commands" "$n_skills" \
        > "$ws/Projects/Websites/datarim.club/content/en.php"
    printf '<p>counts: %s агентов, %s команда, %s навык</p>\n' \
        "$n_agents" "$n_commands" "$n_skills" \
        > "$ws/Projects/Websites/datarim.club/content/ru.php"
    for page in about home; do
        printf "<?php echo count(load_all_docs('agents')); echo count(load_all_docs('commands')); echo count(load_all_docs('skills'));\n" \
            > "$ws/Projects/Websites/datarim.club/pages/${page}.php"
    done
}

@test "a workspace surface behind VERSION fails the check" {
    printf 'Текущий стабильный релиз: **0.0.1**.\n' > "$ws/Projects/Datarim/AGENTS.md"
    run bash "$SCRIPT" --root "$fw"
    [ "$status" -eq 1 ]
    [[ "$output" == *"../../AGENTS.md — found 0.0.1"* ]]
}

@test "the legacy workspace phrasing is read as well" {
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

@test "a site hero that states a stale catalogue size fails the check" {
    printf '<p>counts: 99 agents, 31 commands, 81 skills</p>\n' > "$ws/Projects/Websites/datarim.club/content/en.php"
    run bash "$SCRIPT" --root "$fw"
    [ "$status" -eq 1 ]
    [[ "$output" == *"content/en.php [agents] — claims 99"* ]]
}

@test "a site page that stops deriving the catalogue counts fails the check" {
    printf '<p>19 agents, 31 commands, 81 skills</p>\n' > "$ws/Projects/Websites/datarim.club/pages/about.php"
    run bash "$SCRIPT" --root "$fw"
    [ "$status" -eq 1 ]
    [[ "$output" == *"pages/about.php — does not derive the catalogue count"* ]]
}

@test "an aligned workspace and site pass the check" {
    run bash "$SCRIPT" --root "$fw"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK:"* ]]
}

@test "surfaces that are absent are counted, not silently passed" {
    rm -rf "$ws/Projects/Websites" "$ws/Projects/Datarim/AGENTS.md" "$ws/Projects/Datarim/README.md"
    run bash "$SCRIPT" --root "$fw"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cross-root surface(s) absent, not checked"* ]]
}
