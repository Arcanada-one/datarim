#!/usr/bin/env bash
#
# check-agent-frontmatter.sh — agent frontmatter runtime-agnosticism gate.
#
# Validates agent frontmatter under the runtime-agnostic agent schema
# (companion of check-skill-frontmatter.sh, per the orthogonal-tools rule):
#   REQUIRED  name, description
#   REQUIRED  model: inherit          (hardcoded model-generation names such
#                                      as vendor aliases or full model IDs
#                                      are a FAIL — capability intent belongs
#                                      in metadata.model_tier)
#   REQUIRED  metadata.model_tier     (must be one of the canonical tier
#                                      names declared under `tiers:` in
#                                      config/model-tiers.yaml)
#
# The allowed tier set is parsed from config/model-tiers.yaml at run time so
# this gate cannot drift from the canonical tier registry. A missing or
# unparsable registry is a FAIL (fail-closed).
#
# Scans agents/*.md at the given root.
#
# Usage: check-agent-frontmatter.sh [--root <repo-root>] [--summary-json]
# Exit 0 PASS, 1 FAIL, 2 usage error.

set -euo pipefail
IFS=$'\n\t'

ROOT=""
SUMMARY_JSON=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --summary-json) SUMMARY_JSON=1; shift ;;
        -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$ROOT" ]]; then
    ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

cd "$ROOT"

fail=0
checked=0

emit_summary() {
    local result="$1" exit_code="$2" diagnostic_codes="$3" checked_count="$4" count_status="$5"
    printf '{"schema":"DatarimAgentFrontmatterValidationSummary/v1","result":"%s","exit_code":%s,"diagnostic_codes":%s,"checked_count":%s,"checked_count_status":"%s"}\n' \
        "$result" "$exit_code" "$diagnostic_codes" "$checked_count" "$count_status"
}

# Canonical tier names come from config/model-tiers.yaml (`tiers:` map keys).
TIERS_FILE="config/model-tiers.yaml"
if [[ ! -f "$TIERS_FILE" ]]; then
    if [[ "$SUMMARY_JSON" -eq 1 ]]; then
        emit_summary FAIL 1 '["TIER_REGISTRY_UNAVAILABLE"]' null NOT_MEASURED
    else
        echo "FAIL: canonical tier registry missing: $TIERS_FILE"
    fi
    exit 1
fi
allowed_tiers="$(awk '
    /^tiers:/ { in_tiers = 1; next }
    in_tiers && /^[a-zA-Z_]/ { in_tiers = 0 }
    in_tiers && /^  [a-z_]+:[[:space:]]*$/ {
        key = $1
        sub(/:$/, "", key)
        print key
    }
' "$TIERS_FILE")"
if [[ -z "$allowed_tiers" ]]; then
    if [[ "$SUMMARY_JSON" -eq 1 ]]; then
        emit_summary FAIL 1 '["TIER_REGISTRY_UNAVAILABLE"]' null NOT_MEASURED
    else
        echo "FAIL: no tiers parsed from $TIERS_FILE (schema drift?)"
    fi
    exit 1
fi

tier_allowed() {
    local candidate="$1" t
    while IFS= read -r t; do
        [[ "$candidate" == "$t" ]] && return 0
    done <<< "$allowed_tiers"
    return 1
}

extract_fm() {
    awk '
        BEGIN { in_fm = 0; line_count = 0 }
        /^---$/ {
            if (line_count == 0) { in_fm = 1; line_count++; next }
            if (in_fm == 1) { exit }
        }
        in_fm == 1 { print }
    ' "$1"
}

# Extract scalar value for a top-level key. Strips trailing comments and quotes.
fm_top() {
    local fm="$1" key="$2"
    echo "$fm" | awk -v k="^$key:[[:space:]]*" '
        /^[a-zA-Z_]+:/ && $0 ~ k {
            sub(k, "")
            sub(/[[:space:]]*#.*$/, "")
            gsub(/^["'"'"']|["'"'"']$/, "")
            print
            exit
        }
    '
}

# Extract scalar value for a metadata.<key> field (1-level indent under
# metadata:). Returns empty if not present.
fm_metadata() {
    local fm="$1" key="$2"
    echo "$fm" | awk -v k="^[[:space:]]+$key:[[:space:]]*" '
        /^metadata:/ { in_md = 1; next }
        in_md && /^[a-zA-Z_]+:/ { in_md = 0 }
        in_md && $0 ~ k {
            sub(k, "")
            sub(/[[:space:]]*#.*$/, "")
            gsub(/^["'"'"']|["'"'"']$/, "")
            print
            exit
        }
    '
}

check_file() {
    local path="$1" label="$2"
    checked=$((checked + 1))

    local fm name desc model tier
    fm="$(extract_fm "$path")"

    name="$(fm_top "$fm" "name")"
    desc="$(fm_top "$fm" "description")"
    model="$(fm_top "$fm" "model")"
    tier="$(fm_metadata "$fm" "model_tier")"

    if [[ -z "$name" ]]; then
        if [[ "$SUMMARY_JSON" -eq 0 ]]; then echo "FAIL ($label): MISS name"; fi
        fail=1
    fi

    if [[ -z "$desc" ]]; then
        if [[ "$SUMMARY_JSON" -eq 0 ]]; then echo "FAIL ($label): MISS description"; fi
        fail=1
    fi

    if [[ -z "$model" ]]; then
        if [[ "$SUMMARY_JSON" -eq 0 ]]; then echo "FAIL ($label): MISS model — agents must declare 'model: inherit'"; fi
        fail=1
    elif [[ "$model" != "inherit" ]]; then
        if [[ "$SUMMARY_JSON" -eq 0 ]]; then echo "FAIL ($label): hardcoded model '$model' — agents must use 'model: inherit' (capability intent goes in metadata.model_tier)"; fi
        fail=1
    fi

    if [[ -z "$tier" ]]; then
        if [[ "$SUMMARY_JSON" -eq 0 ]]; then echo "FAIL ($label): MISS metadata.model_tier — required for runtime tier resolution"; fi
        fail=1
    elif ! tier_allowed "$tier"; then
        if [[ "$SUMMARY_JSON" -eq 0 ]]; then echo "FAIL ($label): invalid metadata.model_tier '$tier' — expected one of: $(echo "$allowed_tiers" | tr '\n' ' ')"; fi
        fail=1
    fi
}

shopt -s nullglob
found_any=0
for entry in agents/*.md; do
    [[ -f "$entry" ]] || continue
    found_any=1
    check_file "$entry" "$(basename "$entry")"
done

if [[ "$found_any" -eq 0 ]]; then
    if [[ "$SUMMARY_JSON" -eq 1 ]]; then
        emit_summary FAIL 1 '["NO_AGENT_FILES"]' "$checked" MEASURED
    else
        echo "FAIL: no agents/*.md found under $ROOT"
    fi
    exit 1
fi

if [[ "$SUMMARY_JSON" -eq 1 ]]; then
    if [[ $fail -eq 0 ]]; then
        emit_summary PASS 0 '[]' "$checked" MEASURED
        exit 0
    fi
    emit_summary FAIL 1 '["AGENT_FRONTMATTER_INVALID"]' "$checked" MEASURED
    exit 1
fi

echo ""
echo "=== Summary ==="
echo "checked=$checked agent frontmatter blocks (allowed tiers: $(echo "$allowed_tiers" | tr '\n' ' '))"

if [[ $fail -eq 0 ]]; then
    echo "RESULT: PASS"
    exit 0
else
    echo "RESULT: FAIL"
    exit 1
fi
