#!/usr/bin/env bats
# tune-0542-next-free-id-claim-surfaces.bats
#
# Regression spec for dev-tools/next-free-id.sh — the canonical task-ID
# allocator every agent on a host shares.
#
# It encodes ONE architectural rule, from which every case below follows:
#
#   The script does two jobs that want OPPOSITE biases, and they must not be
#   computed from the same scan.
#
#     CEILING  (max claimed + 1)  — STRICT. Only *structural* positions count:
#         archive/datarim FILENAMES and line-leading index rows. A number
#         lifted from free prose or from an unconstrained name (a branch, a
#         tmux session) must never move the watermark, because an over-high
#         ceiling walks the allocator out of the 4-digit space the whole
#         framework assumes — a silent, unrecoverable fork of the numbering.
#
#     COLLISION PROBE (is this specific ID free?) — PERMISSIVE. Every surface
#         counts, including free prose, live tmux session names and git
#         branch/worktree names. Over-claiming costs one wasted ID.
#         Under-claiming hands two agents the same ID.
#
#   Ceiling errs LOW and is corrected by the probe. The probe errs HIGH and is
#   corrected by nothing, so it must never be tightened.
#
# Groups:
#   A — defect 2: test-fixture literals in prose must not poison the ceiling
#   B — defect 1: live tmux / git worktree names are a claim surface
#   C — the 4-digit invariant (loud failure instead of a 5-digit ID)
#   D — widened NAME claim surface (datarim/tasks, prd, plans, .auto, snapshots;
#       files AND directories; both markdown list markers)
#
# Test seam: the two host-global surfaces are overridable so this spec is
# hermetic on a busy multi-agent host. When DATARIM_ID_TMUX_SESSIONS /
# DATARIM_ID_GIT_REFS are set (even to empty) the helper uses the supplied
# newline-separated list instead of probing the live host. B05 deliberately
# leaves the seam unset and exercises the real tmux binary.

HELPER="${BATS_TEST_DIRNAME}/../dev-tools/next-free-id.sh"

setup() {
    FIXTURE_DIR="$(mktemp -d)"
    mkdir -p "${FIXTURE_DIR}/datarim"
    mkdir -p "${FIXTURE_DIR}/documentation/archive/framework"
    # Hermetic by default: neutralise both host-global surfaces.
    export DATARIM_ID_TMUX_SESSIONS=""
    export DATARIM_ID_GIT_REFS=""
}

teardown() {
    rm -rf "${FIXTURE_DIR}"
}

# Run the helper capturing stdout and stderr separately (bats `run` merges
# them, which would corrupt an exact ID comparison whenever a warning fires).
# Sets: HID, HERR, HSTATUS.
run_helper() {
    local o e
    o="$(mktemp)"; e="$(mktemp)"
    HSTATUS=0
    bash "${HELPER}" "$@" > "$o" 2> "$e" || HSTATUS=$?
    HID="$(cat "$o")"
    HERR="$(cat "$e")"
    rm -f "$o" "$e"
}

# ── Group A — defect 2: fixture literals in prose must not poison the ceiling ─
#
# Reproduced on arcana-devs 2026-07-30: `next-free-id.sh TUNE <workspace>`
# returned TUNE-10001 against a real ceiling of TUNE-0541. Every poisoning
# literal (TUNE-10000/9999/9876/9500/2026/1000) sits MID-LINE in backlog prose;
# all 1077 genuine rows are line-leading `- {ID} ·`. The archive surface was
# already hardened to filenames; tasks.md and backlog.md were not, so the same
# poison re-entered through the two unhardened surfaces.

@test "A01: prose-only 4-digit literal in backlog.md does not lift the ceiling" {
    printf -- '- TUNE-0001 · real row\n  Note: similar to TUNE-9999 discussed previously\n' \
        > "${FIXTURE_DIR}/datarim/backlog.md"

    run_helper TUNE "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "TUNE-0002" ]
}

@test "A02: prose-only 4-digit literal in tasks.md does not lift the ceiling" {
    printf -- '- TUNE-0001 · real row\n  fixture ids TUNE-9876 and TUNE-9500 are illustrative\n' \
        > "${FIXTURE_DIR}/datarim/tasks.md"

    run_helper TUNE "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "TUNE-0002" ]
}

