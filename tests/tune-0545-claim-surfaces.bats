#!/usr/bin/env bats
# tune-0545-claim-surfaces.bats
#
# TUNE-0545 items (1) and (2) — the two claim surfaces next-free-id.sh does not
# yet read.
#
# Both are surfaces that demonstrably hid live claims in the field: two
# consecutive IDs were handed out while task files sat in sibling worktrees and
# the only other trace was a commit subject on a branch that was not checked
# out. A search rooted at the main checkout is structurally blind to both.
#
# Group W — per-worktree datarim/tasks/ FILENAMES (item 1).
# Group L — commit subjects across ALL refs (item 2).
# Group P — both surfaces are PROBE-ONLY and must never lift the ceiling.
#
# Group G — the same two surfaces driven through REAL git, no seam.
#
# Groups W/L/P are hermetic: the live probes are replaced through the documented
# env seams, so they pass identically on a host running dozens of sessions.
# Group G deliberately is not — a seam-only suite leaves the actual git
# invocations untested, and mutating `git log --all` to `git log -1` broke
# nothing until G01 existed.

HELPER="${BATS_TEST_DIRNAME}/../dev-tools/next-free-id.sh"

setup() {
    FIXTURE_DIR="$(mktemp -d)"
    mkdir -p "${FIXTURE_DIR}/datarim/tasks"
    mkdir -p "${FIXTURE_DIR}/documentation/archive/framework"
    # Neutralise the pre-existing live surfaces so only the surface under test
    # can influence the result.
    export DATARIM_ID_TMUX_SESSIONS=""
    export DATARIM_ID_GIT_REFS=""
    export DATARIM_ID_GIT_LOG=""
    export DATARIM_ID_WORKTREE_PATHS=""
}

teardown() {
    rm -rf "${FIXTURE_DIR}" "${SIBLING_DIR:-/nonexistent-xyz}"
    unset DATARIM_ID_TMUX_SESSIONS DATARIM_ID_GIT_REFS \
          DATARIM_ID_GIT_LOG DATARIM_ID_WORKTREE_PATHS
}

# Seed the main checkout so the ceiling is a known value.
seed_main_ceiling() {
    printf -- '- TUNE-0100 · pending · P2 · L1 · seed\n' \
        > "${FIXTURE_DIR}/datarim/backlog.md"
}

# ── Group W — per-worktree task FILENAMES (item 1) ────────────────────────────

# W01: the defect, minimally. A sibling worktree holds a task-description file
# for an ID with ZERO presence in the main checkout. The allocator must not
# hand that ID out.
@test "W01: an ID claimed only by a task file in a sibling worktree is refused" {
    seed_main_ceiling
    SIBLING_DIR="$(mktemp -d)"
    mkdir -p "${SIBLING_DIR}/datarim/tasks"
    : > "${SIBLING_DIR}/datarim/tasks/TUNE-0101-task-description.md"

    export DATARIM_ID_WORKTREE_PATHS="${SIBLING_DIR}"
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    # ceiling is 0100, so the naive answer is 0101 — which the sibling holds
    [ "$output" != "TUNE-0101" ]
}

# W02: the scan must cover every worktree in the list, not just the first.
@test "W02: every worktree path is scanned, not only the first" {
    seed_main_ceiling
    SIB_A="$(mktemp -d)"; SIB_B="$(mktemp -d)"
    mkdir -p "${SIB_A}/datarim/tasks" "${SIB_B}/datarim/tasks"
    : > "${SIB_A}/datarim/tasks/TUNE-0101-task-description.md"
    : > "${SIB_B}/datarim/tasks/TUNE-0102-init-task.md"

    export DATARIM_ID_WORKTREE_PATHS="${SIB_A}
${SIB_B}"
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" != "TUNE-0101" ]
    [ "$output" != "TUNE-0102" ]
    rm -rf "${SIB_A}" "${SIB_B}"
}

# W03: a missing or unreadable worktree path must not break allocation.
# Worktree lists routinely contain stale entries for deleted directories.
@test "W03: a stale worktree path is tolerated, not fatal" {
    seed_main_ceiling
    export DATARIM_ID_WORKTREE_PATHS="/nonexistent/worktree/path"
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0101" ]
}

# ── Group L — commit subjects across all refs (item 2) ───────────────────────

# L01: the defect. An ID whose only trace is a commit subject on some branch
# must not be handed out.
@test "L01: an ID appearing only in a commit subject is refused" {
    seed_main_ceiling
    export DATARIM_ID_GIT_LOG="feat(TUNE-0101): something already in flight"
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" != "TUNE-0101" ]
}

