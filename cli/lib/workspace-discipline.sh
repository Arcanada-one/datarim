#!/usr/bin/env bash
# workspace-discipline.sh — shared workspace discipline helpers (Phase 2b, TUNE-0268).
# Source: plan TUNE-0268 § Phase 2 step 2.2 + threat-model rows 475-476.
#
# Public API:
#   ws_check_id_ownership <file> <task_id>
#       Passive check: returns 0 if file references only <task_id> или вообще
#       не упоминает TASK-* токенов; returns 34 WORKSPACE_DISCIPLINE_VIOLATION
#       при обнаружении foreign TASK-ID. Stderr emits short violation summary
#       (foreign IDs listed).
#
#   ws_stage_selective_hunk <file> <task_id>
#       Defensive `git update-index --add <file>` — выполняется ТОЛЬКО если:
#         (a) файл расположен внутри git working tree И
#         (b) ws_check_id_ownership проходит.
#       Если файл не tracked (нет git repo, либо в .gitignore) — no-op exit 0.
#       Никогда не вызывает `git add -A`.
#
# Канонический TASK-ID regex (per ws_validate_task_id в workspace.sh):
#   ^[A-Z][A-Z0-9]+-[0-9]+[A-Z]?$  (PREFIX-NNNN[A])
#
# Dependencies: bash 3.2+, grep, git (опционально).

[[ -n "${_WS_DISCIPLINE_LOADED:-}" ]] && return 0
_WS_DISCIPLINE_LOADED=1

_WS_TASKID_REGEX='[A-Z][A-Z0-9]+-[0-9]+[A-Z]?'

ws_check_id_ownership() {
    local file="${1:?ws_check_id_ownership: file required}"
    local task_id="${2:?ws_check_id_ownership: task_id required}"

    if [[ ! -f "$file" ]]; then
        return 0  # nothing to check
    fi

    # Extract distinct TASK-ID tokens with word boundaries.
    local found
    found="$(grep -oE "\\b${_WS_TASKID_REGEX}\\b" "$file" 2>/dev/null | sort -u || true)"
    if [[ -z "$found" ]]; then
        return 0  # no TASK-ID references → passive pass
    fi

    local foreign=()
    local id
    while IFS= read -r id; do
        [[ -z "$id" ]] && continue
        if [[ "$id" != "$task_id" ]]; then
            foreign+=("$id")
        fi
    done <<< "$found"

    if (( ${#foreign[@]} == 0 )); then
        return 0
    fi

    printf 'workspace-discipline: file %s references foreign TASK-IDs (expected only %s): %s\n' \
        "$file" "$task_id" "${foreign[*]}" >&2
    return 34
}

ws_stage_selective_hunk() {
    local file="${1:?ws_stage_selective_hunk: file required}"
    local task_id="${2:?ws_stage_selective_hunk: task_id required}"

    if [[ ! -f "$file" ]]; then
        return 0
    fi

    # Inside a git working tree?
    if ! git -C "$(dirname "$file")" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0  # not git-tracked → no-op
    fi

    # File тracked by git? (Honours .gitignore — untracked файлы пропускаем.)
    if ! git -C "$(dirname "$file")" ls-files --error-unmatch "$(basename "$file")" >/dev/null 2>&1; then
        return 0  # gitignored или вне индекса → no-op
    fi

    # Ownership gate.
    ws_check_id_ownership "$file" "$task_id" || return 34

    git -C "$(dirname "$file")" update-index --add -- "$(basename "$file")" 2>&1
}
