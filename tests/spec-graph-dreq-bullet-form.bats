#!/usr/bin/env bats
# spec-graph-dreq-bullet-form.bats — DEV-1547 / DEV-1552-FU
#
# The /dr-prd template's Requirements section emits D-REQs as a bold bullet
# list (`- **D-REQ-NN** — …`), not `#### D-REQ-NN` headings. The spec-graph
# resolution layer originally recognised only the heading form, so a perfectly
# well-formed PRD that declared its D-REQs as a bullet list produced a false
# grade-F (dreq-dangling / Covers resolution firing against zero declared ids).
#
# These tests pin the relaxed schema constants against the sourced library, not
# inline literals, so a future drift in the regex is caught by the same source
# of truth the validator uses.

SCHEMA_REGEX_LIB="$BATS_TEST_DIRNAME/../scripts/lib/schema-regex.sh"
SPEC_GRAPH_LIB="$BATS_TEST_DIRNAME/../scripts/lib/spec-graph.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    # shellcheck source=../scripts/lib/schema-regex.sh
    . "$SCHEMA_REGEX_LIB"
}

teardown() {
    rm -rf "$TMPROOT"
}

# --- D_REQ_ID_RE: both canonical declaration forms ---------------------------

@test "D_REQ_ID_RE matches the heading form (#### D-REQ-NN: desc)" {
    run bash -c '. "'"$SCHEMA_REGEX_LIB"'"; printf "%s" "#### D-REQ-01: do the thing" | grep -qE "$D_REQ_ID_RE"'
    [ "$status" -eq 0 ]
}

@test "D_REQ_ID_RE matches the bold-bullet form (- **D-REQ-NN** — desc)" {
    run bash -c '. "'"$SCHEMA_REGEX_LIB"'"; printf "%s" "- **D-REQ-02** — bullet form declaration" | grep -qE "$D_REQ_ID_RE"'
    [ "$status" -eq 0 ]
}

@test "D_REQ_ID_RE matches an indented bold-bullet declaration" {
    run bash -c '. "'"$SCHEMA_REGEX_LIB"'"; printf "%s" "  - **D-REQ-03** — indented bullet" | grep -qE "$D_REQ_ID_RE"'
    [ "$status" -eq 0 ]
}

@test "D_REQ_ID_RE does NOT match a bare in-prose reference" {
    run bash -c '. "'"$SCHEMA_REGEX_LIB"'"; printf "%s" "see D-REQ-04 elsewhere in the text" | grep -qE "$D_REQ_ID_RE"'
    [ "$status" -ne 0 ]
}

# --- COVERS_LINE_RE / VERIFIES_LINE_RE: inline tolerance ---------------------

@test "COVERS_LINE_RE tolerates leading bullet text before Covers:" {
    run bash -c '. "'"$SCHEMA_REGEX_LIB"'"; printf "%s" "- some V-AC text Covers: D-REQ-01, D-REQ-02" | grep -qE "$COVERS_LINE_RE"'
    [ "$status" -eq 0 ]
}

@test "VERIFIES_LINE_RE tolerates inline italic at the end of a numbered step" {
    run bash -c '. "'"$SCHEMA_REGEX_LIB"'"; printf "%s" "5. Implement X. *Verifies: V-AC-1, V-AC-4*" | grep -qE "$VERIFIES_LINE_RE"'
    [ "$status" -eq 0 ]
}

# --- collect_d_req: end-to-end on a bullet-list PRD --------------------------

@test "collect_d_req extracts ids from a bullet-list Requirements section" {
    PRD="$TMPROOT/PRD-sample.md"
    {
        printf '## Requirements\n\n'
        printf -- '- **D-REQ-01** — first requirement\n'
        printf -- '- **D-REQ-02** — second requirement\n'
    } > "$PRD"
    run bash -c '. "'"$SCHEMA_REGEX_LIB"'"; . "'"$SPEC_GRAPH_LIB"'"; collect_d_req "'"$PRD"'"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"D-REQ-01"* ]]
    [[ "$output" == *"D-REQ-02"* ]]
}
