#!/usr/bin/env bats

HOOK="${HOOK:-${BATS_TEST_DIRNAME}/../dev-tools/coworker-hook-guard.sh}"

setup() {
    [ -x "$HOOK" ] || skip "coworker-hook-guard not executable at $HOOK"
    command -v jq >/dev/null || skip "jq required"
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim" "$TMPROOT/bin"
    printf '# Enabled Plugins\n\n## Active\n' > "$TMPROOT/datarim/enabled-plugins.md"
    printf 'BACKLOG ORIGINAL\n' > "$TMPROOT/datarim/backlog.md"
    printf '# Plan\n' > "$TMPROOT/large.md"
    head -c 60000 < /dev/zero | tr '\0' a >> "$TMPROOT/large.md"
}

teardown() {
    rm -rf "$TMPROOT"
}

disable_delegation() {
    cat >> "$TMPROOT/datarim/enabled-plugins.md" <<'EOF'

## Disabled Defaults

- coworker-delegation
EOF
}

run_hook() {
    local tool="$1" input_key="$2" input_value="$3"
    local payload
    payload="$(jq -nc --arg tool "$tool" --arg cwd "$TMPROOT" \
        --arg key "$input_key" --arg value "$input_value" \
        '{hook_event_name:"PreToolUse",tool_name:$tool,cwd:$cwd,tool_input:{($key):$value}}')"
    printf '%s' "$payload" | "$HOOK"
}

decision_of() {
    printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

@test "enabled state denies delegation-worthy Read" {
    run run_hook Read file_path "$TMPROOT/large.md"
    [ "$status" -eq 0 ] && [ "$(decision_of "$output")" = "deny" ]
}

@test "disabled state permits delegation-worthy Read" {
    disable_delegation
    run run_hook Read file_path "$TMPROOT/large.md"
    [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "disabled state permits protected first-draft Write" {
    disable_delegation
    run run_hook Write file_path "$TMPROOT/prd-tune-9999.md"
    [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "disabled state permits protected first-draft apply_patch" {
    disable_delegation
    run run_hook apply_patch input $'*** Begin Patch\n*** Add File: prd-tune-9999.md\n+x\n*** End Patch'
    [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "disabled state permits bulk git diff" {
    disable_delegation
    run run_hook Bash command "git diff"
    [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "malformed disabled-default state retains Read denial" {
    cat >> "$TMPROOT/datarim/enabled-plugins.md" <<'EOF'

## Disabled Defaults

  - coworker-delegation
EOF
    run run_hook Read file_path "$TMPROOT/large.md"
    [ "$status" -eq 0 ] && [ "$(decision_of "$output")" = "deny" ]
}

@test "disabled state preserves critical KB pre-overwrite backup" {
    disable_delegation
    run run_hook Write file_path "$TMPROOT/datarim/backlog.md"
    local count
    count="$(find "$TMPROOT/datarim/.backups" -name 'backlog.md.*.bak' 2>/dev/null | wc -l | tr -d ' ')"
    [ "$status" -eq 0 ] && [ -z "$output" ] && [ "$count" = "1" ]
}

@test "disabled state preserves critical KB backup for Bash redirection" {
    disable_delegation
    run run_hook Bash command "printf changed > $TMPROOT/datarim/backlog.md"
    local count
    count="$(find "$TMPROOT/datarim/.backups" -name 'backlog.md.*.bak' 2>/dev/null | wc -l | tr -d ' ')"
    [ "$status" -eq 0 ] && [ -z "$output" ] && [ "$count" = "1" ]
}

@test "disabled state preserves explicit branch start-point gate" {
    disable_delegation
    run run_hook Bash command "git checkout -b unsafe-branch"
    [ "$status" -eq 0 ] && [ "$(decision_of "$output")" = "deny" ]
}

@test "enabled SessionStart performs the configured provider balance probe" {
    cat > "$TMPROOT/bin/curl" <<EOF
#!/usr/bin/env bash
touch "$TMPROOT/curl-called"
printf '%s' '{"data":{"available_balance":0.5}}'
EOF
    chmod +x "$TMPROOT/bin/curl"
    local payload
    payload="$(jq -nc --arg cwd "$TMPROOT" '{hook_event_name:"SessionStart",cwd:$cwd}')"
    run bash -c 'printf "%s" "$1" | env -u XDG_CONFIG_HOME HOME="$2/home" PATH="$2/bin:$PATH" COWORKER_DEFAULT_PROVIDER=moonshot MOONSHOT_API_KEY=test "$3"' \
        _ "$payload" "$TMPROOT" "$HOOK"
    [ "$status" -eq 0 ] && [ -e "$TMPROOT/curl-called" ]
}

@test "disabled SessionStart skips the configured provider balance probe" {
    disable_delegation
    cat > "$TMPROOT/bin/curl" <<EOF
#!/usr/bin/env bash
touch "$TMPROOT/curl-called"
printf '%s' '{"data":{"available_balance":0.5}}'
EOF
    chmod +x "$TMPROOT/bin/curl"
    local payload
    payload="$(jq -nc --arg cwd "$TMPROOT" '{hook_event_name:"SessionStart",cwd:$cwd}')"
    run bash -c 'printf "%s" "$1" | env -u XDG_CONFIG_HOME HOME="$2/home" PATH="$2/bin:$PATH" COWORKER_DEFAULT_PROVIDER=moonshot MOONSHOT_API_KEY=test "$3"' \
        _ "$payload" "$TMPROOT" "$HOOK"
    [ "$status" -eq 0 ] && [ -z "$output" ] && [ ! -e "$TMPROOT/curl-called" ]
}
