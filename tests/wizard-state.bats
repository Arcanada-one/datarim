#!/usr/bin/env bats
# wizard-state.bats — unit matrix for the interactive task-spec wizard state
# engine (TUNE-0390). Each test sources dev-tools/lib/wizard-state.sh in a
# throwaway KB root and asserts the append-only JSONL event-log contract:
# projection (resumable), drill push/pop context-capture (references, no
# session_id), re-scope dirty flags, finalize/abandon semantics, the S1/S5/S9
# security gates, and the `validate` integrity op. V-AC ids bind to
# prd/PRD-TUNE-0390.md § Success Criteria.

setup() {
    LIB="${BATS_TEST_DIRNAME}/../dev-tools/lib/wizard-state.sh"
    KB="$(mktemp -d)"
    ID="DEMO-0001"
}

teardown() { rm -rf "$KB"; }

wfile() { printf '%s/datarim/wizard/%s.wizard.jsonl' "$KB" "$ID"; }
gfile() { printf '%s/datarim/wizard/%s.graph.jsonl'  "$KB" "$ID"; }

json_ok() {  # every line of $1 is valid JSON
    python3 -c 'import json,sys
[json.loads(l) for l in open(sys.argv[1]) if l.strip()]' "$1"
}

# ---- V-AC-1 · state engine + projection ----

@test "V-AC-1a: init writes a meta line (kind meta, seq 0), valid JSONL" {
    run bash -c "source '$LIB'; wizard_init '$ID' --root '$KB'"
    [ "$status" -eq 0 ]
    [ -f "$(wfile)" ]
    grep -q '"kind":"meta"' "$(wfile)"
    grep -q '"seq":0' "$(wfile)"
    json_ok "$(wfile)"
}

@test "V-AC-1b: add_question + answer + status reports counts" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    wizard_add_question "$ID" q1 goal 'What is the goal?' --root "$KB"
    wizard_answer "$ID" q1 'Ship the wizard' --root "$KB"
    run bash -c "source '$LIB'; wizard_status '$ID' --root '$KB'"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q 'questions=1'
    echo "$output" | grep -q 'answered=1'
    echo "$output" | grep -q 'status=active'
}

@test "V-AC-1c: same qid answered twice — projection returns the latest" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    wizard_add_question "$ID" q1 goal 'g?' --root "$KB"
    wizard_add_question "$ID" q1 goal 'g?' --root "$KB"
    wizard_answer "$ID" q1 'first' --root "$KB"
    wizard_answer "$ID" q1 'second' --root "$KB"
    # idempotent question projection: one distinct qid
    run bash -c "source '$LIB'; wizard_status '$ID' --root '$KB'"
    echo "$output" | grep -q 'questions=1'
    # latest answer wins
    run bash -c "source '$LIB'; wizard_get_answer '$ID' q1 --root '$KB'"
    [ "$output" = 'second' ]
}

@test "V-AC-1d: finalize flips status to finalized" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    wizard_finalize "$ID" --root "$KB"
    run bash -c "source '$LIB'; wizard_status '$ID' --root '$KB'"
    echo "$output" | grep -q 'status=finalized'
}

# ---- V-AC-2 · drill side-thread, references not copies ----

@test "V-AC-2a: drill_push raises drill_depth to 1" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    wizard_add_question "$ID" q1 goal 'hard?' --root "$KB"
    wizard_drill_push "$ID" q1 q1 --root "$KB"
    run bash -c "source '$LIB'; wizard_status '$ID' --root '$KB'"
    echo "$output" | grep -q 'drill_depth=1'
}

@test "V-AC-2b: drill_pop lowers depth and writes the conclusion back to the parent qid" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    wizard_add_question "$ID" q1 goal 'hard?' --root "$KB"
    wizard_drill_push "$ID" q1 q1 --root "$KB"
    wizard_drill_pop "$ID" 'use append-only JSONL' --root "$KB"
    run bash -c "source '$LIB'; wizard_status '$ID' --root '$KB'"
    echo "$output" | grep -q 'drill_depth=0'
    run bash -c "source '$LIB'; wizard_get_answer '$ID' q1 --root '$KB'"
    [ "$output" = 'use append-only JSONL' ]
}

