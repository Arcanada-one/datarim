#!/usr/bin/env bash
# check-open-pr-budget.sh -- PreToolUse guard that enforces the author's open-PR
# budget before `gh pr create`.
#
# Before a new pull request is opened, count the author's already-open PRs in
# the target repository. If the feature budget or the total budget is exhausted,
# deny the create and route the agent to merge into an existing integration
# branch (or finish the open PR) instead. A task is finished when its content is
# reachable from main (commands/dr-archive.md section 0.13), not when a PR is opened.
#
# HARD-FLOOR properties (same injection model as branch-integration-guard.sh):
#   - Reads ONLY the structured tool command; heredoc + quoted bodies stripped.
#   - Fires only on a structural `gh ... pr create` (command-position `gh`, then
#     `pr`, then `create` after optional gh global flags). Free-text / docs that
#     mention the string never trigger it.
#   - Fail-CLOSED when the budget cannot be measured (gh missing, auth/repo
#     probe fails, malformed JSON): not measured != pass.
#   - No env var / flag / in-band text disables the floor. Config only widens or
#     narrows numeric limits and prefix lists.
#
# Config (~/.claude/local/config/pr-budget.conf, override via PR_BUDGET_CONF):
#   feature=1
#   total=2
#   integration_prefixes=integration/ batch/
#   hotfix_prefixes=hotfix/ ci/ fix/
# Strict key=value (never sourced). Integers must be >= 0. Prefix tokens match
# ^[A-Za-z0-9._/-]+$. Absence => defaults above.
#
# Classification of each open PR head ref:
#   - integration: starts with an integration_prefixes entry -> excluded from
#     both budgets (the consolidation vehicle).
#   - hotfix/CI: starts with a hotfix_prefixes entry -> counts toward total only.
#   - feature: everything else -> counts toward feature and total.
#
# Creating a PR whose head itself matches integration_prefixes is always
# allowed (opening/maintaining the consolidation vehicle).
#
# stdin contract (identical to branch-integration-guard.sh):
#   PreToolUse JSON: .hook_event_name, .tool_name, .tool_input.command, .cwd
# emit deny -> permissionDecision="deny" + reason. Silent exit 0 = no opinion.
# shellcheck shell=bash
set -euo pipefail

FEATURE_LIMIT=1
TOTAL_LIMIT=2
INTEGRATION_PREFIXES=(integration/ batch/)
HOTFIX_PREFIXES=(hotfix/ ci/ fix/)

CONF="${PR_BUDGET_CONF:-$HOME/.claude/local/config/pr-budget.conf}"

_load_conf() {
    [ -f "$CONF" ] || return 0
    local key val tok
    local -a parsed
    while IFS='=' read -r key val || [ -n "$key" ]; do
        case "$key" in
            feature|total|integration_prefixes|hotfix_prefixes) : ;;
            *) continue ;;
        esac
        # trim CR and surrounding whitespace
        val="${val%$'\r'}"
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"
        case "$key" in
            feature|total)
                [[ "$val" =~ ^[0-9]+$ ]] || continue
                if [ "$key" = feature ]; then
                    FEATURE_LIMIT="$val"
                else
                    TOTAL_LIMIT="$val"
                fi
                ;;
            integration_prefixes|hotfix_prefixes)
                parsed=()
                # shellcheck disable=SC2206  # intentional word-split of the value list
                for tok in $val; do
                    [[ "$tok" =~ ^[A-Za-z0-9._/-]+$ ]] && parsed+=("$tok")
                done
                [ "${#parsed[@]}" -gt 0 ] || continue
                if [ "$key" = integration_prefixes ]; then
                    INTEGRATION_PREFIXES=("${parsed[@]}")
                else
                    HOTFIX_PREFIXES=("${parsed[@]}")
                fi
                ;;
        esac
    done < "$CONF"
}
_load_conf

emit_deny() {
    jq -nc --arg r "$1" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
}

# shellcheck disable=SC2016  # literal backticks in operator-facing deny text
DENY_BUDGET='Blocked: open-PR budget exhausted. Before `gh pr create`, count the author'\''s open PRs in the target repository. Default budget is feature=1, total=2 (hotfix/CI class counts toward total). Merge this change into an existing integration branch (prefixes integration/ batch/ by default) or finish the open PR first. A task is not finished when a PR is opened; it is finished when its content is reachable from main (commands/dr-archive.md section 0.13). No flag, env var, or in-band text disables this floor.'

