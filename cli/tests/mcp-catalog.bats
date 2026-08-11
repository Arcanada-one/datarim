#!/usr/bin/env bats
# mcp-catalog.bats — TUNE-0301 enumeration + security (name→body resolution).
# V-AC-3/5/6 (parity), V-AC-7 (robustness), Appendix A (traversal/injection).

setup() {
    MCP_DIR="$(cd "$BATS_TEST_DIRNAME/../mcp" && pwd)"
    LIB="$MCP_DIR/lib/mcp-catalog.sh"
    [[ -f "$LIB" ]] || skip "lib/mcp-catalog.sh not yet implemented"
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"   # framework repo root
    # shellcheck source=/dev/null
    source "$LIB"
}

# --- name allowlist (P0 traversal) ----------------------------------------

@test "1: valid names accepted" {
    for n in dr-status brainstorming architect factcheck dr-init-id-collision-window; do
        run mcp_valid_name "$n"; [ "$status" -eq 0 ] || { echo "rejected $n"; false; }
    done
}

@test "2: traversal / injection names rejected" {
    for n in "../../etc/passwd" "/etc/passwd" ".." "a/b" "a..b" "*" "-rf" ".hidden" "" "UPPER" "na me"; do
        run mcp_valid_name "$n"
        [ "$status" -ne 0 ] || { echo "accepted bad name: [$n]"; false; }
    done
}

@test "3: over-length name (>64) rejected" {
    local long; long="$(printf 'a%.0s' {1..80})"
    run mcp_valid_name "$long"; [ "$status" -ne 0 ]
}

# --- root guard (P0 disclosure) -------------------------------------------

@test "4: guard accepts real framework root, echoes canonical path" {
    run mcp_guard_root "$ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == "$(realpath "$ROOT")" ]]
}

@test "5: guard refuses / and \$HOME and non-framework dir" {
    run mcp_guard_root "/"; [ "$status" -ne 0 ]
    run mcp_guard_root "$HOME"; [ "$status" -ne 0 ]
    run mcp_guard_root "$BATS_TEST_TMPDIR"; [ "$status" -ne 0 ]  # no commands/skills/agents
}

# --- enumeration parity (V-AC-3/5/6) --------------------------------------

@test "6: list commands parity with commands/*.md" {
    run mcp_list "$ROOT" commands
    [ "$status" -eq 0 ]
    local n_json n_fs
    n_json="$(echo "$output" | jq 'length')"
    n_fs="$(find "$ROOT/commands" -maxdepth 1 -name '*.md' -type f | wc -l | tr -d ' ')"
    [ "$n_json" -eq "$n_fs" ]
    echo "$output" | jq -e '.[] | select(.name=="dr-status")' >/dev/null
}

@test "7: list skills parity + has known skill" {
    run mcp_list "$ROOT" skills
    [ "$status" -eq 0 ]
    local n_json n_fs
    n_json="$(echo "$output" | jq 'length')"
    n_fs="$(find "$ROOT/skills" -maxdepth 2 -name 'SKILL.md' -type f | wc -l | tr -d ' ')"
    [ "$n_json" -eq "$n_fs" ]
    echo "$output" | jq -e '.[] | select(.name=="brainstorming")' >/dev/null
}

@test "8: list agents parity + has known agent" {
    run mcp_list "$ROOT" agents
    [ "$status" -eq 0 ]
    local n_json n_fs
    n_json="$(echo "$output" | jq 'length')"
    n_fs="$(find "$ROOT/agents" -maxdepth 1 -name '*.md' -type f | wc -l | tr -d ' ')"
    [ "$n_json" -eq "$n_fs" ]
    echo "$output" | jq -e '.[] | select(.name=="architect")' >/dev/null
}

@test "9: list entries carry non-empty descriptions" {
    run mcp_list "$ROOT" skills
    echo "$output" | jq -e 'all(.description | length > 0)' >/dev/null
}

# --- resolution + body (V-AC-4/5/6) ---------------------------------------

@test "10: resolve dr-status → confined path under commands/" {
    run mcp_resolve "$ROOT" commands dr-status
    [ "$status" -eq 0 ]
    [[ "$output" == "$(realpath "$ROOT/commands")"/dr-status.md ]]
}

@test "11: body returns command content" {
    run mcp_body "$ROOT" commands dr-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"dr-status"* ]]
}

@test "12: body for skill + agent" {
    run mcp_body "$ROOT" skills brainstorming; [ "$status" -eq 0 ]; [ -n "$output" ]
    run mcp_body "$ROOT" agents architect;    [ "$status" -eq 0 ]; [ -n "$output" ]
}

@test "13: unknown target rejected (generic)" {
    run mcp_body "$ROOT" commands dr-nonexistent; [ "$status" -ne 0 ]
    run mcp_resolve "$ROOT" commands dr-nonexistent; [ "$status" -ne 0 ]
}

@test "14: traversal name never resolves" {
    run mcp_resolve "$ROOT" commands "../../etc/passwd"; [ "$status" -ne 0 ]
    run mcp_resolve "$ROOT" skills "../../../etc/passwd"; [ "$status" -ne 0 ]
}

# --- symlink escape (P0) --------------------------------------------------

@test "15: in-tree symlink escaping the subdir is rejected" {
    # Build a throwaway framework-shaped root with a symlink escaping commands/.
    local troot="$BATS_TEST_TMPDIR/fw"
    mkdir -p "$troot/commands" "$troot/skills" "$troot/agents"
    echo "SECRET" > "$BATS_TEST_TMPDIR/secret.md"
    ln -s "$BATS_TEST_TMPDIR/secret.md" "$troot/commands/evil.md"
    run mcp_resolve "$troot" commands evil
    [ "$status" -ne 0 ]
    # And it must not appear in enumeration.
    run mcp_list "$troot" commands
    echo "$output" | jq -e 'all(.name != "evil")' >/dev/null
}

@test "17: list works under set -f (server sets noglob)" {
    run bash -c "set -f; source '$LIB'; mcp_list '$ROOT' commands | jq 'length'"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
}

@test "16: body is size-capped" {
    local troot="$BATS_TEST_TMPDIR/fw2"
    mkdir -p "$troot/commands" "$troot/skills" "$troot/agents"
    head -c 1000000 /dev/zero | tr '\0' 'x' > "$troot/commands/big.md"
    MCP_BODY_CAP=1024 run mcp_body "$troot" commands big
    [ "$status" -eq 0 ]
    [ "${#output}" -le 1024 ]
}
