#!/usr/bin/env bats
# check-archive-landing.bats — TUNE-0562 regression cover for the
# archive-vs-reality landing verifier.
#
# Every assertion here is mutation-checked: reverting the behaviour under test
# turns the case red. The gate's whole purpose is to refuse to trust a claim, so
# a test suite that passes against a broken gate would be self-defeating.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SUT="$REPO_ROOT/dev-tools/check-archive-landing.sh"
    [ -x "$SUT" ] || skip "check-archive-landing.sh not executable"

    # A self-contained git repo so the tests never depend on the real history,
    # on network access, or on which branch the developer happens to be on.
    FIX="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$FIX/documentation/archive/framework" "$FIX/dev-tools" "$FIX/datarim"
    cd "$FIX" || return 1
    git init -q .
    git config user.email t@example.invalid
    git config user.name  t
    git config commit.gpgsign false

    mkdir -p "$FIX/skills/real-skill"
    echo "shipped" > "$FIX/skills/real-skill/SKILL.md"
    echo "# Backlog" > "$FIX/datarim/backlog.md"
    git add -A
    git commit -qm "base"
    LANDED_SHA="$(git rev-parse HEAD)"
}

# Write an archive whose completed_date is inside the ratchet window.
mkarchive() {  # $1=id  $2=body
    cat > "$FIX/documentation/archive/framework/archive-$1.md" <<EOF
---
id: $1
completed_date: 2026-07-15
---
$2
EOF
}

run_a() { run bash "$SUT" --root "$FIX" --ref HEAD \
    --archives "$FIX/documentation/archive/framework" \
    --direction a --report --no-scope-guard; }

@test "V-AC-1: an archive whose artefact and SHA both landed passes" {
    mkarchive "TUNE-9001" "Shipped \`skills/real-skill/SKILL.md\` in \`$LANDED_SHA\`."
    run_a
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT: PASS"* ]]
}

@test "V-AC-2: a cited SHA whose files never landed is a blocking violation" {
    # The TUNE-0334 case exactly: work committed on a side branch, archive
    # written, branch never merged. Six weeks of silent breakage came from this.
    # The signal is that NONE of the commit's files exist on the ref — not mere
    # unreachability, which squash-merge produces routinely (see V-AC-16).
    git checkout -q -b sidebranch
    echo "unmerged" > "$FIX/skills/real-skill/ADRIFT.md"
    git add -A && git commit -qm "side work"
    local orphan; orphan="$(git rev-parse HEAD)"
    git checkout -q -
    mkarchive "TUNE-9002" "Delivered in \`$orphan\`."
    run_a
    [ "$status" -eq 1 ]
    [[ "$output" == *"ADRIFT-SHA"* ]]
}

@test "V-AC-16: a squash-landed SHA is not a violation" {
    # Squash-merge rewrites the commit, so the branch's original SHA is never an
    # ancestor of main even though every byte of its content shipped. Treating
    # unreachability alone as failure flagged TUNE-0210's five commits as lost
    # while both their artefacts were live on main. Ancestry is not landing.
    git checkout -q -b squashed
    echo "content" > "$FIX/skills/real-skill/SQUASHED.md"
    git add -A && git commit -qm "work that will be squashed"
    local orig; orig="$(git rev-parse HEAD)"
    git checkout -q -
    # Simulate the squash: same file content, different commit object.
    echo "content" > "$FIX/skills/real-skill/SQUASHED.md"
    git add -A && git commit -qm "squashed landing (#123)"
    mkarchive "TUNE-9016" "Delivered in \`$orig\`."
    run_a
    [ "$status" -eq 0 ]
    [[ "$output" == *"SQUASHED-SHA"* ]]
    [[ "$output" != *"ADRIFT-SHA"* ]]
}

