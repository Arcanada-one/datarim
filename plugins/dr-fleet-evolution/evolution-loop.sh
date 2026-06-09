#!/usr/bin/env bash
# evolution-loop.sh — Bash-native fleet skill-evolution loop.
#
# Pipeline: collect signals (registered adapters) -> generate N candidates
# (coworker write) -> run all constraint gates on each -> select the best
# gate-passing candidate by judged success-rate (coworker ask) -> open a PR
# branch. Never auto-merges.
#
# Usage:
#   evolution-loop.sh --skill <skill-dir> [options]
# Options:
#   --skill <dir>            skill directory containing SKILL.md (required)
#   --adapters-conf <file>   source-adapters.conf (default: plugin default)
#   --candidates <N>         number of variants to generate (default 3)
#   --threshold <N>          minimum eval-dataset size to proceed (default 5)
#   --dry-run                do everything except git push / PR (local branch only)
#   -h|--help                this help
#
# Env overrides (testability):
#   COWORKER_BIN   path to a coworker shim (default: coworker on PATH)
#   GIT_BIN        path to git (default: git on PATH)
#   COWORKER_TIMEOUT  per-call seconds (default 60; ignored if no `timeout`)

set -o pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/jsonl.sh
source "$PLUGIN_DIR/lib/jsonl.sh"

COWORKER_BIN="${COWORKER_BIN:-coworker}"
GIT_BIN="${GIT_BIN:-git}"
COWORKER_TIMEOUT="${COWORKER_TIMEOUT:-60}"

# Fixed, constant instruction strings (never carry data — Security S1).
GEN_SPEC='Improve this fleet starter skill using the eval dataset. Keep changes minimal and keep the YAML frontmatter intact. Output ONLY the new SKILL.md content.'
SCORE_Q='Score how well this skill would handle the eval dataset. Output ONLY a number between 0.0 and 1.0.'

log() { echo "evolution-loop: $*" >&2; }

usage() { sed -n '3,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# Run coworker with an optional timeout wrapper (timeout is absent on macOS).
_coworker() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$COWORKER_TIMEOUT" "$COWORKER_BIN" "$@"
    else
        "$COWORKER_BIN" "$@"
    fi
}

# Expand ~ and ${VAR} in a config source-path.
_expand_path() {
    local p=$1
    p=$(eval echo "$p")  # expands ${VAR} and ~
    printf '%s' "$p"
}

# --- Stage 1: collect -----------------------------------------------------
collect_dataset() {
    local conf=$1 out=$2
    : > "$out"
    local line script_rel source_path label script_abs raw
    while IFS= read -r line; do
        case "$line" in ''|\#*) continue ;; esac
        IFS='|' read -r script_rel source_path label <<< "$line"
        script_abs="$PLUGIN_DIR/${script_rel#plugins/dr-fleet-evolution/}"
        [ -x "$script_abs" ] || { log "adapter not executable: $script_abs (skip)"; continue; }
        source_path=$(_expand_path "$source_path")
        if [ ! -e "$source_path" ]; then
            log "source path missing for '$label': $source_path (skip)"
            continue
        fi
        if raw=$("$script_abs" "$source_path" 2>/dev/null); then
            printf '%s\n' "$raw" >> "$out"
        else
            log "adapter '$label' failed (skip)"
        fi
    done < "$conf"
    # Drop blank lines produced by empty adapters.
    grep -c . "$out" >/dev/null 2>&1 || true
    local merged; merged=$(jsonl_merge "$out" 2>/dev/null || true)
    printf '%s\n' "$merged" | grep -c . >/dev/null 2>&1
    printf '%s' "$merged" > "$out"
}

