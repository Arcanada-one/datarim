#!/usr/bin/env bats
# datarim-history-gitignore-negation.bats — the gitignore-negation gotcha
#
# The consumer .gitignore wholesale-ignores /datarim/. A bare !/datarim/history/
# does NOT un-ignore nested files because git never descends into an ignored
# directory. The negation MUST re-include the directory AND its contents:
#   /datarim/
#   !/datarim/history/
#   !/datarim/history/**
# These tests assert the empirical git behaviour via `git check-ignore`.

DOCTOR="$BATS_TEST_DIRNAME/../scripts/datarim-doctor.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    cd "$TMPROOT"
    git init -q
    git config user.email t@t.t
    git config user.name t
    mkdir -p datarim/docs datarim/history
    printf 'x\n' > datarim/docs/evolution-log.md
    printf 'y\n' > datarim/history/evolution-log.md
}

teardown() {
    cd /
    rm -rf "$TMPROOT"
}

# git check-ignore: exit 0 = path IS ignored; exit 1 = NOT ignored.

@test "N1 wholesale /datarim/ ignores both docs and history before negation" {
    printf '/datarim/\n' > .gitignore
    run git -C "$TMPROOT" check-ignore -q datarim/docs/evolution-log.md
    [ "$status" -eq 0 ]   # ignored
    run git -C "$TMPROOT" check-ignore -q datarim/history/evolution-log.md
    [ "$status" -eq 0 ]   # ignored
}

@test "N2 bare directory-only negation FAILS to un-ignore nested files (the gotcha)" {
    printf '/datarim/\n!/datarim/history/\n' > .gitignore
    run git -C "$TMPROOT" check-ignore -q datarim/history/evolution-log.md
    [ "$status" -eq 0 ]   # STILL ignored — proves the gotcha is real
}

@test "N3 glob-form ignore (/datarim/*) + contents negation un-ignores nested history files" {
    # The trailing-slash /datarim/ cannot be negated (N2). The working canonical
    # form ignores ENTRIES (/datarim/*) so a sub-path can be re-included.
    printf '/datarim/*\n!/datarim/history/\n!/datarim/history/**\n' > .gitignore
    run git -C "$TMPROOT" check-ignore -q datarim/history/evolution-log.md
    [ "$status" -eq 1 ]   # NOT ignored — negation works
}

@test "N4 negation does not leak: docs/ stays ignored under glob form" {
    printf '/datarim/*\n!/datarim/history/\n!/datarim/history/**\n' > .gitignore
    run git -C "$TMPROOT" check-ignore -q datarim/docs/evolution-log.md
    [ "$status" -eq 0 ]   # docs still ignored
}

@test "N5 doctor --fix writes a working negation block (end-to-end)" {
    printf '/datarim/\n' > .gitignore
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    [ "$status" -eq 0 ]
    # the ledger moved to history/ and is now NOT ignored
    run git -C "$TMPROOT" check-ignore -q datarim/history/evolution-log.md
    [ "$status" -eq 1 ]   # NOT ignored
    # docs/ is gone, so nothing ignored to check there; tasks/ still ignored
    printf 'z\n' > datarim/state-probe.md
    run git -C "$TMPROOT" check-ignore -q datarim/state-probe.md
    [ "$status" -eq 0 ]   # ephemeral datarim/ state still ignored
}

@test "N6 doctor --fix writes an explicit /datarim/.backups/ ignore line" {
    # F-dispatch-3: the backup dir must be explicitly ignored, not only covered
    # incidentally by the wholesale /datarim/* rule — so a consumer that later
    # adds a negation under the glob form cannot accidentally un-ignore backups.
    printf '/datarim/\n' > .gitignore
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    [ "$status" -eq 0 ]
    grep -qxF '/datarim/.backups/' .gitignore
    # and .backups/ is empirically ignored
    mkdir -p datarim/.backups
    printf 'b\n' > datarim/.backups/backlog.md.20260101T000000Z.bak
    run git -C "$TMPROOT" check-ignore -q datarim/.backups/backlog.md.20260101T000000Z.bak
    [ "$status" -eq 0 ]   # ignored
}

@test "N7 the /datarim/.backups/ line is idempotent across two --fix runs" {
    printf '/datarim/\n' > .gitignore
    "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    # re-create a docs ledger so the second --fix has work and re-touches gitignore
    mkdir -p datarim/docs; printf 'x\n' > datarim/docs/activity-log.md
    "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    [ "$(grep -cxF '/datarim/.backups/' .gitignore)" -eq 1 ]
}
