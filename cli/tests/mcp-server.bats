#!/usr/bin/env bats
# mcp-server.bats — TUNE-0301 JSON-RPC protocol surface.
# V-AC-1 (discovery), V-AC-2 (tools/list), V-AC-3/4 (command invocation),
# V-AC-7 (robustness).

setup() {
    SRV="$(cd "$BATS_TEST_DIRNAME/../mcp" && pwd)/datarim-mcp-server.sh"
    [[ -x "$SRV" ]] || skip "datarim-mcp-server.sh not yet implemented/executable"
}

# Feed one JSON-RPC line, capture the single response line.
rpc() { printf '%s\n' "$1" | "$SRV"; }

@test "1: initialize echoes protocolVersion, tools-only caps, serverInfo.name=datarim" {
    run rpc '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{}}}'
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.result.protocolVersion=="2025-06-18"' >/dev/null
    echo "$output" | jq -e '.result.capabilities|has("tools")' >/dev/null
    echo "$output" | jq -e '.result.capabilities|(has("prompts")|not) and (has("resources")|not)' >/dev/null
    echo "$output" | jq -e '.result.serverInfo.name=="datarim"' >/dev/null
    echo "$output" | jq -e '.id==0' >/dev/null   # numeric id preserved
}

@test "2: initialize falls back to 2025-06-18 when client omits protocolVersion" {
    run rpc '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
    echo "$output" | jq -e '.result.protocolVersion=="2025-06-18"' >/dev/null
}

@test "3: tools/list returns >=6 datarim_* tools with object inputSchema + description" {
    run rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
    echo "$output" | jq -e '.result.tools|length>=6' >/dev/null
    echo "$output" | jq -e '.result.tools|all(.name|startswith("datarim_"))' >/dev/null
    echo "$output" | jq -e '.result.tools|all(.inputSchema.type=="object")' >/dev/null
    echo "$output" | jq -e '.result.tools|all(.description|length>0)' >/dev/null
}

@test "4: datarim_list_commands returns full command catalogue" {
    run rpc '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"datarim_list_commands"}}'
    echo "$output" | jq -e '.result.isError==false' >/dev/null
    n="$(echo "$output" | jq -r '.result.content[0].text|fromjson|length')"
    [ "$n" -ge 20 ]
    echo "$output" | jq -e '.result.content[0].text|fromjson|any(.name=="dr-status")' >/dev/null
}

@test "5: datarim_run_command returns the command body (invocation via MCP)" {
    run rpc '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"datarim_run_command","arguments":{"name":"dr-status"}}}'
    echo "$output" | jq -e '.result.isError==false' >/dev/null
    echo "$output" | jq -e '.result.content[0].text|contains("dr-status")' >/dev/null
}

@test "6: get_skill + get_agent return bodies" {
    run rpc '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"datarim_get_skill","arguments":{"name":"brainstorming"}}}'
    echo "$output" | jq -e '.result.content[0].text|length>0 and (.|ascii_downcase|contains("brainstorm"))' >/dev/null
    run rpc '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"datarim_get_agent","arguments":{"name":"architect"}}}'
    echo "$output" | jq -e '.result.content[0].text|length>0' >/dev/null
}

@test "7: valid tool + unknown target -> isError result, no path leak" {
    run rpc '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"datarim_run_command","arguments":{"name":"dr-nope"}}}'
    echo "$output" | jq -e '.result.isError==true' >/dev/null
    echo "$output" | jq -e '.result.content[0].text|(contains("/home")|not) and (contains("/etc")|not)' >/dev/null
}

@test "8: unknown tool name -> -32602 (not -32601)" {
    run rpc '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"bogus"}}'
    echo "$output" | jq -e '.error.code==-32602' >/dev/null
}

@test "9: missing required arg -> -32602" {
    run rpc '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"datarim_run_command","arguments":{}}}'
    echo "$output" | jq -e '.error.code==-32602' >/dev/null
}

@test "10: traversal name via tool -> isError, never resolves outside tree" {
    run rpc '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"datarim_get_skill","arguments":{"name":"../../../etc/passwd"}}}'
    echo "$output" | jq -e '.result.isError==true' >/dev/null
    echo "$output" | jq -e '.result.content[0].text|contains("root:")|not' >/dev/null
}

@test "11: unknown method -> -32601" {
    run rpc '{"jsonrpc":"2.0","id":11,"method":"foo/bar"}'
    echo "$output" | jq -e '.error.code==-32601' >/dev/null
}

@test "12: notification (no id) -> no response line" {
    run rpc '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    [ -z "$output" ]
}

@test "13: ping -> empty result" {
    run rpc '{"jsonrpc":"2.0","id":13,"method":"ping"}'
    echo "$output" | jq -e '.result=={} and .id==13' >/dev/null
}

@test "14: malformed line -> -32700 and loop survives the next request" {
    run bash -c "printf '%s\n%s\n' 'not json{{{' '{\"jsonrpc\":\"2.0\",\"id\":14,\"method\":\"ping\"}' | '$SRV'"
    [ "$status" -eq 0 ]
    echo "$output" | head -1 | jq -e '.error.code==-32700' >/dev/null
    echo "$output" | tail -1 | jq -e '.id==14 and .result=={}' >/dev/null
}

@test "15: batch array -> single -32600 error, not a crash" {
    run rpc '[{"jsonrpc":"2.0","id":1,"method":"ping"}]'
    echo "$output" | jq -e '.error.code==-32600' >/dev/null
}

@test "16: string id preserved as string" {
    run rpc '{"jsonrpc":"2.0","id":"abc","method":"ping"}'
    echo "$output" | jq -e '.id=="abc"' >/dev/null
}

@test "17: stdout carries ONLY JSON-RPC (every line parses)" {
    run bash -c "printf '%s\n%s\n%s\n' \
        '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}' \
        '{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}' \
        '{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"datarim_run_command\",\"arguments\":{\"name\":\"dr-plan\"}}}' \
        | '$SRV'"
    [ "$status" -eq 0 ]
    while IFS= read -r l; do [ -z "$l" ] && continue; echo "$l" | jq -e . >/dev/null || { echo "non-JSON line: $l"; false; }; done <<< "$output"
}

@test "18: server refuses to start on a bad DATARIM_ROOT" {
    run bash -c "DATARIM_ROOT='$BATS_TEST_TMPDIR' '$SRV' < /dev/null"
    [ "$status" -ne 0 ]
}