# --- main -----------------------------------------------------------------
main() {
    local skill_dir="" conf="$PLUGIN_DIR/adapters/source-adapters.conf"
    local candidates=3 threshold=5 dry_run=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --skill) skill_dir=$2; shift 2 ;;
            --adapters-conf) conf=$2; shift 2 ;;
            --candidates) candidates=$2; shift 2 ;;
            --threshold) threshold=$2; shift 2 ;;
            --dry-run) dry_run=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) log "unknown arg: $1"; usage >&2; exit 2 ;;
        esac
    done
    [ -n "$skill_dir" ] || { log "--skill is required"; exit 2; }
    local skill_md="$skill_dir/SKILL.md"
    [ -f "$skill_md" ] || { log "no SKILL.md in $skill_dir"; exit 2; }
    [ -f "$conf" ] || { log "adapters-conf not found: $conf"; exit 2; }
    jsonl_require_jq || exit 3

    local level; level=$(basename "$skill_dir")
    local work; work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT

    # Stage 1: collect.
    # NOTE: .txt extension (not .jsonl) is mandatory — `coworker` rejects
    # non-text extensions in --context/--paths (file-type policy, exit 6).
    # The content is JSONL; the extension only satisfies the coworker gate.
    local dataset="$work/eval.txt"
    collect_dataset "$conf" "$dataset"
    local n; n=$(grep -c . "$dataset" 2>/dev/null || echo 0)
    log "collected $n eval records"
    if [ "$n" -lt "$threshold" ]; then
        log "dataset below threshold ($n < $threshold) — skipping evolution (not an error)"
        exit 0
    fi

    # Stage 2: generate variants.
    local i passed=() cand
    for i in $(seq 1 "$candidates"); do
        cand="$work/candidate-$i.md"
        if _coworker write --provider deepseek --profile datarim \
                --spec "$GEN_SPEC" \
                --context "$skill_md" "$dataset" \
                --target "$cand" >/dev/null 2>&1 && [ -s "$cand" ]; then
            : # generated
        else
            log "candidate $i generation failed (skip)"
            continue
        fi
        # Stage 3: gates (fail-closed).
        if "$PLUGIN_DIR/gates/run-all-gates.sh" "$cand" "$level" >/dev/null 2>&1; then
            passed+=("$cand")
        else
            log "candidate $i rejected by gates"
        fi
    done

    if [ "${#passed[@]}" -eq 0 ]; then
        log "no candidate passed the gates — no PR"
        exit 1
    fi

    # Stage 4: select best by judged success-rate; ties -> smaller size.
    local best="" best_score="-1" best_size="" c score size
    for c in "${passed[@]}"; do
        score=$(_coworker ask --provider deepseek --profile datarim \
                    --paths "$c" "$dataset" --question "$SCORE_Q" 2>/dev/null \
                | grep -oE '[0-9]+\.[0-9]+|[0-9]+' | head -n1)
        [ -n "$score" ] || score="0"
        size=$(wc -c < "$c")
        if awk "BEGIN{exit !($score > $best_score)}"; then
            best="$c"; best_score="$score"; best_size="$size"
        elif awk "BEGIN{exit !($score == $best_score)}" && [ "$size" -lt "${best_size:-999999999}" ]; then
            best="$c"; best_size="$size"
        fi
    done
    log "selected best candidate (score=$best_score, size=$best_size)"

    # Stage 5: open PR branch (never auto-merge).
    local short_skill; short_skill=$(echo "$level" | tr -cd 'a-z0-9-')
    local branch="feat/tune-0380-evolve-${short_skill}"
    cp "$best" "$skill_md"
    if [ "$dry_run" -eq 1 ]; then
        log "dry-run: candidate applied to $skill_md locally; no branch/push"
        log "DRY_RUN_DIFF_BEGIN"
        "$GIT_BIN" --no-pager diff -- "$skill_md" 2>/dev/null || true
        log "DRY_RUN_DIFF_END"
        exit 0
    fi
    "$GIT_BIN" checkout -b "$branch" 2>/dev/null || "$GIT_BIN" checkout "$branch"
    "$GIT_BIN" add "$skill_md"
    "$GIT_BIN" commit -m "evolve fleet skill $level (score=$best_score)" >/dev/null 2>&1
    "$GIT_BIN" push origin "HEAD:$branch" 2>/dev/null \
        && log "pushed branch $branch — open PR manually (never auto-merge)" \
        || log "push failed — branch $branch exists locally; push + open PR manually"
    exit 0
}

main "$@"