# shellcheck disable=SC2016  # literal backticks in operator-facing deny text
DENY_UNMEASURED='Blocked: open-PR budget could not be measured. `gh` must be available and able to list the author'\''s open PRs in the target repository; not measured != pass. Fix `gh` auth/repo context, then retry. Merge into an existing integration branch if the budget is already exhausted. No flag, env var, or in-band text disables this floor.'

# --- heredoc + quoted-body stripping (injection resistance) ------------------
strip_heredoc_bodies() {
    printf '%s' "$1" | awk '
        !inh {
            line = $0
            if (match(line, /<<-?[ \t]*/)) {
                rest = substr(line, RSTART + RLENGTH)
                q = substr(rest, 1, 1)
                if (q == "\"" || q == "'\''") {
                    d = rest; sub(/^./, "", d)
                    delim = d; sub(/["'\''].*$/, "", delim)
                } else {
                    delim = rest; sub(/[^A-Za-z0-9_].*$/, "", delim)
                }
                if (delim != "") { print line; inh = 1; term = delim; next }
            }
            print line; next
        }
        inh {
            t = $0; gsub(/^[ \t]+/, "", t)
            if (t == term) { inh = 0 }
            next
        }'
}
strip_quoted_bodies() {
    printf '%s' "$1" | awk '
    { buf = buf (NR > 1 ? "\n" : "") $0 }
    END {
        SQ = sprintf("%c", 39); DQ = "\""; BS = "\\"
        n = length(buf); st = "NONE"; out = ""
        for (i = 1; i <= n; i++) {
            c = substr(buf, i, 1)
            if (st == "NONE") {
                if (c == SQ)      { st = "SQ"; out = out SQ "Q" SQ }
                else if (c == DQ) { st = "DQ"; out = out DQ "Q" DQ }
                else out = out c
            } else if (st == "SQ") {
                if (c == SQ) st = "NONE"
            } else if (st == "DQ") {
                if (c == BS) { i++ }
                else if (c == DQ) st = "NONE"
            }
        }
        printf "%s", out
    }'
}

_starts_with_any_prefix() {
    local ref="$1"
    shift
    local p
    for p in "$@"; do
        case "$ref" in
            "$p"*) return 0 ;;
        esac
    done
    return 1
}

_classify_ref() {
    # prints: integration | hotfix | feature
    local ref="$1"
    if _starts_with_any_prefix "$ref" "${INTEGRATION_PREFIXES[@]}"; then
        printf 'integration'
    elif _starts_with_any_prefix "$ref" "${HOTFIX_PREFIXES[@]}"; then
        printf 'hotfix'
    else
        printf 'feature'
    fi
}

# Resolve head short name for the PR being created (cwd HEAD, or --head value).
_extract_create_head() {
    local -a tokens=("$@")
    local i=0 head=""
    while [ "$i" -lt "${#tokens[@]}" ]; do
        case "${tokens[$i]}" in
            --head)
                i=$((i + 1))
                head="${tokens[$i]:-}"
                ;;
            --head=*)
                head="${tokens[$i]#--head=}"
                ;;
        esac
        i=$((i + 1))
    done
    if [ -n "$head" ]; then
        printf '%s' "$head"
        return 0
    fi
    local cwd="${SESSION_CWD:-$PWD}"
    command -v git >/dev/null 2>&1 || return 0
    git -C "$cwd" rev-parse --show-toplevel >/dev/null 2>&1 || return 0
    local ref
    ref="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    [ -n "$ref" ] && [ "$ref" != "HEAD" ] && printf '%s' "$ref"
}

