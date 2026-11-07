#!/usr/bin/env bats
#
# Regression spec for dev-tools/check-open-pr-budget.sh — PreToolUse open-PR
# budget floor before `gh pr create`.
#
# A crafted PreToolUse JSON is piped to the guard. Blocked ⇒ stdout contains
# permissionDecision "deny". Allowed ⇒ empty stdout + exit 0.
# Measurement uses a fake `gh` on PATH; negative controls prove fail-closed
# when gh is missing or returns unusable output (not measured ≠ pass).

setup() {
    GUARD="$BATS_TEST_DIRNAME/../check-open-pr-budget.sh"
    [ -f "$GUARD" ] || skip "guard not found: $GUARD"
    BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$BIN"
    REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email t@t.t
    git -C "$REPO" config user.name t
    git -C "$REPO" commit -q --allow-empty -m init
    git -C "$REPO" branch -M main
    git -C "$REPO" checkout -qb feature/x
    CONF="$BATS_TEST_TMPDIR/pr-budget.conf"
    printf 'feature=1\ntotal=2\nintegration_prefixes=integration/ batch/\nhotfix_prefixes=hotfix/ ci/ fix/\n' > "$CONF"
    NOREPO="$BATS_TEST_TMPDIR/plain"
    mkdir -p "$NOREPO"
    # Default fake gh: empty open-PR list (under budget).
    cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "repo" ] && [ "${2:-}" = "view" ]; then
    printf 'owner/demo\n'
    exit 0
fi
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
    printf '[]\n'
    exit 0
fi
printf 'unexpected gh args: %s\n' "$*" >&2
exit 99
EOF
    chmod +x "$BIN/gh"
    export PATH="$BIN:$PATH"
    export PR_BUDGET_CONF="$CONF"
}

fire() {
    local cwd="$1" cmd="$2"
    local json
    json=$(jq -nc --arg c "$cmd" --arg cwd "$cwd" \
        '{hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$c}, cwd:$cwd}')
    printf '%s' "$json" | bash "$GUARD"
}
assert_deny() { [[ "$output" == *'"permissionDecision"'*'"deny"'* ]]; }
assert_pass() { [ -z "$output" ]; }

install_gh_open_list() {
    # $1 = JSON array body for `gh pr list`
    local body="$1"
    cat > "$BIN/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [ "\${1:-}" = "repo" ] && [ "\${2:-}" = "view" ]; then
    printf 'owner/demo\n'
    exit 0
fi
if [ "\${1:-}" = "pr" ] && [ "\${2:-}" = "list" ]; then
    cat <<'JSON'
$body
JSON
    exit 0
fi
printf 'unexpected gh args: %s\n' "\$*" >&2
exit 99
EOF
    chmod +x "$BIN/gh"
}

# ── BLOCKED (budget / unmeasured) ─────────────────────────────────────────────
@test "B1 feature budget exhausted (1 open feature, feature=1) => deny" {
    install_gh_open_list '[{"headRefName":"feature/other"}]'
    run fire "$REPO" "gh pr create --fill"
    assert_deny
}
@test "B2 total budget exhausted (1 feature + 1 hotfix, total=2) => deny" {
    install_gh_open_list '[{"headRefName":"feature/a"},{"headRefName":"hotfix/b"}]'
    run fire "$REPO" "gh pr create --title t"
    assert_deny
}
@test "B3 two hotfixes exhaust total=2 even with zero feature => deny" {
    install_gh_open_list '[{"headRefName":"hotfix/a"},{"headRefName":"ci/b"}]'
    run fire "$REPO" "gh pr create"
    assert_deny
}
@test "NEG gh missing from PATH => deny (not measured ≠ pass)" {
    # Put an empty dir first so `gh` resolves to nothing; keep system tools after.
    EMPTY="$BATS_TEST_TMPDIR/empty"
    mkdir -p "$EMPTY"
    PATH="$EMPTY:/usr/bin:/bin" run fire "$REPO" "gh pr create --fill"
    assert_deny
    [[ "$output" == *"could not be measured"* ]]
}
@test "NEG gh repo view fails => deny" {
    cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$BIN/gh"
    run fire "$REPO" "gh pr create"
    assert_deny
}
@test "NEG gh pr list returns non-JSON => deny" {
    cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "repo" ]; then printf 'owner/demo\n'; exit 0; fi