# L02: multi-line log output — every subject line counts, not just the first.
@test "L02: all log lines are scanned" {
    seed_main_ceiling
    export DATARIM_ID_GIT_LOG="chore: unrelated
feat(TUNE-0101): first
fix(TUNE-0102): second"
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" != "TUNE-0101" ]
    [ "$output" != "TUNE-0102" ]
}

# L03: an empty log seam must not refuse anything.
@test "L03: empty commit-log surface leaves allocation unchanged" {
    seed_main_ceiling
    export DATARIM_ID_GIT_LOG=""
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0101" ]
}

# ── Group P — probe-only discipline ──────────────────────────────────────────
#
# Both new surfaces are free-form prose or foreign-checkout state. A hit is
# good enough to REFUSE an ID; it must NOT define the watermark. Trusting
# either for the ceiling rebuilds the fixture-poison defect on a new surface —
# a commit subject saying "renumbered TUNE-9000" would otherwise push every
# future ID past 9000.

@test "P01: a high ID in a commit subject does not lift the ceiling" {
    seed_main_ceiling
    export DATARIM_ID_GIT_LOG="docs: renumbered away from TUNE-9000"
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    # must stay just above the real ceiling, NOT jump to 9001
    [ "$output" = "TUNE-0101" ]
}

@test "P02: a high ID in a worktree task file does not lift the ceiling" {
    seed_main_ceiling
    SIBLING_DIR="$(mktemp -d)"
    mkdir -p "${SIBLING_DIR}/datarim/tasks"
    : > "${SIBLING_DIR}/datarim/tasks/TUNE-9000-task-description.md"
    export DATARIM_ID_WORKTREE_PATHS="${SIBLING_DIR}"
    run bash "${HELPER}" "TUNE" "${FIXTURE_DIR}"
    [ "$status" -eq 0 ]
    [ "$output" = "TUNE-0101" ]
}

# ── Group D — the surfaces are documented ────────────────────────────────────

@test "D01: the script documents the per-worktree filename surface" {
    grep -qiE 'worktree' "${HELPER}"
    grep -q 'DATARIM_ID_WORKTREE_PATHS' "${HELPER}"
}

@test "D02: the script documents the all-refs commit-subject surface" {
    grep -q 'DATARIM_ID_GIT_LOG' "${HELPER}"
}

# ── Group G — the REAL git paths, no seam ────────────────────────────────────
#
# Groups W and L drive the surfaces through their env seams, which keeps them
# hermetic but leaves the actual git invocations unexercised. That is a real
# blind spot: mutating `git log --all` to `git log -1` broke nothing in the
# seam-driven tests. These two build a genuine repository so the discovery
# commands themselves are under test.

@test "G01: real git — an ID on a NON-checked-out branch is refused (exercises --all)" {
    unset DATARIM_ID_GIT_LOG          # force the live git path
    export DATARIM_ID_GIT_REFS=""     # keep branch NAMES out of it
    REPO="$(mktemp -d)"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
    git -C "$REPO" config commit.gpgsign false
    mkdir -p "$REPO/datarim"
    printf -- '- TUNE-0100 · pending · P2 · L1 · seed\n' > "$REPO/datarim/backlog.md"
    git -C "$REPO" add -A; git -C "$REPO" commit -qm "chore: seed"
    # a claim that exists ONLY as a commit subject on another branch
    git -C "$REPO" checkout -q -b sidebranch
    git -C "$REPO" commit -q --allow-empty -m "feat(TUNE-0101): in flight elsewhere"
    git -C "$REPO" checkout -q -

    run bash "${HELPER}" "TUNE" "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" != "TUNE-0101" ]
    rm -rf "$REPO"
}

@test "G02: real git — a task file in a linked worktree is refused (exercises worktree list)" {
    unset DATARIM_ID_WORKTREE_PATHS   # force the live git path
    export DATARIM_ID_GIT_REFS=""
    export DATARIM_ID_GIT_LOG=""
    REPO="$(mktemp -d)"; LINKED="$(mktemp -d)"; rmdir "$LINKED"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
    git -C "$REPO" config commit.gpgsign false
    mkdir -p "$REPO/datarim"
    printf -- '- TUNE-0100 · pending · P2 · L1 · seed\n' > "$REPO/datarim/backlog.md"
    git -C "$REPO" add -A; git -C "$REPO" commit -qm "chore: seed"
    git -C "$REPO" worktree add -q -b wt "$LINKED"
    mkdir -p "$LINKED/datarim/tasks"
    : > "$LINKED/datarim/tasks/TUNE-0101-task-description.md"

    run bash "${HELPER}" "TUNE" "$REPO"
    [ "$status" -eq 0 ]
    [ "$output" != "TUNE-0101" ]
    git -C "$REPO" worktree remove --force "$LINKED" 2>/dev/null || true
    rm -rf "$REPO" "$LINKED"
}
