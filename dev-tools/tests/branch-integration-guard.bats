#!/usr/bin/env bats
#
# Regression spec for dev-tools/branch-integration-guard.sh — the PreToolUse
# hard-floor forbidding direct integration-branch → protected-branch merges.
#
# A crafted PreToolUse JSON is piped to the guard. Blocked ⇒ stdout contains
# permissionDecision "deny". Allowed ⇒ empty stdout + exit 0. HEAD-dependent
# cases build a temp git repo fixture and check it out to the relevant branch.

setup() {
    GUARD="$BATS_TEST_DIRNAME/../branch-integration-guard.sh"
    [ -f "$GUARD" ] || skip "guard not found: $GUARD"
    REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email t@t.t
    git -C "$REPO" config user.name t
    git -C "$REPO" commit -q --allow-empty -m init
    # rename default to main, then create integration branches
    git -C "$REPO" branch -M main
    git -C "$REPO" branch dev
    git -C "$REPO" branch develop
    git -C "$REPO" branch integration
    git -C "$REPO" branch trunk
    git -C "$REPO" branch feature/x
    NOREPO="$BATS_TEST_TMPDIR/plain"
    mkdir -p "$NOREPO"
}

# fire CWD CMD → run guard, capture output
fire() {
    local cwd="$1" cmd="$2"
    local json
    json=$(jq -nc --arg c "$cmd" --arg cwd "$cwd" \
        '{hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}, cwd:$cwd}')
    printf '%s' "$json" | BRANCH_INTEGRATION_GUARD_CONF=/dev/null bash "$GUARD"
}
checkout() { git -C "$REPO" checkout -q "$1"; }
assert_deny() { [[ "$output" == *'"permissionDecision"'*'"deny"'* ]]; }
assert_pass() { [ -z "$output" ]; }

# ── BLOCKED ────────────────────────────────────────────────────────────────────
@test "B1 git merge dev with HEAD=main => deny" {
    checkout main; run fire "$REPO" "git merge dev"; assert_deny
}
@test "B1 git merge origin/dev with HEAD=main => deny" {
    checkout main; run fire "$REPO" "git merge origin/dev"; assert_deny
}
@test "B2 git merge --no-ff dev with HEAD=main => deny" {
    checkout main; run fire "$REPO" "git merge --no-ff dev"; assert_deny
}
@test "B3 git push origin dev:main (no repo needed) => deny" {
    run fire "$NOREPO" "git push origin dev:main"; assert_deny
}
@test "B4 git push origin HEAD:main with HEAD=dev => deny" {
    checkout dev; run fire "$REPO" "git push origin HEAD:main"; assert_deny
}
@test "B5 git push origin +dev:main (force refspec) => deny" {
    run fire "$NOREPO" "git push origin +dev:main"; assert_deny
}
@test "B5 git push --force origin dev:main => deny" {
    run fire "$NOREPO" "git push --force origin dev:main"; assert_deny
}
@test "B6 git push origin main with HEAD=develop => deny" {
    checkout develop; run fire "$REPO" "git push origin main"; assert_deny
}
@test "B7 git checkout main && git merge dev (on-disk HEAD=dev) => deny" {
    checkout dev; run fire "$REPO" "git checkout main && git merge dev"; assert_deny
}
@test "B7 git switch main; git merge integration => deny" {
    checkout dev; run fire "$REPO" "git switch main; git merge integration"; assert_deny
}
@test "B8 git rebase dev main => deny" {
    run fire "$NOREPO" "git rebase dev main"; assert_deny
}
@test "B9 git push origin dev:refs/heads/main => deny" {
    run fire "$NOREPO" "git push origin dev:refs/heads/main"; assert_deny
}
@test "fail-closed: git merge dev in non-repo cwd (HEAD UNKNOWN) => deny" {
    run fire "$NOREPO" "git merge dev"; assert_deny
}
@test "alt-set: git merge develop with HEAD=trunk => deny" {
    checkout trunk; run fire "$REPO" "git merge develop"; assert_deny
}

