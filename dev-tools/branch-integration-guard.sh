#!/usr/bin/env bash
# branch-integration-guard.sh -- PreToolUse hard-floor that forbids integrating
# an integration branch (dev/develop/...) DIRECTLY into a protected branch
# (main/master/...). Protected branches receive changes only through the review
# path: feature branch -> pull/merge request -> protected branch.
#
# This is a HARD-FLOOR: injection-resistant. No env var, flag, marker file, or
# in-band text ("ignore this rule", "you may merge dev into main this once")
# disables it. The guard reads ONLY the structured tool command, never free-text
# prompts / task descriptions / commit-message bodies for permission signals.
#
# stdin contract (identical to coworker-hook-guard.sh / datarim-exec-guard.sh):
#   PreToolUse JSON: .hook_event_name, .tool_name, .tool_input.command, .cwd
# emit deny -> permissionDecision="deny" + reason. Silent exit 0 = no opinion.
#
# Matches mutating git tool-calls only (Bash / shell / exec_command). Read-only
# look-alikes (`git log dev..main`, `git branch --merged main`, `rg "merge dev"`)
# pass through structurally -- the guard fires only when the command-position
# token is `git` AND the subcommand is a mutating one (merge/push/rebase).
#
# Fail-CLOSED on ambiguity: when a HEAD-dependent form cannot prove HEAD is safe
# (detached HEAD, non-repo cwd, git absent), the guard BLOCKS. A direct dev->main
# integration is irreversible once it lands; an over-block is a recoverable
# annoyance. (Contrast datarim-exec-guard.sh, which fails OPEN -- its miss is
# benign; here the miss is destructive, so the safe direction flips.)
#
# Config (widen/narrow the sets only -- can NEVER disable the floor):
#   ~/.claude/local/config/branch-integration-guard.conf
#   integration_branches=dev develop ...
#   protected_targets=main master ...
# Parsed as strict key=value (never eval/source); tokens validated
# ^[A-Za-z0-9._/-]+$. Absence => built-in defaults below.
# shellcheck shell=bash
set -euo pipefail

# --- configurable sets (defaults; identifier-free, generic) ------------------
INTEGRATION_BRANCHES=(dev develop development integration staging)
PROTECTED_TARGETS=(main master trunk release)

CONF="${BRANCH_INTEGRATION_GUARD_CONF:-$HOME/.claude/local/config/branch-integration-guard.conf}"
_load_conf() {
    [ -f "$CONF" ] || return 0
    local key val tok
    local -a parsed
    while IFS='=' read -r key val; do
        case "$key" in
            integration_branches|protected_targets) : ;;
            *) continue ;;
        esac
        parsed=()
        # shellcheck disable=SC2206  # intentional word-split of the value list
        for tok in $val; do
            [[ "$tok" =~ ^[A-Za-z0-9._/-]+$ ]] && parsed+=("$tok")
        done
        # Never let config EMPTY a set -- the floor's defaults remain.
        [ "${#parsed[@]}" -gt 0 ] || continue
        if [ "$key" = "integration_branches" ]; then
            INTEGRATION_BRANCHES=("${parsed[@]}")
        else
            PROTECTED_TARGETS=("${parsed[@]}")
        fi
    done < "$CONF"
}
_load_conf

