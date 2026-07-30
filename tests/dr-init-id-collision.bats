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
# Group C: anchor semantics of next-free-id.sh's two internal probes.
#   Originally a guard pinning the unanchored-watermark gotcha as
#   known-good behaviour; REVERSED by TUNE-0542 after that behaviour
#   walked the live allocator out of the 4-digit ID space. See the
#   Group C header below for what survived the reversal and why.

CMDS_DIR="${BATS_TEST_DIRNAME}/../commands"
HELPER="${BATS_TEST_DIRNAME}/../dev-tools/next-free-id.sh"
DR_INIT="${CMDS_DIR}/dr-init.md"
DR_ARCHIVE="${CMDS_DIR}/dr-archive.md"

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

@test "A10: dr-archive.md wires the dr-init-id-collision-window skill into the collision-detection branch" {
    grep -F "skills/dr-init-id-collision-window/SKILL.md" "$DR_ARCHIVE"
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
    # TUNE-0542: next-free-id.sh now also reads two HOST-GLOBAL claim surfaces
    # (live tmux session names, git worktree/branch names). Neutralise them so
    # this spec stays hermetic on a host running dozens of unrelated agents.
    export DATARIM_ID_TMUX_SESSIONS=""
    export DATARIM_ID_GIT_REFS=""
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

# ── Group C — anchor semantics of the two probes ─────────────────────────────
#
# CONTRACT REVERSED BY TUNE-0542 — deliberate, not a regression.
#
# C01 used to assert the opposite of what it asserts now: that a prose-only
# mention of TUNE-9999 correctly inflated next-free-id.sh's watermark to
# TUNE-10000. It was filed as "deliberately exercised, not asserted as a
# defect", on the rationale that the helper and the dr-init Step-4 probe have
# different anchor semantics BY DESIGN — the helper picks a NEW id, Step-4
# checks a SPECIFIC id.
#
# That rationale was half right, and the half that was wrong cost real work.
# On 2026-07-30 the unanchored watermark walked the live allocator to
# TUNE-10001 against a true ceiling of TUNE-0541, out of the 4-digit space the
# framework assumes.
#
# What survives: the two probes really do differ. What was misdrawn: the axis.
# Anchoring does not track WHICH caller is asking — it tracks WHAT A FALSE
# POSITIVE COSTS. There are three probes, not two, and the helper contains two
# of them:
#
#   helper CEILING      FP = the numbering space forks     → ANCHORED   (C01)
#   helper is_claimed   FP = one wasted ID                 → unanchored (C02)
#   dr-init Step-4      FP = an operator STOP + 3-way ask  → ANCHORED   (B04)
#
# So Group B's anchored probe stays exactly as it was, and the unanchored
# semantics C01 was defending survive too — relocated to the one place where
# being wrong is cheap. Full derivation: dev-tools/next-free-id.sh header.

@test "C01: next-free-id.sh CEILING is anchored — a prose-only mention does not inflate the max" {
    printf -- '- TUNE-0001 · real task\n  Note: similar to TUNE-9999 discussed previously\n' \
        > datarim/backlog.md

    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    # One real entry line → the ceiling is 0001 and the next free ID is 0002.
    # The prose mention of TUNE-9999 contributes nothing to the watermark.
    [ "$output" = "TUNE-0002" ]
}

@test "C01b: next-free-id.sh COLLISION PROBE stays unanchored — prose still blocks reuse" {
    # The surviving half of the original Group-C intent. The prose mention must
    # not lift the ceiling (C01) and must still make that specific ID
    # unavailable, because "renumbered from TUNE-0002" is somebody's claim even
    # though it is not an entry line. Ceiling 0001 → candidate 0002 lands
    # exactly on the prose-only ID, so the probe alone decides this case.
    printf -- '- TUNE-0001 · real task [renumbered from TUNE-0002 earlier today]\n' \
        > datarim/backlog.md

    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "TUNE-0003"
}

@test "C02: next-free-id.sh with no prose mention returns the expected low next-free ID" {
    printf -- '- TUNE-0001 · real task only, no prose ID mentions\n' > datarim/backlog.md

    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0002" ]
}