@test "A03: 5-digit literal never lifts the ceiling and is never truncated to 4 digits" {
    # `grep -o "TUNE-[0-9]\{4\}"` over `TUNE-10000` yields the substring
    # `TUNE-1000` — a number that was never claimed by anyone. The ceiling
    # scan must anchor on BOTH sides so a 5-digit token contributes nothing.
    printf -- '- TUNE-0001 · real row\n  see the TUNE-10000 overflow fixture\n' \
        > "${FIXTURE_DIR}/datarim/backlog.md"

    run_helper TUNE "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "TUNE-0002" ]
}

@test "A04: full arcana-devs reproduction — poisoned prose plus real rows to 0541" {
    {
        printf -- '- TUNE-0540 · real row\n'
        printf -- '- TUNE-0541 · real row\n'
        printf -- '- TUNE-0538 · [prose] deliberate test-fixture literals (TUNE-10000, TUNE-9999,'
        printf -- ' TUNE-9876, TUNE-9500, TUNE-2026, TUNE-1000) sit in task descriptions and QA evidence\n'
    } > "${FIXTURE_DIR}/datarim/backlog.md"

    run_helper TUNE "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "TUNE-0542" ]
}

@test "A05: GUARD — a prose-only claim stays visible to the collision probe" {
    # The failure direction this task must NOT introduce. Tightening the
    # ceiling is safe; tightening the PROBE is not. An ID mentioned only in
    # prose ("renumbered from TUNE-0005") is still somebody's claim, so the
    # allocator must refuse to hand it out even though it never lifted the
    # ceiling. Rows reach 0004, so the candidate lands exactly on the
    # prose-only ID — the probe has to catch it and bump.
    {
        printf -- '- TUNE-0001 · row\n- TUNE-0002 · row\n'
        printf -- '- TUNE-0003 · row\n- TUNE-0004 · row [renumbered from TUNE-0005 earlier today]\n'
    } > "${FIXTURE_DIR}/datarim/backlog.md"

    run_helper TUNE "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "TUNE-0006" ]
    echo "$HERR" | grep -iE "already claimed|auto.?bump"
}

# ── Group B — defect 1: live tmux / git names are a claim surface ─────────────
#
# Reproduced on arcana-devs 2026-07-30 11:24:55. A batch-spawned orchestrator
# reserves an ID in its tmux SESSION NAME (`dr-<space>-<TASK-ID>`) minutes
# before any file records the claim. The allocator read files only, reported
# RESEARCH-0012 then RESEARCH-0013 as free while both were in flight, forced a
# double renumber, and the second allocation looked enough like an own-session
# leftover that a `tmux kill-session` was fired at another orchestrator's LIVE
# session ~13 minutes into its work.

@test "B01: a live tmux session name claims its ID" {
    printf -- '- TUNE-0001 · row\n' > "${FIXTURE_DIR}/datarim/tasks.md"
    export DATARIM_ID_TMUX_SESSIONS="dr-arcanada-TUNE-0002"

    run_helper TUNE "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "TUNE-0003" ]
    echo "$HERR" | grep -iE "already claimed|auto.?bump"
}

@test "B02: a git branch / worktree name claims its ID, case-insensitively" {
    # Branch names are lowercase by convention (`tune-0002-some-slug`); the
    # ID they carry is not.
    printf -- '- TUNE-0001 · row\n' > "${FIXTURE_DIR}/datarim/tasks.md"
    export DATARIM_ID_GIT_REFS="/home/dev/.worktrees/datarim/TUNE-0002
tune-0002-next-free-id"

    run_helper TUNE "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "TUNE-0003" ]
}

@test "B03: incident replay — four in-flight sessions ahead of the file ceiling" {
    # Files know RESEARCH-0011. Sessions hold 0012..0015, none of them yet
    # written anywhere. The allocator must skip the whole live block.
    printf -- '- RESEARCH-0011 · row\n' > "${FIXTURE_DIR}/datarim/tasks.md"
    export DATARIM_ID_TMUX_SESSIONS="dr-arcanada-RESEARCH-0012
dr-arcanada-RESEARCH-0013
dr-arcanada-RESEARCH-0014
dr-arcanada-RESEARCH-0015"

    run_helper RESEARCH "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "RESEARCH-0016" ]
}