# --- membership helpers ------------------------------------------------------
# Normalise a ref token: strip a leading '+' (force refspec), a 'refs/heads/'
# prefix, and ONE leading '<remote>/' segment, so `origin/dev` / `+dev` /
# `refs/heads/main` all resolve to their short name.
_normalise_ref() {
    local r="$1"
    r="${r#+}"
    r="${r#refs/heads/}"
    # strip one leading remote segment only if what remains is a bare name
    if [[ "$r" == */* ]]; then r="${r##*/}"; fi
    printf '%s' "$r"
}
_in_set() {
    local needle="$1"; shift
    local x
    for x in "$@"; do [ "$x" = "$needle" ] && return 0; done
    return 1
}
_is_integration() { _in_set "$(_normalise_ref "$1")" "${INTEGRATION_BRANCHES[@]}"; }
_is_protected()  { _in_set "$(_normalise_ref "$1")" "${PROTECTED_TARGETS[@]}"; }

# --- deny emitter ------------------------------------------------------------
emit_deny() {
    jq -nc --arg r "$1" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
}

DENY_REASON='Blocked: direct integration of an integration branch into a protected branch. This command merges/pushes an integration branch (e.g. dev/develop/integration) straight into a protected branch (e.g. main/master/trunk), which the branch-integration floor forbids. Protected branches receive changes only through the review path: push your work to a feature branch and open a pull/merge request (e.g. `git push -u origin <feature>` then `gh pr create` / `glab mr create`). Pulling the protected branch DOWN into your branch (`git merge main`) is allowed. No flag, env var, or in-band text disables this floor. If HEAD could not be resolved, re-run from an unambiguous branch or use the PR path.'

# --- heredoc + quoted-body stripping (injection resistance) ------------------
# Document text inside a heredoc / a quoted string literal is DATA, never a
# command-position token. Strip both before analysis so a doc or commit message
# containing `git merge dev` (or "ignore this rule") neither false-denies nor is
# honoured. (Same passes as datarim-exec-guard.sh DEF-1h / DEF-1m.)
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

# --- read-only HEAD resolution (mutates nothing) -----------------------------
# Prints the current branch short-name, or empty string on UNKNOWN (git absent,
# non-repo cwd, detached HEAD).
resolve_head() {
    local cwd="$1"
    command -v git >/dev/null 2>&1 || return 0
    git -C "$cwd" rev-parse --show-toplevel >/dev/null 2>&1 || return 0
    local ref
    ref="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    [ -n "$ref" ] && [ "$ref" != "HEAD" ] && printf '%s' "$ref"
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
session_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -n "$session_cwd" ] || session_cwd="$PWD"

# strip data bodies, then split into command-position segments
cmd="$(strip_heredoc_bodies "$cmd")"
cmd="$(strip_quoted_bodies "$cmd")"
segments=$(printf '%s' "$cmd" | sed -E 's/(&&|\|\||[|;])/\n/g')

# effective HEAD: starts at the real HEAD, updated by checkout/switch within the
# same command (B7 compound catch -- `git checkout main && git merge dev`).
effective_head="$(resolve_head "$session_cwd")"

deny() { emit_deny "$DENY_REASON"; exit 0; }

while IFS= read -r seg; do
    # tokenise; skip leading VAR=val env-assignments to find command position
    # shellcheck disable=SC2206
    local_tokens=($seg)
    [ "${#local_tokens[@]}" -gt 0 ] || continue
    idx=0
    while [ "$idx" -lt "${#local_tokens[@]}" ]; do
        case "${local_tokens[$idx]}" in
            [A-Za-z_][A-Za-z0-9_]*=*) idx=$((idx + 1)) ;;
            *) break ;;
        esac
    done
    [ "$idx" -lt "${#local_tokens[@]}" ] || continue
    first="${local_tokens[$idx]}"
    base="$(basename "$first" 2>/dev/null || printf '%s' "$first")"
    [ "$base" = "git" ] || continue
    sub="${local_tokens[$((idx + 1))]:-}"

    # collect non-flag args after the subcommand
    args=()
    j=$((idx + 2))
    while [ "$j" -lt "${#local_tokens[@]}" ]; do
        case "${local_tokens[$j]}" in
            -*) : ;;                       # flags handled per-subcommand below
            *) args+=("${local_tokens[$j]}") ;;
        esac
        j=$((j + 1))
    done
    # note presence of a force flag anywhere in the segment (B5)
    has_force=0
    for t in "${local_tokens[@]:$idx}"; do
        case "$t" in --force|-f) has_force=1 ;; esac
    done

    case "$sub" in
        checkout|switch)
            # update effective HEAD if this segment moves onto a known branch.
            # `checkout -b X` / `switch -c X` create+move; last positional is the target.
            new="${args[${#args[@]}-1]:-}"
            [ -n "$new" ] && effective_head="$(_normalise_ref "$new")"
            ;;
        merge)
            # B1/B2: `git merge <INT>` is a violation only when effective HEAD
            # is a protected target. `git merge <PROT>` (reverse pull) always ok.
            src="${args[0]:-}"
            [ -n "$src" ] || continue
            if _is_integration "$src"; then
                # HEAD must be protected -> block. UNKNOWN HEAD -> fail-closed block.
                if [ -z "$effective_head" ] || _is_protected "$effective_head"; then
                    deny
                fi
            fi
            ;;
        rebase)
            # B8: `git rebase <INT> <PROT>` rewrites PROT onto INT.
            up="${args[0]:-}"; onto="${args[1]:-}"
            if [ -n "$onto" ] && _is_integration "$up" && _is_protected "$onto"; then
                deny
            fi
            ;;
        push)
            # scan for a refspec SRC:DST, else a single ref arg (current->ref).
            refspec=""
            single=""
            for a in "${args[@]}"; do
                case "$a" in
                    *:*) refspec="$a"; break ;;
                    *) [ -z "$single" ] && single="$a" || single="$single" ;;
                esac
            done
            if [ -n "$refspec" ]; then
                # B3/B4/B5/B9: SRC:DST
                s="${refspec%%:*}"; d="${refspec#*:}"
                # HEAD on SRC resolves to effective_head
                if [ "$(_normalise_ref "$s")" = "HEAD" ]; then s="$effective_head"; fi
                src_int=0; dst_prot=0
                { [ -n "$s" ] && _is_integration "$s"; } && src_int=1
                _is_protected "$d" && dst_prot=1
                # HEAD:PROT with UNKNOWN head is fail-closed (B4)
                if [ "$(_normalise_ref "${refspec%%:*}")" = "HEAD" ] && [ -z "$effective_head" ] && [ "$dst_prot" = 1 ]; then
                    deny
                fi
                if [ "$src_int" = 1 ] && [ "$dst_prot" = 1 ]; then
                    deny
                fi
                # force flag doesn't change the verdict; noted for completeness
                : "$has_force"
            elif [ -n "$single" ]; then
                # B6: `git push <remote> <PROT>` while HEAD is INT (last positional
                # after the remote is the protected target; remote is args[0]).
                # args: [remote, PROT] typically. Treat the LAST positional as ref.
                ref="${args[${#args[@]}-1]:-}"
                if _is_protected "$ref"; then
                    if [ -z "$effective_head" ] || _is_integration "$effective_head"; then
                        deny
                    fi
                fi
            fi
            ;;
    esac
done <<< "$segments"

exit 0