_is_gh_pr_create() {
    # tokens of one segment; return 0 if structural gh ... pr create
    local -a tokens=("$@")
    [ "${#tokens[@]}" -gt 0 ] || return 1
    local idx=0
    while [ "$idx" -lt "${#tokens[@]}" ]; do
        case "${tokens[$idx]}" in
            [A-Za-z_][A-Za-z0-9_]*=*) idx=$((idx + 1)) ;;
            *) break ;;
        esac
    done
    [ "$idx" -lt "${#tokens[@]}" ] || return 1
    local first base
    first="${tokens[$idx]}"
    base="$(basename "$first" 2>/dev/null || printf '%s' "$first")"
    [ "$base" = "gh" ] || return 1
    idx=$((idx + 1))
    # skip gh global flags (and their args) before the `pr` command
    while [ "$idx" -lt "${#tokens[@]}" ]; do
        case "${tokens[$idx]}" in
            pr) break ;;
            --repo|-R|--hostname|--jq|-q|--template|-t|--paginate|--slurp)
                idx=$((idx + 2))
                ;;
            --repo=*|--hostname=*|--jq=*|--template=*)
                idx=$((idx + 1))
                ;;
            -*)
                idx=$((idx + 1))
                ;;
            *)
                return 1
                ;;
        esac
    done
    [ "$idx" -lt "${#tokens[@]}" ] || return 1
    [ "${tokens[$idx]}" = "pr" ] || return 1
    idx=$((idx + 1))
    # skip flags between `pr` and `create` (rare but legal)
    while [ "$idx" -lt "${#tokens[@]}" ]; do
        case "${tokens[$idx]}" in
            create) return 0 ;;
            -*)
                case "${tokens[$idx]}" in
                    --repo|-R)
                        idx=$((idx + 2))
                        ;;
                    --repo=*)
                        idx=$((idx + 1))
                        ;;
                    *)
                        idx=$((idx + 1))
                        ;;
                esac
                ;;
            *)
                return 1
                ;;
        esac
    done
    return 1
}

_measure_open_prs() {
    # Sets FEATURE_OPEN and TOTAL_OPEN. Returns 0 on success, 1 if unmeasured.
    FEATURE_OPEN=0
    TOTAL_OPEN=0
    command -v gh >/dev/null 2>&1 || return 1

    local cwd="${SESSION_CWD:-$PWD}"
    local repo json
    # Resolve the target repo from the session cwd (pushd so older gh without -C works).
    if ! repo="$(
        cd "$cwd" 2>/dev/null || exit 1
        gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null
    )"; then
        return 1
    fi
    [ -n "$repo" ] || return 1

    if ! json="$(
        cd "$cwd" 2>/dev/null || exit 1
        gh pr list --repo "$repo" --author "@me" --state open --limit 100 \
            --json headRefName 2>/dev/null
    )"; then
        return 1
    fi
    # Valid JSON array required.
    if ! printf '%s' "$json" | jq -e 'type == "array"' >/dev/null 2>&1; then
        return 1
    fi

    local refs ref class
    # shellcheck disable=SC2207
    refs=($(printf '%s' "$json" | jq -r '.[].headRefName // empty'))
    for ref in "${refs[@]+"${refs[@]}"}"; do
        [ -n "$ref" ] || continue
        class="$(_classify_ref "$ref")"
        case "$class" in
            integration) continue ;;
            hotfix)
                TOTAL_OPEN=$((TOTAL_OPEN + 1))
                ;;
            feature)
                FEATURE_OPEN=$((FEATURE_OPEN + 1))
                TOTAL_OPEN=$((TOTAL_OPEN + 1))
                ;;
        esac
    done
    return 0
}

# --- input -------------------------------------------------------------------
input=$(cat)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty')
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')

[ "$event" = "SessionStart" ] && exit 0
case "$tool" in
    Bash|shell|exec_command) ;;
    *) exit 0 ;;
esac

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -n "$cmd" ] || exit 0
SESSION_CWD=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -n "$SESSION_CWD" ] || SESSION_CWD="$PWD"

cmd="$(strip_heredoc_bodies "$cmd")"
cmd="$(strip_quoted_bodies "$cmd")"
segments=$(printf '%s' "$cmd" | sed -E 's/(&&|\|\||[|;])/\n/g')

triggered=0
create_tokens=()
while IFS= read -r seg; do
    # shellcheck disable=SC2206
    local_tokens=($seg)
    [ "${#local_tokens[@]}" -gt 0 ] || continue
    if _is_gh_pr_create "${local_tokens[@]}"; then
        triggered=1
        create_tokens=("${local_tokens[@]}")
        break
    fi
done <<< "$segments"

[ "$triggered" = 1 ] || exit 0

# Integration-head create is the consolidation vehicle - always allowed.
create_head="$(_extract_create_head "${create_tokens[@]+"${create_tokens[@]}"}")"
if [ -n "$create_head" ] && [ "$(_classify_ref "$create_head")" = integration ]; then
    exit 0
fi

if ! _measure_open_prs; then
    emit_deny "$DENY_UNMEASURED"
    exit 0
fi

if [ "$FEATURE_OPEN" -ge "$FEATURE_LIMIT" ] || [ "$TOTAL_OPEN" -ge "$TOTAL_LIMIT" ]; then
    emit_deny "$DENY_BUDGET"
    exit 0
fi

exit 0