@test "V-AC-3: an artefact that existed and is now gone is a blocking violation" {
    echo "doomed" > "$FIX/dev-tools/doomed.sh"
    git add -A && git commit -qm "add doomed"
    git rm -q "$FIX/dev-tools/doomed.sh"
    git commit -qm "remove doomed"
    mkarchive "TUNE-9003" "Delivered \`dev-tools/doomed.sh\`."
    run_a
    [ "$status" -eq 1 ]
    [[ "$output" == *"REMOVED-ARTEFACT"* ]]
}

@test "V-AC-4: a renamed artefact is MOVED, not a violation" {
    # Regression guard for a real defect in this gate: `ls-tree | grep -q` under
    # `pipefail` reports no-match for EVERY file, because grep -q exits early and
    # git dies on SIGPIPE. That misfiled all 98 docs/->documentation/ renames as
    # removals. If this case ever goes red, check for an early-exit pipeline.
    mkdir -p "$FIX/documentation/reference"
    git mv "$FIX/skills/real-skill/SKILL.md" "$FIX/documentation/reference/SKILL.md"
    # The match MUST land early with a lot of output still to come, or the buggy
    # `grep -q` form passes and this test proves nothing. `grep -q` exits on the
    # first hit; git then keeps writing and takes SIGPIPE, which `pipefail`
    # surfaces as failure — but only if writing is still in progress. With the
    # match last (or a tiny tree), git finishes first and nothing breaks.
    # `documentation/` sorts before `skills/`, so the padding below guarantees
    # ~1000 unread lines after the hit — mirroring the real tree, where the match
    # sat at line 384 of 1108.
    for i in $(seq 1 1000); do echo pad > "$FIX/skills/pad-$i.md"; done
    git add -A
    git commit -qm "move it"
    mkarchive "TUNE-9004" "Delivered \`skills/real-skill/SKILL.md\`."
    run_a
    [ "$status" -eq 0 ]
    [[ "$output" == *"MOVED-ARTEFACT"* ]]
    [[ "$output" != *"REMOVED-ARTEFACT"* ]]
}

@test "V-AC-5: an artefact with no history here is FOREIGN, not a violation" {
    # ROB-0001's docs/AER-*.md live in the Rules-of-Robotics repo but its archive
    # is filed under framework/. Judging it against this repo says nothing.
    mkarchive "TUNE-9005" "Delivered \`docs/never-existed-here.md\`."
    run_a
    [ "$status" -eq 0 ]
    [[ "$output" == *"FOREIGN-ARTEFACT"* ]]
}

@test "V-AC-6: an unresolvable SHA is unverifiable, not a declared loss" {
    # Pre-2026-05-19-rewrite SHAs cannot resolve by construction. Calling those
    # losses would keep the gate permanently red, i.e. ignored.
    mkarchive "TUNE-9006" "Delivered in \`deadbeef\`."
    run_a
    [ "$status" -eq 0 ]
    [[ "$output" == *"UNVERIFIABLE-SHA"* ]]
}

@test "V-AC-7: archives completed before the baseline are skipped" {
    cat > "$FIX/documentation/archive/framework/archive-TUNE-9007.md" <<'EOF'
---
id: TUNE-9007
completed_date: 2026-04-01
---
Delivered `dev-tools/never-existed.sh`.
EOF
    run_a
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 pre-baseline"* ]]
}

@test "V-AC-8: an archive with no completed_date is skipped, not guessed at" {
    cat > "$FIX/documentation/archive/framework/archive-TUNE-9008.md" <<'EOF'
# no frontmatter at all
Delivered `dev-tools/never-existed.sh`.
EOF
    run_a
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 undated"* ]]
}

@test "V-AC-9: --since overrides the baseline and re-judges older archives" {
    cat > "$FIX/documentation/archive/framework/archive-TUNE-9009.md" <<'EOF'
---
id: TUNE-9009
completed_date: 2026-04-01
---
Delivered `dev-tools/gone.sh`.
EOF
    echo x > "$FIX/dev-tools/gone.sh"; git add -A; git commit -qm add
    git rm -q "$FIX/dev-tools/gone.sh"; git commit -qm rm
    run bash "$SUT" --root "$FIX" --ref HEAD \
        --archives "$FIX/documentation/archive/framework" \
        --since 2026-01-01 --direction a --report --no-scope-guard
    [ "$status" -eq 1 ]
    [[ "$output" == *"REMOVED-ARTEFACT"* ]]
}