@test "V-AC-2c: drill_push stores refs (qid references), not a copy of the answer text" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    wizard_add_question "$ID" q1 goal 'hard?' --root "$KB"
    wizard_answer "$ID" q1 'SECRETCONTEXTBODY' --root "$KB"
    wizard_drill_push "$ID" q1 q1 --root "$KB"
    push_line=$(grep '"kind":"drill_push"' "$(wfile)")
    echo "$push_line" | grep -q '"refs"'
    # Robust negative: [[ ]] fails the bats test properly ('! grep' is set -e exempt).
    [[ "$push_line" != *SECRETCONTEXTBODY* ]]
}

# ---- V-AC-3 · re-scope dirty flags ----

@test "V-AC-3: rescope sets research_dirty=on with a note; later event does not clear it" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    wizard_rescope "$ID" research 'added new external API dep' --root "$KB"
    wizard_add_question "$ID" q9 scope 'anything else?' --root "$KB"
    run bash -c "source '$LIB'; wizard_flags '$ID' --root '$KB'"
    echo "$output" | grep -q 'research_dirty=on'
    grep '"kind":"flag"' "$(wfile)" | grep -q 'added new external API dep'
}

# ---- V-AC-4 · graph emission ----

@test "V-AC-4: graph_node + graph_edge produce valid JSONL and the edge references a node" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    wizard_graph_node "$ID" n_goal requirement 'ship wizard' --root "$KB"
    wizard_graph_node "$ID" n_dep concept 'JSONL log' --root "$KB"
    wizard_graph_edge "$ID" n_goal n_dep dependency --root "$KB"
    [ -f "$(gfile)" ]
    json_ok "$(gfile)"
    grep '"kind":"edge"' "$(gfile)" | grep -q '"from":"n_goal"'
    grep '"kind":"edge"' "$(gfile)" | grep -q '"to":"n_dep"'
    run bash -c "source '$LIB'; wizard_validate '$ID' --root '$KB'"
    [ "$status" -eq 0 ]
}

# ---- V-AC-5 · security matrix (S9 injection / S5 path / S1 redaction) ----

@test "V-AC-5a: embedded newline in an answer is rejected, no forged line" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    before=$(wc -l < "$(wfile)")
    run bash -c "source '$LIB'; wizard_answer '$ID' q1 \$'line1\nINJECTED' --root '$KB'"
    [ "$status" -ne 0 ]
    after=$(wc -l < "$(wfile)")
    [ "$before" -eq "$after" ]
    run grep -qF 'INJECTED' "$(wfile)"; [ "$status" -ne 0 ]
}

@test "V-AC-5b: control byte in an answer is rejected" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    run bash -c "source '$LIB'; wizard_answer '$ID' q1 \$'bad\x07bell' --root '$KB'"
    [ "$status" -ne 0 ]
}

@test "V-AC-5c: quote+backslash in text is escaped to one valid-JSON line and round-trips" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    val='a"b\c'
    wizard_add_question "$ID" q1 goal "$val" --root "$KB"
    [ "$(grep -c '"kind":"question"' "$(wfile)")" -eq 1 ]
    json_ok "$(wfile)"
    got=$(python3 -c 'import json,sys
for l in open(sys.argv[1]):
    o=json.loads(l)
    if o.get("kind")=="question": print(o["text"])' "$(wfile)")
    [ "$got" = 'a"b\c' ]
}

@test "V-AC-5d: bad qid (dot-dot / slash) is rejected" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    run bash -c "source '$LIB'; wizard_add_question '$ID' 'q..1' goal 'x' --root '$KB'"
    [ "$status" -ne 0 ]
    run bash -c "source '$LIB'; wizard_add_question '$ID' 'q/x' goal 'x' --root '$KB'"
    [ "$status" -ne 0 ]
}

