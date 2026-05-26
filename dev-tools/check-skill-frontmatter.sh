#!/usr/bin/env bash
#
# check-skill-frontmatter.sh — TUNE-0304 V-AC-4 gate (supersedes TUNE-0114).
#
# Validates skill frontmatter under the universal SKILL.md schema:
#   REQUIRED  name, description
#   OPTIONAL  model (∈ {inherit, sonnet, opus, haiku} or full model ID)
#             effort, disable-model-invocation, allowed-tools
#             metadata.model_tier (∈ {reasoning, balanced, fast, cheap})
#             metadata.current_aal, metadata.target_aal (1..5)
#             metadata.runtime (any), metadata.creators (any)
#   WARN ONLY top-level `runtime:` (legacy; migration window)
#
# Scans both flat skills/<name>.md and nested skills/<name>/SKILL.md so the
# script is safe to run during the migration hybrid window. Reserved
# skills/.system/ namespace (Constraint C3) is skipped.
#
# Companion: AGENTS.md MUST be a symlink → CLAUDE.md (AC-7 carry-over).
#
# Usage: check-skill-frontmatter.sh [--root <repo-root>]
# Exit 0 PASS, 1 FAIL.

set -euo pipefail

ROOT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$ROOT" ]]; then
    ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

cd "$ROOT"

fail=0
warn=0
checked=0

# Allowed model: aliases.
model_alias_re='^(inherit|sonnet|opus|haiku)$'
# Allowed full model ID (provider-prefix/model or bare kebab id).
model_full_re='^[a-z0-9_-]+(/[a-z0-9_.-]+)?$'

tier_re='^(reasoning|balanced|fast|cheap)$'

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
        echo "FAIL ($label): MISS name"
        fail=1
    fi

    if [[ -z "$desc" ]]; then
        echo "FAIL ($label): MISS description"
        fail=1
    fi

    if [[ -n "$model" ]]; then
        if ! [[ "$model" =~ $model_alias_re || "$model" =~ $model_full_re ]]; then
            echo "FAIL ($label): invalid model value '$model' — expected inherit|sonnet|opus|haiku or full ID"
            fail=1
        fi
    fi

    if [[ -n "$tier" ]]; then
        if ! [[ "$tier" =~ $tier_re ]]; then
            echo "FAIL ($label): invalid metadata.model_tier '$tier' — expected reasoning|balanced|fast|cheap"
            fail=1
        fi
    fi

    # Legacy top-level runtime: → WARN only (migration window).
    if echo "$fm" | grep -qE '^runtime:[[:space:]]'; then
        echo "WARN ($label): legacy top-level runtime: — move into metadata.runtime: post-migration"
        warn=$((warn + 1))
    fi
}

# Walk skills/ scanning both layouts.
shopt -s nullglob
for entry in skills/*.md; do
    [[ -f "$entry" ]] || continue
    check_file "$entry" "$(basename "$entry")"
done
for skill_md in skills/*/SKILL.md; do
    [[ -f "$skill_md" ]] || continue
    parent="$(basename "$(dirname "$skill_md")")"
    # Skip reserved namespace.
    [[ "$parent" == ".system" ]] && continue
    check_file "$skill_md" "$parent/SKILL.md"
done

# Companion check: AGENTS.md symlink integrity (TUNE-0114 AC-7).
if [[ ! -L AGENTS.md ]]; then
    echo "FAIL AGENTS.md not a symlink"
    fail=1
elif [[ "$(readlink AGENTS.md)" != "CLAUDE.md" ]]; then
    echo "FAIL AGENTS.md target != CLAUDE.md (got: $(readlink AGENTS.md))"
    fail=1
fi

echo ""
echo "=== Summary ==="
echo "checked=$checked frontmatter blocks, warnings=$warn"

if [[ $fail -eq 0 ]]; then
    echo "RESULT: PASS (V-AC-4 + AC-7)"
    exit 0
else
    echo "RESULT: FAIL"
    exit 1
fi