@test "B04: live names feed the PROBE only — they must never lift the ceiling" {
    # Session and branch names are unconstrained free-form strings: they may be
    # stale (arcana-devs currently runs TUNE-0541 under a session literally
    # named `dr-arcanada-TUNE-0538`), abbreviated, or typo'd. That makes a hit
    # good enough to refuse an ID but not good enough to define the watermark.
    # Trusting them for the ceiling would rebuild defect 2 on a new surface.
    printf -- '- TUNE-0001 · row\n' > "${FIXTURE_DIR}/datarim/tasks.md"
    export DATARIM_ID_TMUX_SESSIONS="dr-arcanada-TUNE-9999"
    export DATARIM_ID_GIT_REFS="tune-9998-stale-branch"

    run_helper TUNE "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "TUNE-0002" ]
}

@test "B05: the real tmux surface is wired, not merely the test seam" {
    command -v tmux >/dev/null 2>&1 || skip "tmux not installed"
    # Ownership: this session is created HERE, in this run, under a name no
    # orchestrator uses, and is killed by this test alone. Never touch a
    # session you did not create (the 2026-07-30 incident).
    local sess="dr-tune0542-selftest-$$-ZZ-0002"
    tmux new-session -d -s "$sess" 'sleep 30' 2>/dev/null || skip "cannot start a tmux server here"

    printf -- '- ZZ-0001 · row\n' > "${FIXTURE_DIR}/datarim/tasks.md"
    unset DATARIM_ID_TMUX_SESSIONS   # exercise the live probe

    run_helper ZZ "${FIXTURE_DIR}"
    tmux kill-session -t "$sess" 2>/dev/null || true

    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "ZZ-0003" ]
}

# ── Group C — the 4-digit invariant ──────────────────────────────────────────
#
# RECLASSIFICATION. tests/tune-0461-id-collision-autobump.bats B07 previously
# required TUNE-10000 as the correct answer at the 9999 boundary ("no 4-digit
# truncation", absorbed from TUNE-0229). TUNE-0542 supersedes that reading, and
# C02 below is the proof rather than an appeal to taste: a 5-digit ID is
# INVISIBLE to the archive claim surface, whose glob is fixed at four digits.
# An allocator that emits one cannot see it again on the next call, so it hands
# the same ID out forever. TUNE-0229's real requirement — never emit a silently
# TRUNCATED id — is preserved: exhaustion now fails loudly instead.

@test "C01: exhausting the 4-digit space fails loudly instead of emitting 5 digits" {
    printf -- '- TUNE-9999 · row at the boundary\n' > "${FIXTURE_DIR}/datarim/tasks.md"

    run_helper TUNE "${FIXTURE_DIR}"
    [ "$HSTATUS" -ne 0 ]
    [ -z "$HID" ]
    echo "$HERR" | grep -iE "exhaust|4-digit|out of range|no free id"
}

@test "C02: proof — a 5-digit ID is invisible to the archive claim surface" {
    # The archive surface matches `archive-{PREFIX}-[0-9][0-9][0-9][0-9].md`.
    # An archived TUNE-10000 therefore does not register as claimed at all,
    # which is why emitting a 5-digit ID is not a cosmetic problem but a
    # self-collision generator.
    printf '# archived\n' \
        > "${FIXTURE_DIR}/documentation/archive/framework/archive-TUNE-10000.md"
    printf '# archived\n' \
        > "${FIXTURE_DIR}/documentation/archive/framework/archive-TUNE-0007.md"

    run_helper TUNE "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "TUNE-0008" ]
}

@test "C03: every successful allocation is exactly four digits" {
    for seed in 0001 0058 0099 0100 0999 0542; do
        printf -- "- TUNE-%s · row\n" "$seed" > "${FIXTURE_DIR}/datarim/tasks.md"
        run_helper TUNE "${FIXTURE_DIR}"
        [ "$HSTATUS" -eq 0 ]
        echo "$HID" | grep -qE '^TUNE-[0-9]{4}$' \
            || { echo "not 4-digit for seed ${seed}: ${HID}"; false; }
    done
}

# ── Group D — widened NAME claim surface ─────────────────────────────────────
#
# Absorbs TUNE-0538 item 1, reproduced during CTRL-0037: an epic decomposition
# wrote `datarim/tasks/{ID}-task-description.md` files but no tasks.md rows, so
# a 12-ID block was invisible and the allocator handed the first of them out
# again. A FILENAME carrying an ID is as structural a claim as an archive
# filename, so these count for the ceiling as well as the probe.

