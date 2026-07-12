#!/usr/bin/env bats
# dr-init-id-collision.bats — TUNE-0266
#
# Test backfill for the /dr-init ID-collision probe (Class A A1, already
# applied to commands/dr-init.md Step 4 on 2026-05-22). The probe logic
# itself is shipped; the runtime auto-bump path for the agent's OWN new ID
# is already covered by tests/tune-0461-id-collision-autobump.bats.
#
# This file covers the remainder of the probe that tune-0461's suite does
# NOT exercise:
#   (a) the three-way operator prompt on a FOREIGN-ID collision
#       (reassign / cancel / operator-picks-different-ID)
#   (b) the grep probe across backlog.md + tasks.md for a foreign entry
#   (c) the archive scan (documentation/archive/*/archive-{ID}.md)
#
# Group A: markdown-contract assertions — the 3-way prompt and grep-probe
#   text are prose steps in commands/dr-init.md, not runtime-executable
#   code. Asserted structurally per the task brief.
# Group B: functional harness reproducing the exact grep-probe command
#   dr-init.md Step 4 specifies, against fixture backlog/tasks/archive
#   trees, to prove the probe correctly flags/clears FOREIGN collisions.
# Group C: known-behaviour regression guard for the next-free-id.sh
#   literal-substring gotcha (Surface-3 `grep -oh` over backlog.md body
#   text, not anchored to an entry line) — deliberately exercised per the
#   wave-12 finding, not treated as an in-scope fix for this task.

CMDS_DIR="${BATS_TEST_DIRNAME}/../commands"
HELPER="${BATS_TEST_DIRNAME}/../dev-tools/next-free-id.sh"
DR_INIT="${CMDS_DIR}/dr-init.md"

# ── Group A — markdown-contract assertions (commands/dr-init.md Step 4) ──────

@test "A01: dr-init.md documents the FOREIGN-entry 3-way operator prompt" {
    grep -iE "FOREIGN entry.*3-way prompt|3-way prompt to the operator" "$DR_INIT"
}

@test "A02: dr-init.md 3-way prompt offers option (a) reassign the prior entry" {
    grep -iE "reassign the prior backlog|queued entry to the next free ID" "$DR_INIT"
}

@test "A03: dr-init.md 3-way prompt offers option (b) cancel the prior entry" {
    grep -iE "cancel the prior entry" "$DR_INIT"
}

@test "A04: dr-init.md 3-way prompt offers option (c) operator picks a different ID" {
    grep -iE "operator picks a different ID" "$DR_INIT"
}

@test "A05: dr-init.md specifies the foreign-entry grep probe across backlog.md + tasks.md" {
    grep -F 'grep -lE "^- {TASK-ID} ·" datarim/backlog.md datarim/tasks.md' "$DR_INIT"
}

@test "A06: dr-init.md specifies the archive scan for the collision probe" {
    grep -F 'ls documentation/archive/*/archive-{TASK-ID}.md' "$DR_INIT"
}

@test "A07: dr-init.md gates the STOP behaviour — must not proceed until collision closed" {
    grep -iE "do not proceed with .?\{TASK-ID\}.? until the collision is closed" "$DR_INIT"
}

@test "A08: dr-init.md distinguishes agent's-own-ID auto-bump from FOREIGN-entry STOP" {
    grep -iE "Agent's OWN new-ID .parallel-session race." "$DR_INIT"
}

@test "A09: dr-init.md wires the dr-init-id-collision-window skill into the option-(a) reassign branch" {
    grep -F "skills/dr-init-id-collision-window/SKILL.md" "$DR_INIT"
}

# ── Group B — functional grep-probe harness ──────────────────────────────────
# Reproduces the exact probe dr-init.md Step 4 specifies:
#   grep -lE "^- {TASK-ID} ·" datarim/backlog.md datarim/tasks.md
#   ls documentation/archive/*/archive-{TASK-ID}.md

setup() {
    FIXTURE_DIR="$(mktemp -d)"
    mkdir -p "${FIXTURE_DIR}/datarim"
    mkdir -p "${FIXTURE_DIR}/documentation/archive/framework"
    cd "${FIXTURE_DIR}" || return 1
}

teardown() {
    cd "${BATS_TEST_DIRNAME}" || true
    rm -rf "${FIXTURE_DIR}"
}