@test "V-AC-5e: unknown graph relation is rejected" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    wizard_graph_node "$ID" a concept 'a' --root "$KB"
    wizard_graph_node "$ID" b concept 'b' --root "$KB"
    run bash -c "source '$LIB'; wizard_graph_edge '$ID' a b owns --root '$KB'"
    [ "$status" -ne 0 ]
}

@test "V-AC-5f: traversal TASK-ID is rejected, nothing written outside root" {
    run bash -c "source '$LIB'; wizard_init '../../etc/x' --root '$KB'"
    [ "$status" -ne 0 ]
    [ ! -e "$KB/../etc/x.wizard.jsonl" ]
}

@test "V-AC-5g: a symlink target is refused" {
    mkdir -p "$KB/datarim/wizard"
    ln -s /etc/hosts "$(wfile)"
    run bash -c "source '$LIB'; wizard_init '$ID' --root '$KB'"
    [ "$status" -ne 0 ]
}

@test "V-AC-5h: a graph label carrying a secret is redacted before write" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    wizard_graph_node "$ID" n1 decision 'token is sk-ABC123DEF456GHI789 keep it' --root "$KB"
    run grep -qF 'sk-ABC123DEF456GHI789' "$(gfile)"; [ "$status" -ne 0 ]
    grep -q 'REDACTED' "$(gfile)"
}

@test "V-AC-5i: a full home path (incl. trailing filename) is redacted in a graph label" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    wizard_graph_node "$ID" n1 decision 'config at /home/dev/api-keys.txt loaded' --root "$KB"
    run grep -qF 'api-keys.txt' "$(gfile)"; [ "$status" -ne 0 ]
    run grep -qF '/home/dev' "$(gfile)"; [ "$status" -ne 0 ]
    grep -q 'REDACTED' "$(gfile)"
}

@test "V-AC-5j: too-few args under set -u is a clean reject, not an unbound-variable crash" {
    run bash -c "set -u; source '$LIB'; wizard_add_question '$ID' q1 --root '$KB'"
    [ "$status" -eq 2 ]
    ! echo "$output" | grep -q 'unbound variable'
}

# ---- V-AC-6 · validate integrity + finalize/abandon ----

@test "V-AC-6a: validate on a well-formed log exits 0" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    wizard_add_question "$ID" q1 goal 'g?' --root "$KB"
    wizard_answer "$ID" q1 'a' --root "$KB"
    run bash -c "source '$LIB'; wizard_validate '$ID' --root '$KB'"
    [ "$status" -eq 0 ]
}

@test "V-AC-6b: validate rejects an unbalanced drill (pop without push)" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    printf '%s\n' '{"v":1,"seq":1,"kind":"drill_pop","parent":"q1","status":"resolved"}' >> "$(wfile)"
    run bash -c "source '$LIB'; wizard_validate '$ID' --root '$KB'"
    [ "$status" -ne 0 ]
}

@test "V-AC-6c: validate rejects an unknown event kind" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    printf '%s\n' '{"v":1,"seq":1,"kind":"bogus","x":1}' >> "$(wfile)"
    run bash -c "source '$LIB'; wizard_validate '$ID' --root '$KB'"
    [ "$status" -ne 0 ]
}

@test "V-AC-6d: finalize with an open drill frame records an abandoned pop and reaches depth 0" {
    source "$LIB"
    wizard_init "$ID" --root "$KB"
    wizard_add_question "$ID" q1 goal 'hard?' --root "$KB"
    wizard_drill_push "$ID" q1 q1 --root "$KB"
    wizard_finalize "$ID" --root "$KB"
    grep '"kind":"drill_pop"' "$(wfile)" | grep -q '"status":"abandoned"'
    run bash -c "source '$LIB'; wizard_status '$ID' --root '$KB'"
    echo "$output" | grep -q 'drill_depth=0'
    run bash -c "source '$LIB'; wizard_validate '$ID' --root '$KB'"
    [ "$status" -eq 0 ]
}