@test "D01: datarim/tasks/{ID}-task-description.md files are claimed (12-ID window)" {
    mkdir -p "${FIXTURE_DIR}/datarim/tasks"
    for n in 0038 0039 0040 0041 0042 0043 0044 0045 0046 0047 0048 0049; do
        printf '# brief\n' > "${FIXTURE_DIR}/datarim/tasks/CTRL-${n}-task-description.md"
    done
    # tasks.md / backlog.md deliberately absent — that is the defect.

    run_helper CTRL "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "CTRL-0050" ]
}

@test "D02: datarim/prd and datarim/plans filenames are claimed" {
    mkdir -p "${FIXTURE_DIR}/datarim/prd" "${FIXTURE_DIR}/datarim/plans"
    printf '# prd\n' > "${FIXTURE_DIR}/datarim/prd/PRD-TUNE-0007.md"
    printf '# plan\n' > "${FIXTURE_DIR}/datarim/plans/plan-TUNE-0006.md"

    run_helper TUNE "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "TUNE-0008" ]
}

@test "D03: runtime marker filenames (.auto, snapshots) are claimed" {
    mkdir -p "${FIXTURE_DIR}/datarim/.auto" "${FIXTURE_DIR}/datarim/snapshots"
    printf 'auto\n' > "${FIXTURE_DIR}/datarim/.auto/TUNE-0009.mode"
    printf 'snap\n' > "${FIXTURE_DIR}/datarim/snapshots/TUNE-0008.snapshot.md"

    run_helper TUNE "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "TUNE-0010" ]
}

@test "D04: a 5-digit filename is ignored by the widened file surface too" {
    # The class, not the hole: the same anchoring rule that protects the prose
    # surface must protect every filename surface added above.
    mkdir -p "${FIXTURE_DIR}/datarim/tasks"
    printf '# brief\n' > "${FIXTURE_DIR}/datarim/tasks/TUNE-10000-task-description.md"
    printf '# brief\n' > "${FIXTURE_DIR}/datarim/tasks/TUNE-0003-task-description.md"

    run_helper TUNE "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "TUNE-0004" ]
}

@test "D05: fixture isolation — the widened surface still reads only the supplied root" {
    run_helper ZZ "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "ZZ-0001" ]
}

@test "D06: an ID-named DIRECTORY is claimed, not just an ID-named file" {
    # A task can stake its claim with a directory before it writes any file —
    # per-task consilium/qa/snapshot folders do exactly that. Scanning only
    # `-type f` left 89 such claims invisible on the live workspace, which is
    # the same "one hole, not the class" mistake this task exists to correct.
    mkdir -p "${FIXTURE_DIR}/datarim/consilium/TUNE-0077"

    run_helper TUNE "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "TUNE-0078" ]
}

@test "D07: ceiling accepts the '*' and '+' list markers, not only '-'" {
    # Markdown allows three bullet markers. Recognising only one made the
    # ceiling silently degrade from "next free" to "lowest free" on an index
    # written with another — safe, because the probe still refuses a claimed
    # ID, but surprising and invisible.
    printf -- '* TUNE-0050 · star-marker row\n' > "${FIXTURE_DIR}/datarim/tasks.md"
    run_helper TUNE "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "TUNE-0051" ]

    printf -- '+ TUNE-0060 · plus-marker row\n' > "${FIXTURE_DIR}/datarim/tasks.md"
    run_helper TUNE "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "TUNE-0061" ]
}

@test "D08: GUARD — widening the marker set must not admit INDENTED sub-bullets" {
    # The anchor stays at column zero. Accepting leading whitespace would let a
    # nested prose bullet ("  - see TUNE-9999 for the fixture") back into the
    # ceiling and reopen defect 2 through the marker set instead of the grep.
    printf -- '- TUNE-0003 · real row\n  - see TUNE-9999 for the fixture\n' \
        > "${FIXTURE_DIR}/datarim/tasks.md"

    run_helper TUNE "${FIXTURE_DIR}"
    [ "$HSTATUS" -eq 0 ]
    [ "$HID" = "TUNE-0004" ]
}
