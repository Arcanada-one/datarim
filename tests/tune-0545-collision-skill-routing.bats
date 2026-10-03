#!/usr/bin/env bats
# TUNE-0545 — the collision-window skill must route agents to the RESERVING
# allocator. TUNE-0285 shipped an atomic mkdir mutex that works (its own suite
# proves it), but the skill agents read when picking an ID never mentioned it
# and prescribed a hand-rolled probe blind to tmux, worktrees, gitignore and
# git log --all. A sound mutex wired to nothing still produces collisions:
# three occurred on 2026-07-31 alone. These assertions keep the wiring.

SKILL="${BATS_TEST_DIRNAME}/../skills/dr-init-id-collision-window/SKILL.md"

@test "S01: skill names the reserving allocator" {
    grep -q 'next-free-id\.sh' "$SKILL"
}

@test "S02: skill states the allocator reserves, not merely probes" {
    grep -qiE 'probes AND reserves|both probes and .*reserve' "$SKILL"
}

@test "S03: skill documents the atomic mkdir reservation mutex" {
    grep -q 'id-reservations' "$SKILL"
    grep -qi 'mkdir' "$SKILL"
}

@test "S04: skill documents all three reversibility paths" {
    grep -qi 'TTL' "$SKILL"
    grep -q -- '--release' "$SKILL"
    grep -qi 'rm -rf datarim/\.id-reservations' "$SKILL"
}

@test "S05: skill documents release-after-first-artifact semantics" {
    grep -qiE 'after your first artifact|first artifact is written' "$SKILL"
}

@test "S06: skill warns about the gitignore trap with the actual flag" {
    grep -q -- '--no-ignore' "$SKILL"
}

@test "S07: skill covers host-global surfaces a file scan cannot see" {
    grep -q 'tmux' "$SKILL"
    grep -q 'worktree' "$SKILL"
}

@test "S08: skill covers per-worktree task filenames and all-branch subjects" {
    grep -q 'git log --all' "$SKILL"
    # shellcheck disable=SC2016  # matching the LITERAL "$wt" the skill prints, not expanding it
    grep -qE 'find .*\$wt/datarim|for wt in' "$SKILL"
}

@test "S09: the rename path also allocates via the reserving allocator" {
    sed -n '/^## Resolution/,$p' "$SKILL" | grep -q 'next-free-id\.sh'
}

@test "S10: the allocator the skill names actually exists and is executable" {
    [ -x "${BATS_TEST_DIRNAME}/../dev-tools/next-free-id.sh" ]
}

@test "S11: that allocator really implements the reservation the skill promises" {
    grep -q 'id-reservations' "${BATS_TEST_DIRNAME}/../dev-tools/next-free-id.sh"
    grep -q -- '--release' "${BATS_TEST_DIRNAME}/../dev-tools/next-free-id.sh"
}