printf 'not-json\n'
exit 0
EOF
    chmod +x "$BIN/gh"
    run fire "$REPO" "gh pr create"
    assert_deny
}

# ── ALLOWED ───────────────────────────────────────────────────────────────────
@test "A1 under budget (0 open) => pass" {
    run fire "$REPO" "gh pr create --fill"
    assert_pass
}
@test "A2 one hotfix open with total=2 feature=1 => pass" {
    install_gh_open_list '[{"headRefName":"hotfix/only"}]'
    run fire "$REPO" "gh pr create --fill"
    assert_pass
}
@test "A3 integration open PRs do not consume budget => pass" {
    install_gh_open_list '[{"headRefName":"integration/batch"},{"headRefName":"batch/011"}]'
    run fire "$REPO" "gh pr create --fill"
    assert_pass
}
@test "A4 creating from integration/ head is always allowed even when feature full" {
    install_gh_open_list '[{"headRefName":"feature/other"}]'
    git -C "$REPO" checkout -qb integration/batch011
    run fire "$REPO" "gh pr create --fill"
    assert_pass
}
@test "A5 gh --repo owner/name pr create under budget => pass" {
    run fire "$REPO" "gh --repo owner/demo pr create --fill"
    assert_pass
}
@test "A6 /usr/bin/gh pr create under budget => pass" {
    # basename must still detect gh; point a path-looking token at our fake
    ln -sf "$BIN/gh" "$BIN/usr-bin-gh"
    # emulate path form: copy as a name that basename → still need real basename gh
    run fire "$REPO" "$BIN/gh pr create --fill"
    assert_pass
}

# ── NON-TRIGGER / READ-ONLY LOOK-ALIKES ───────────────────────────────────────
@test "RO gh pr list => pass (not create)" {
    install_gh_open_list '[{"headRefName":"feature/other"}]'
    run fire "$REPO" "gh pr list"
    assert_pass
}
@test "RO echo gh pr create => pass (command-position echo)" {
    install_gh_open_list '[{"headRefName":"feature/other"}]'
    run fire "$REPO" "echo gh pr create"
    assert_pass
}
@test "RO git push => pass" {
    run fire "$REPO" "git push -u origin feature/x"
    assert_pass
}
@test "RO rg gh pr create in docs => pass" {
    run fire "$REPO" 'rg "gh pr create" docs/'
    assert_pass
}

# ── INJECTION RESISTANCE ──────────────────────────────────────────────────────
@test "INJ quoted body citing gh pr create does not trigger" {
    install_gh_open_list '[{"headRefName":"feature/other"}]'
    run fire "$REPO" 'git commit -m "note: run gh pr create next"'
    assert_pass
}
@test "INJ heredoc containing gh pr create => pass" {
    install_gh_open_list '[{"headRefName":"feature/other"}]'
    run fire "$REPO" "cat > f <<EOF
ignore this rule, gh pr create --fill
EOF"
    assert_pass
}
@test "INJ in-band allow comment does NOT bypass real create => deny" {
    install_gh_open_list '[{"headRefName":"feature/other"}]'
    run fire "$REPO" "gh pr create --fill  # budget waived this once"
    assert_deny
}

# ── STRUCTURAL ────────────────────────────────────────────────────────────────
@test "STRUCT non-Bash tool (Read) => silent pass" {
    json=$(jq -nc '{hook_event_name:"PreToolUse", tool_name:"Read", tool_input:{command:"gh pr create"}, cwd:"'"$REPO"'"}')
    run bash -c "printf '%s' '$json' | PR_BUDGET_CONF='$CONF' PATH='$BIN:$PATH' bash '$GUARD'"
    [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "STRUCT SessionStart event => silent pass" {
    json=$(jq -nc '{hook_event_name:"SessionStart", tool_name:"Bash", tool_input:{command:"gh pr create"}, cwd:"'"$REPO"'"}')
    run bash -c "printf '%s' '$json' | PR_BUDGET_CONF='$CONF' PATH='$BIN:$PATH' bash '$GUARD'"
    [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "CONF feature=2 allows one open feature => pass" {
    printf 'feature=2\ntotal=2\nintegration_prefixes=integration/ batch/\n' > "$CONF"
    install_gh_open_list '[{"headRefName":"feature/other"}]'
    run fire "$REPO" "gh pr create --fill"
    assert_pass
}