@test "B01: grep probe finds no match when TASK-ID is genuinely free (no collision)" {
    printf -- '- TUNE-0001 · unrelated task\n' > datarim/tasks.md
    printf -- '- TUNE-0002 · another unrelated task\n' > datarim/backlog.md

    run grep -lE "^- TUNE-0500 ·" datarim/backlog.md datarim/tasks.md
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "B02: grep probe flags a FOREIGN entry present as a backlog.md entry line" {
    printf -- '- TUNE-0500 · someone else queued this already\n' > datarim/backlog.md
    printf -- '- TUNE-0001 · unrelated task\n' > datarim/tasks.md

    run grep -lE "^- TUNE-0500 ·" datarim/backlog.md datarim/tasks.md
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "backlog.md"
}

@test "B03: grep probe flags a FOREIGN entry present as a tasks.md entry line" {
    printf -- '- TUNE-0001 · unrelated task\n' > datarim/backlog.md
    printf -- '- TUNE-0500 · already in flight\n' > datarim/tasks.md

    run grep -lE "^- TUNE-0500 ·" datarim/backlog.md datarim/tasks.md
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "tasks.md"
}

@test "B04: grep probe does NOT flag a mere prose mention (anchored to entry-line start)" {
    # A description line that mentions the ID mid-sentence must not match —
    # the probe is anchored to "^- {TASK-ID} ·", i.e. an actual entry, not a
    # prose reference elsewhere in the file.
    printf -- '- TUNE-0001 · unrelated task\n  see also TUNE-0500 in prior discussion\n' \
        > datarim/backlog.md
    printf -- '- TUNE-0002 · another task\n' > datarim/tasks.md

    run grep -lE "^- TUNE-0500 ·" datarim/backlog.md datarim/tasks.md
    [ "$status" -ne 0 ]
}

@test "B05: archive scan finds a match when archive-{ID}.md exists" {
    : > documentation/archive/framework/archive-TUNE-0500.md

    run bash -c 'ls documentation/archive/*/archive-TUNE-0500.md 2>/dev/null'
    [ -n "$output" ]
}

@test "B06: archive scan finds no match when no archive-{ID}.md exists" {
    : > documentation/archive/framework/archive-TUNE-0099.md

    run bash -c 'ls documentation/archive/*/archive-TUNE-0500.md 2>/dev/null'
    [ -z "$output" ]
}

@test "B07: combined probe (grep + archive scan) surfaces a FOREIGN collision from any of the 3 surfaces" {
    printf -- '- TUNE-0001 · unrelated task\n' > datarim/backlog.md
    printf -- '- TUNE-0002 · unrelated task\n' > datarim/tasks.md
    : > documentation/archive/framework/archive-TUNE-0500.md

    run grep -lE "^- TUNE-0500 ·" datarim/backlog.md datarim/tasks.md
    [ "$status" -ne 0 ]  # not a live-entry match

    ARCHIVE_HIT="$(ls documentation/archive/*/archive-TUNE-0500.md 2>/dev/null)"
    [ -n "$ARCHIVE_HIT" ]  # but the archive surface still flags it as claimed
}

# ── Group C — known-behaviour regression guard (wave-12 literal-grep gotcha) ─
# next-free-id.sh Surface-3 extraction (`grep -oh "${PREFIX}-[0-9]\{4\}"` over
# the full body of backlog.md/tasks.md) is NOT anchored to an entry line — a
# prose mention of a high-numbered ID anywhere in backlog.md is picked up and
# inflates MAX_NUM, unlike the anchored dr-init.md Step-4 FOREIGN-entry probe
# (Group B) which correctly ignores prose mentions. This is deliberately
# exercised, not asserted as a defect — the two probes have different anchor
# semantics by design (helper picks a NEW free id; Step-4 probe checks a
# SPECIFIC candidate id against real entries).

@test "C01: next-free-id.sh Surface-3 extraction is NOT anchored — a prose-only ID mention inflates the max" {
    printf -- '- TUNE-0001 · real task\n  Note: similar to TUNE-9999 discussed previously\n' \
        > datarim/backlog.md

    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    # Known behaviour: the prose mention of TUNE-9999 is picked up by the
    # unanchored grep, so the computed next-free ID jumps to TUNE-10000
    # instead of the "true" TUNE-0002 a reader would expect from the one
    # real entry line.
    [ "$output" = "TUNE-10000" ]
}

@test "C02: next-free-id.sh with no prose mention returns the expected low next-free ID" {
    printf -- '- TUNE-0001 · real task only, no prose ID mentions\n' > datarim/backlog.md

    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0002" ]
}