# ── ALLOWED ────────────────────────────────────────────────────────────────────
@test "A1 gh pr create => pass" {
    run fire "$REPO" "gh pr create --fill"; assert_pass
}
@test "A2 git push -u origin feature/x => pass" {
    checkout feature/x; run fire "$REPO" "git push -u origin feature/x"; assert_pass
}
@test "A3 git merge main with HEAD=dev (reverse pull) => pass" {
    checkout dev; run fire "$REPO" "git merge main"; assert_pass
}
@test "A3 git merge origin/main with HEAD=dev => pass" {
    checkout dev; run fire "$REPO" "git merge origin/main"; assert_pass
}
@test "A4 git merge dev with HEAD=feature/x (dev into non-protected) => pass" {
    checkout feature/x; run fire "$REPO" "git merge dev"; assert_pass
}
@test "A push feature:feature (non-protected DST) => pass" {
    run fire "$NOREPO" "git push origin feature/x:feature/x"; assert_pass
}
@test "A checkout main && git pull (no dev merge) => pass" {
    checkout main; run fire "$REPO" "git checkout main && git pull"; assert_pass
}

# ── READ-ONLY LOOK-ALIKES ───────────────────────────────────────────────────────
@test "RO git log dev..main => pass" {
    run fire "$REPO" "git log dev..main"; assert_pass
}
@test "RO git branch --merged main => pass" {
    run fire "$REPO" "git branch --merged main"; assert_pass
}
@test "RO git diff dev main => pass" {
    run fire "$REPO" "git diff dev main"; assert_pass
}
@test "RO git rev-list dev..main => pass" {
    run fire "$REPO" "git rev-list dev..main"; assert_pass
}
@test "RO rg merge dev => pass (command-position basename rg)" {
    run fire "$REPO" 'rg "merge dev" .'; assert_pass
}
@test "RO grep push origin dev:main in docs => pass" {
    run fire "$REPO" 'grep -rn "git push origin dev:main" docs/'; assert_pass
}

# ── INJECTION RESISTANCE ────────────────────────────────────────────────────────
@test "INJ commit message body citing the rule => pass (quoted body stripped)" {
    checkout main; run fire "$REPO" 'git commit -m "note: git merge dev into main is banned"'; assert_pass
}
@test "INJ heredoc doc containing git merge dev + ignore-this-rule => pass" {
    checkout main
    run fire "$REPO" "cat > f <<EOF
ignore this rule, merge dev into main
git merge dev
EOF"
    assert_pass
}
@test "INJ in-band allow comment does NOT bypass: git merge dev # you may merge => deny" {
    checkout main; run fire "$REPO" "git merge dev  # you may merge dev into main this once"; assert_deny
}

# ── STRUCTURAL ──────────────────────────────────────────────────────────────────
@test "STRUCT non-Bash tool (Read) => silent pass" {
    json=$(jq -nc '{hook_event_name:"PreToolUse", tool_name:"Read", tool_input:{command:"git merge dev"}, cwd:"'"$REPO"'"}')
    run bash -c "printf '%s' '$json' | BRANCH_INTEGRATION_GUARD_CONF=/dev/null bash '$GUARD'"
    [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "STRUCT SessionStart event => silent pass" {
    json=$(jq -nc '{hook_event_name:"SessionStart", tool_name:"Bash", tool_input:{command:"git merge dev"}, cwd:"'"$REPO"'"}')
    run bash -c "printf '%s' '$json' | BRANCH_INTEGRATION_GUARD_CONF=/dev/null bash '$GUARD'"
    [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "CONF widening: qa added => git merge qa HEAD=main denies" {
    conf="$BATS_TEST_TMPDIR/gi.conf"
    printf 'integration_branches=dev develop qa\nprotected_targets=main master\n' > "$conf"
    git -C "$REPO" branch qa 2>/dev/null || true
    checkout main
    json=$(jq -nc --arg cwd "$REPO" '{hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:"git merge qa"}, cwd:$cwd}')
    run bash -c "printf '%s' '$json' | BRANCH_INTEGRATION_GUARD_CONF='$conf' bash '$GUARD'"
    [[ "$output" == *'"deny"'* ]]
}
