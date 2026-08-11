#!/usr/bin/env bats
# mcp-install-register.bats — TUNE-0301 V-AC-8: idempotent, no-clobber
# registration of [mcp_servers.datarim] into ~/.codex/config.toml.

setup() {
    REG="$(cd "$BATS_TEST_DIRNAME/../mcp" && pwd)/register-codex-mcp.py"
    [[ -f "$REG" ]] || skip "register-codex-mcp.py not yet implemented"
    CFG="$BATS_TEST_TMPDIR/config.toml"
    CMD="/opt/datarim/cli/mcp/datarim-mcp-server.sh"
    ROOT="/opt/datarim"
    HAS_TOMLLIB=1
    python3 -c 'import tomllib' 2>/dev/null || HAS_TOMLLIB=0
}

reg() { python3 "$REG" --config "$CFG" --command "$CMD" --root "$ROOT"; }
toml_ok() { [ "$HAS_TOMLLIB" -eq 0 ] || python3 -c "import tomllib;tomllib.load(open('$CFG','rb'))"; }

@test "1: registers into a fresh (absent) config → valid TOML with datarim" {
    run reg; [ "$status" -eq 0 ]
    toml_ok
    grep -q '^\[mcp_servers.datarim\]$' "$CFG"
    grep -q "command = \"$CMD\"" "$CFG"
    grep -q 'env = { DATARIM_ROOT = "/opt/datarim" }' "$CFG"
}

@test "2: idempotent — second run is byte-identical" {
    reg; cp "$CFG" "$BATS_TEST_TMPDIR/first"
    reg
    diff "$BATS_TEST_TMPDIR/first" "$CFG"
}

@test "3: no-clobber — preserves other keys, tables, and sibling mcp_servers" {
    cat > "$CFG" <<'EOF'
model = "gpt-5.6-sol"

[projects."/home/dev/arcanada"]
trust_level = "trusted"

# keep this comment
[mcp_servers.openaiDeveloperDocs]
url = "https://developers.openai.com/mcp"
EOF
    run reg; [ "$status" -eq 0 ]
    toml_ok
    grep -q 'model = "gpt-5.6-sol"' "$CFG"
    grep -q '\[projects."/home/dev/arcanada"\]' "$CFG"
    grep -q '# keep this comment' "$CFG"
    grep -q '\[mcp_servers.openaiDeveloperDocs\]' "$CFG"
    grep -q '\[mcp_servers.datarim\]' "$CFG"
    # exactly one datarim table
    [ "$(grep -c '^\[mcp_servers.datarim\]$' "$CFG")" -eq 1 ]
}

@test "4: re-register with a changed root → replaced, not duplicated" {
    reg
    ROOT="/opt/datarim2" CMD="/opt/datarim2/cli/mcp/datarim-mcp-server.sh" \
        python3 "$REG" --config "$CFG" --command "/opt/datarim2/cli/mcp/datarim-mcp-server.sh" --root "/opt/datarim2"
    [ "$(grep -c '^\[mcp_servers.datarim\]$' "$CFG")" -eq 1 ]
    grep -q 'DATARIM_ROOT = "/opt/datarim2"' "$CFG"
    ! grep -q 'DATARIM_ROOT = "/opt/datarim"$' "$CFG"
    toml_ok
}

@test "5: migrates a legacy separate-subtable [mcp_servers.datarim.env] layout" {
    cat > "$CFG" <<'EOF'
model = "x"

[mcp_servers.datarim]
command = "/old/path.sh"
args = []

[mcp_servers.datarim.env]
DATARIM_ROOT = "/old"

[mcp_servers.other]
url = "https://x"
EOF
    run reg; [ "$status" -eq 0 ]
    toml_ok
    # no orphan subtable header remains
    ! grep -q '\[mcp_servers.datarim.env\]' "$CFG"
    [ "$(grep -c '^\[mcp_servers.datarim\]$' "$CFG")" -eq 1 ]
    grep -q '\[mcp_servers.other\]' "$CFG"
    grep -q 'DATARIM_ROOT = "/opt/datarim" }' "$CFG"
}

@test "6: refuses a malformed config (exit 3), leaves it untouched" {
    if [ "$HAS_TOMLLIB" -eq 0 ]; then skip "no tomllib"; fi
    printf '%s\n' 'this = = broken toml [[[' > "$CFG"
    cp "$CFG" "$BATS_TEST_TMPDIR/orig"
    run reg
    [ "$status" -eq 3 ]
    diff "$BATS_TEST_TMPDIR/orig" "$CFG"
}

@test "7: prefix false-match [mcp_servers.datarimX] is preserved" {
    cat > "$CFG" <<'EOF'
[mcp_servers.datarimX]
url = "https://keep-me"
EOF
    run reg; [ "$status" -eq 0 ]
    toml_ok
    grep -q '\[mcp_servers.datarimX\]' "$CFG"
    grep -q 'https://keep-me' "$CFG"
    grep -q '^\[mcp_servers.datarim\]$' "$CFG"
}
