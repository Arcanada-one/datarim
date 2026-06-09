#!/usr/bin/env bash
# lib/jsonl.sh — JSONL helpers for the fleet skill-evolution loop.
#
# Sourced by adapters and the evolution loop. Depends on `jq` for validation;
# callers that need a hard dependency check should call jsonl_require_jq first.
#
# Functions:
#   jsonl_require_jq                 — exit 3 with a message if jq is absent
#   jsonl_emit_record <ti> <eo> <ao> <outcome> <source>
#                                    — print one schema-valid JSONL line
#   jsonl_validate <file>            — exit 0 if every line matches the contract
#   jsonl_merge <file>...            — cat + dedup by (task_input,source) to stdout

set -o pipefail

# Required record fields (contract: source-adapter-contract.md).
JSONL_REQUIRED_FIELDS=(task_input expected_output actual_output outcome source)

jsonl_require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "jsonl: jq not found on PATH (required for JSONL validation)" >&2
        return 3
    fi
}

# Emit a single contract-valid JSONL record. jq builds the JSON so arbitrary
# string content (newlines, quotes) is escaped correctly — never hand-format.
jsonl_emit_record() {
    local task_input=$1 expected_output=$2 actual_output=$3 outcome=$4 source=$5
    jq -cn \
        --arg ti "$task_input" \
        --arg eo "$expected_output" \
        --arg ao "$actual_output" \
        --arg oc "$outcome" \
        --arg src "$source" \
        '{task_input:$ti, expected_output:$eo, actual_output:$ao, outcome:$oc, source:$src}'
}

# Validate that every non-empty line is a JSON object carrying all required
# fields and an outcome in the allowed set. Empty file = valid (exit 0).
jsonl_validate() {
    local file=$1
    [ -f "$file" ] || { echo "jsonl: file not found: $file" >&2; return 1; }
    jsonl_require_jq || return 3

    local lineno=0 line
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        [ -z "$line" ] && continue
        if ! printf '%s' "$line" | jq -e 'type == "object"' >/dev/null 2>&1; then
            echo "jsonl: line $lineno is not a JSON object" >&2
            return 1
        fi
        local field
        for field in "${JSONL_REQUIRED_FIELDS[@]}"; do
            if ! printf '%s' "$line" | jq -e --arg f "$field" 'has($f)' >/dev/null 2>&1; then
                echo "jsonl: line $lineno missing field '$field'" >&2
                return 1
            fi
        done
        if ! printf '%s' "$line" | jq -e '.outcome=="success" or .outcome=="failure"' >/dev/null 2>&1; then
            echo "jsonl: line $lineno has invalid outcome (want success|failure)" >&2
            return 1
        fi
    done < "$file"
    return 0
}

# Merge several JSONL files, keeping the first record per (task_input,source).
jsonl_merge() {
    jsonl_require_jq || return 3
    cat "$@" 2>/dev/null \
        | jq -c 'select(length > 0)' 2>/dev/null \
        | jq -s -c 'unique_by([.task_input, .source]) | .[]'
}