@test "V-AC-10: direction B flags an open row whose artefact already ships" {
    cat > "$FIX/datarim/backlog.md" <<'EOF'
# Backlog
- TUNE-9010 · pending · P3 · L1 · Build `skills/real-skill/SKILL.md` from scratch
EOF
    run bash "$SUT" --root "$FIX" --ref HEAD --backlog "$FIX/datarim/backlog.md" \
        --direction b --report
    [ "$status" -eq 0 ]
    [[ "$output" == *"STALE-LABEL?"* ]]
    [[ "$output" == *"TUNE-9010"* ]]
}

@test "V-AC-11: direction B never fails the build, even when it finds things" {
    # B is a heuristic: a path existing does not prove the row's intent was met.
    # If this ever exits non-zero, someone has promoted a guess to a verdict.
    cat > "$FIX/datarim/backlog.md" <<'EOF'
# Backlog
- TUNE-9011 · pending · P3 · L1 · Build `skills/real-skill/SKILL.md`
- TUNE-9012 · in_progress · P2 · L1 · Also `skills/real-skill/SKILL.md`
EOF
    run bash "$SUT" --root "$FIX" --ref HEAD --backlog "$FIX/datarim/backlog.md" \
        --direction b --report
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT: PASS"* ]]
}

@test "V-AC-12: a done row is not reported by direction B" {
    cat > "$FIX/datarim/backlog.md" <<'EOF'
# Backlog
- TUNE-9013 · done · P3 · L1 · Built `skills/real-skill/SKILL.md`
EOF
    run bash "$SUT" --root "$FIX" --ref HEAD --backlog "$FIX/datarim/backlog.md" \
        --direction b --report
    [ "$status" -eq 0 ]
    [[ "$output" != *"STALE-LABEL?"* ]]
}

@test "V-AC-13: the scope guard refuses a wrong-repo run instead of crying wolf" {
    # Pointing --archives at another project's archives produced 2865 false
    # violations before this guard existed. A gate nobody can trust gets muted.
    for i in $(seq 1 30); do
        cat > "$FIX/documentation/archive/framework/archive-FOR-$i.md" <<EOF
---
id: FOR-$i
completed_date: 2026-07-15
---
Delivered \`dev-tools/absent-$i.sh\` and \`scripts/absent-$i.sh\`.
EOF
        # Give each path real history so they count as REMOVED, not FOREIGN.
        mkdir -p "$FIX/scripts"
        echo x > "$FIX/dev-tools/absent-$i.sh"; echo x > "$FIX/scripts/absent-$i.sh"
    done
    git add -A; git commit -qm "add then remove"
    for i in $(seq 1 30); do
        git rm -q "$FIX/dev-tools/absent-$i.sh" "$FIX/scripts/absent-$i.sh"
    done
    git commit -qm "remove all"
    run bash "$SUT" --root "$FIX" --ref HEAD \
        --archives "$FIX/documentation/archive/framework" --direction a
    [ "$status" -eq 3 ]
    [[ "$output" == *"DIFFERENT repo"* ]] || [[ "$output" == *"different repo"* ]]
}

@test "V-AC-14: --direction rejects an unknown value" {
    run bash "$SUT" --root "$FIX" --direction sideways
    [ "$status" -eq 2 ]
}

@test "V-AC-15: an unresolvable --ref is a clean refusal, not a crash" {
    run bash "$SUT" --root "$FIX" --ref no/such/ref --direction a
    [ "$status" -eq 3 ]
    [[ "$output" == *"not resolvable"* ]]
}
