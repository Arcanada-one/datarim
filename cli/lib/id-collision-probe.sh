#!/usr/bin/env bash
# id-collision-probe.sh — workspace-wide ID collision probe (Phase 2, TUNE-0268).
# Source: creative-TUNE-0268-architecture-id-collision-probe.md § IP-1..IP-5.
#
# Public API:
#   probe_collisions <ID> <WORKSPACE_ROOT>
#       Writes JSON array of collision records к stdout.
#       Returns: 0 if clean (empty array), 28 if collisions found, 29 if probe timed out.
#
# Collision record schema:
#   {id, source_file (relative to root), source_line (1-indexed),
#    source_type ∈ {backlog,archive,prd,tasks_md,other},
#    conflict_with_content (≤80 chars, word-boundary clip + ellipsis)}
#
# Dependencies: find, grep, jq, timeout/gtimeout (coreutils).

[[ -n "${_ID_COLLISION_PROBE_LOADED:-}" ]] && return 0
_ID_COLLISION_PROBE_LOADED=1

_PROBE_TIMEOUT_SEC="${DATARIM_PROBE_TIMEOUT_SEC:-5}"

_probe_classify_source() {
    local file="$1"
    case "$file" in
        */backlog.md|*/backlog-*.md) printf 'backlog' ;;
        */archive-*.md)              printf 'archive' ;;
        */prd/*.md|*/PRD-*.md)       printf 'prd' ;;
        */tasks/*.md)                printf 'tasks_md' ;;
        *)                           printf 'other' ;;
    esac
}

# _probe_truncate_content <line>
# Trims to ≤80 chars with word-boundary clip in [60..80] and trailing ellipsis.
_probe_truncate_content() {
    local s="$1"
    local len=${#s}
    if (( len <= 80 )); then
        printf '%s' "$s"
        return
    fi
    local i clip=80
    for (( i=80; i>=60; i-- )); do
        if [[ "${s:i-1:1}" == ' ' ]]; then
            clip=$((i-1))
            break
        fi
    done
    printf '%s…' "${s:0:clip}"
}

# probe_collisions <ID> <WORKSPACE_ROOT>
probe_collisions() {
    local id="$1"
    local root="$2"
    local timeout_bin=""
    if command -v timeout >/dev/null 2>&1; then
        timeout_bin="timeout"
    elif command -v gtimeout >/dev/null 2>&1; then
        timeout_bin="gtimeout"
    fi

    # Discover candidate files.
    local files find_rc=0
    if [[ -n "$timeout_bin" ]]; then
        files="$("$timeout_bin" "${_PROBE_TIMEOUT_SEC}" find "$root" -maxdepth 8 -type f \
            -not -path '*/.git/*' \
            -not -path '*/node_modules/*' \
            -not -path '*/Projects/Datarim/*' \
            -not -name '*sync-conflict*' \
            \( -name 'backlog.md' -o -name 'archive-*.md' -o -path '*/tasks/*.md' -o -path '*/prd/*.md' \) \
            2>/dev/null)"
        find_rc=$?
    else
        files="$(find "$root" -maxdepth 8 -type f \
            -not -path '*/.git/*' \
            -not -path '*/node_modules/*' \
            -not -path '*/Projects/Datarim/*' \
            -not -name '*sync-conflict*' \
            \( -name 'backlog.md' -o -name 'archive-*.md' -o -path '*/tasks/*.md' -o -path '*/prd/*.md' \) \
            2>/dev/null)"
    fi

    if (( find_rc == 124 )); then
        printf '[]'
        return 29
    fi

    # Scan with grep -nE.
    local matches=()
    local file grep_out match
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        # Defense-in-depth sync-conflict skip (find predicate is primary).
        if [[ "$file" == *sync-conflict* ]]; then
            continue
        fi
        grep_out="$(grep -nE "\\b${id}\\b" "$file" 2>/dev/null)" || continue
        while IFS= read -r match; do
            [[ -z "$match" ]] && continue
            matches+=("$file"$'\t'"$match")
        done <<< "$grep_out"
    done <<< "$files"

    if (( ${#matches[@]} == 0 )); then
        printf '[]'
        return 0
    fi

    # Build JSON array (one jq call with batched stdin).
    local rel_root_len=${#root}
    local payload=""
    local entry rel lineno content src_type
    for entry in "${matches[@]}"; do
        file="${entry%%$'\t'*}"
        local rest="${entry#*$'\t'}"
        lineno="${rest%%:*}"
        content="${rest#*:}"
        if [[ "$file" == "$root"/* ]]; then
            rel="${file:$((rel_root_len+1))}"
        else
            rel="$file"
        fi
        src_type="$(_probe_classify_source "$file")"
        content="$(_probe_truncate_content "$content")"
        # NUL-separated fields per record to survive embedded special chars in jq input.
        payload+="${id}"$'\x1f'"${rel}"$'\x1f'"${lineno}"$'\x1f'"${src_type}"$'\x1f'"${content}"$'\x1e'
    done

    printf '%s' "$payload" | jq -Rsc '
        split("")
        | map(select(length > 0))
        | map(
            split("") as $f
            | {
                id: $f[0],
                source_file: $f[1],
                source_line: ($f[2] | tonumber),
                source_type: $f[3],
                conflict_with_content: $f[4]
              }
          )'
    return 28
}
