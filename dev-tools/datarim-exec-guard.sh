#!/usr/bin/env bash
# PreToolUse guard: deny executing Datarim tasks (/dr-* pipeline stages) on
# this machine when the current workspace declares a required execution host
# elsewhere. Emits an actionable delegation directive pointing to
# dev-tools/datarim-dispatch.sh. (TUNE-0471, Phase 1 — machine-local.)
#
# stdin contract (identical to coworker-hook-guard.sh, TUNE-0303 precedent):
#   PreToolUse JSON: .hook_event_name, .tool_name, .tool_input.command, .cwd
#
# Matches ONLY executional tool-calls:
#   - Bash / shell / exec_command whose command contains a /dr-<word>
#     invocation, OR invokes a CLI agent (claude|codex) directly.
# Any other tool call (Read/Write/Edit/etc.) -> silent passthrough (exit 0).
#
# Resolution: walk up from cwd (or tool_input.command's implied cwd) until a
# directory containing datarim/ is found, then match against
# bindings[].workspace in the execution-hosts map (default
# ~/.claude/local/config/execution-hosts.yml; test override ONLY via
# DATARIM_EXEC_GUARD_MAP env var — this is a TEST-ONLY hook, never read by
# the real dispatch path in prod; the canonical override contract per the
# plan is `--map <file>` for the dispatch CLI. The guard itself has no CLI
# surface (it is invoked by the harness with stdin only), so an env var is
# used here strictly for bats fixtures; production activation always reads
# the default path).
#
# Exemptions (allow + audit-log line, never denied):
#   - datarim/.exec-local-override marker file (operator-created)
#   - datarim-doctor.sh / /dr-doctor invocations (repair-class; operator
#     amendment 2026-07-12) -> audit-log line "allowed-doctor-local"
#   - dev-tools/datarim-dispatch.sh itself (the sanctioned delegation
#     channel must never be blocked by the guard it triggers)
#
# No env var disables the guard's deny behaviour (only the two documented
# exemptions above bypass it). skip-permissions modes do not bypass
# PreToolUse hooks (same guarantee as coworker-hook-guard.sh).
# shellcheck shell=bash
set -euo pipefail

DEFAULT_MAP="${HOME}/.claude/local/config/execution-hosts.yml"
MAP_PATH="${DATARIM_EXEC_GUARD_MAP:-$DEFAULT_MAP}"
AUDIT_LOG="${DATARIM_EXEC_GUARD_AUDIT_LOG:-${HOME}/.claude/logs/exec-dispatch.log}"

# --- TUNE-0472 Phase 2: shared resolver library ------------------------------
# Prefer the framework-native dev-tools/lib/execution-host.sh (ships in
# Datarim >= 2.54.0). Fall back to the embedded Phase-1 match logic below
# when the lib is not yet installed on this machine (pre-release runtime, or
# an operator on an older Datarim version) — the guard must never break due
# to a missing upstream file.
EH_LIB="${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/lib/execution-host.sh"
EH_LIB_AVAILABLE=0
if [ -f "$EH_LIB" ]; then
    # shellcheck source=/dev/null
    if source "$EH_LIB" 2>/dev/null; then
        EH_LIB_AVAILABLE=1
    fi
fi

# --- audit log ---------------------------------------------------------
audit_log() {
    local decision="$1" task_ctx="$2" host="$3" vendor="${4:-n/a}"
    local dir
    dir="$(dirname "$AUDIT_LOG")"
    mkdir -p "$dir" 2>/dev/null || return 0
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$decision" "$task_ctx" "$host" "$vendor" \
        >> "$AUDIT_LOG" 2>/dev/null || true
}

emit_deny() {
    jq -nc --arg r "$1" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
}

# --- walk-up: find nearest ancestor dir containing datarim/ ------------
# Delegates to the shared lib's eh_resolve_workspace_root() when available;
# falls back to the embedded Phase-1 walk-up otherwise (no lib -> no break).
resolve_datarim_root() {
    local dir="$1"
    if [ "$EH_LIB_AVAILABLE" -eq 1 ]; then
        eh_resolve_workspace_root "$dir"
        return $?
    fi
    while [ -n "$dir" ] && [ "$dir" != "/" ]; do
        if [ -d "$dir/datarim" ]; then
            printf '%s' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# --- lookup binding for a resolved workspace root -----------------------
# Emits: required_host<TAB>host_aliases_csv<TAB>tailscale_ip<TAB>ssh_user<TAB>default_agent<TAB>allowed_agents_csv<TAB>space
# Delegates to the shared lib's eh_lookup_binding() when available (V-AC-1:
# no duplicated host-match logic); falls back to the embedded Phase-1
# implementation otherwise.
lookup_binding() {
    local root="$1"
    if [ "$EH_LIB_AVAILABLE" -eq 1 ]; then
        eh_lookup_binding "$root" "$MAP_PATH"
        return $?
    fi
    [ -f "$MAP_PATH" ] || return 1
    command -v yq >/dev/null 2>&1 || return 1
    local n
    n=$(yq e '.bindings | length' "$MAP_PATH" 2>/dev/null || echo 0)
    [ "$n" -gt 0 ] 2>/dev/null || return 1
    local i=0
    while [ "$i" -lt "$n" ]; do
        local ws
        ws=$(yq e ".bindings[$i].workspace" "$MAP_PATH" 2>/dev/null || true)
        if [ "$ws" = "$root" ]; then
            local host aliases ip user agent allowed space
            host=$(yq e ".bindings[$i].required_host" "$MAP_PATH")
            aliases=$(yq e ".bindings[$i].host_aliases | join(\",\")" "$MAP_PATH")
            ip=$(yq e ".bindings[$i].tailscale_ip" "$MAP_PATH")
            user=$(yq e ".bindings[$i].ssh_user" "$MAP_PATH")
            agent=$(yq e ".bindings[$i].default_agent" "$MAP_PATH")
            allowed=$(yq e ".bindings[$i].allowed_agents | join(\",\")" "$MAP_PATH")
            space=$(yq e ".bindings[$i].space" "$MAP_PATH")
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$host" "$aliases" "$ip" "$user" "$agent" "$allowed" "$space"
            return 0
        fi
        i=$((i + 1))
    done
    return 1
}

# --- is this Bash command an executional Datarim invocation? -----------
# Command-position matching (DEF-1, QA TUNE-0471): a bare substring match on
# "claude "/"codex "/"/dr-" false-denies read-only commands whose ARGUMENTS
# happen to contain those words (e.g. `rg claude datarim/`, `grep -r codex .`).
# Instead, split the command into segments on the shell control operators
# |, ;, &&, ||, and for each segment inspect only its first word (the command
# itself) — never the argument list.
#
# Per-segment checks:
#   - Skip leading VAR=value env-assignment tokens (e.g. `VAR=1 claude`).
#   - Match the resolved token against `claude`/`codex` by basename, so an
#     absolute/relative path (`/opt/homebrew/bin/claude`) still matches.
#   - Separately, match a `/dr-<word>` token appearing as the FIRST word of a
#     segment (a slash-command invoked directly) OR as an argument to a
#     claude/codex invocation in that same segment (e.g. `claude /dr-do X`,
#     `codex /dr-plan Y`) — never a `/dr-` substring buried in unrelated
#     arguments of a non-agent command.
# Strip heredoc bodies from a command before command-position analysis.
# (DEF-1h, QA TUNE-0474): a Bash call that writes a document via a heredoc
# (`cat > f <<EOF ... EOF`) carries the document TEXT inside .tool_input.command.
# If that text contains a line that begins with `/dr-<word>` (or `claude`/
# `codex`) — e.g. a CTA snippet «run /dr-archive TASK» in a snapshot file —
# the segmenter below would treat that prose line as a command segment and
# false-deny. Heredoc bodies are data, never command-position tokens, so we
# remove them first. Recognises `<<WORD`, `<<-WORD`, `<<'WORD'`, `<<"WORD"`
# (bash strips the quotes/`-` from the closing delimiter match; `<<-` also
# allows leading tabs on the terminator). We drop everything from the line
# AFTER the heredoc operator up to and including the terminator line.
strip_heredoc_bodies() {
    local cmd="$1"
    printf '%s' "$cmd" | awk '
        # Not currently inside a heredoc: look for an opener on this line.
        !inh {
            line = $0
            # Extract the delimiter word of the LAST heredoc opener on the line
            # (bash processes multiple `<<A <<B` in order; for guard purposes a
            # single active body strip is sufficient — nested/stacked heredocs
            # in one command are not a realistic guard input, and stripping the
            # first-opened body already removes the prose that causes false-deny).
            if (match(line, /<<-?[ \t]*/)) {
                rest = substr(line, RSTART + RLENGTH)
                # rest starts at the delimiter token (optionally quoted).
                q = substr(rest, 1, 1)
                if (q == "\"" || q == "'\''") {
                    # quoted delimiter: WORD is up to the matching quote
                    d = rest; sub(/^./, "", d)          # drop opening quote
                    delim = d; sub(/["'\''].*$/, "", delim)
                } else {
                    delim = rest; sub(/[^A-Za-z0-9_].*$/, "", delim)
                }
                if (delim != "") {
                    print line          # keep the opener line (its command-position token is real)
                    inh = 1
                    term = delim
                    next
                }
            }
            print line
            next
        }
        # Inside a heredoc body: drop lines until the terminator.
        inh {
            t = $0
            gsub(/^[ \t]+/, "", t)      # `<<-` allows leading tabs on terminator
            if (t == term) { inh = 0 }  # terminator consumed (and dropped)
            next                        # drop every body line and the terminator
        }
    '
}

# Strip quoted string-literal bodies before command-position analysis.
# (DEF-1m, TUNE-0486 — sibling class to the heredoc strip): a Bash call with a
# multi-line quoted argument (`git commit -m "TUNE-0474 fix\n\n/dr-archive was
# denied..."`) carries prose INSIDE the quotes. The segmenter below splits on
# shell control operators AND the `while read` over segments treats each input
# line as its own segment — so a body line that begins with `/dr-<word>` (or
# `claude`/`codex`) becomes a false command-position token and false-denies.
# Quoted string-literal contents are argument DATA, never command-position, so
# we collapse every '...' / "..." body to a single placeholder token `Q`
# (removing internal newlines and operators) before segmentation. A real
# chained command OUTSIDE the quotes (`... && claude /dr-do X`) is untouched.
# Bash quoting rules honoured: single-quote `'...'` has no escapes (literal to
# the next `'`); double-quote `"..."` honours `\"`/`\\` escapes.
strip_quoted_bodies() {
    printf '%s' "$1" | awk '
    { buf = buf (NR > 1 ? "\n" : "") $0 }
    END {
        SQ = sprintf("%c", 39); DQ = "\""; BS = "\\"
        n = length(buf); st = "NONE"; out = ""
        for (i = 1; i <= n; i++) {
            c = substr(buf, i, 1)
            if (st == "NONE") {
                if (c == SQ)      { st = "SQ"; out = out SQ "Q" SQ }   # open single → emit '"'"'Q'"'"'
                else if (c == DQ) { st = "DQ"; out = out DQ "Q" DQ }   # open double → emit "Q"
                else out = out c
            } else if (st == "SQ") {
                if (c == SQ) st = "NONE"                                # close single (no escapes)
            } else if (st == "DQ") {
                if (c == BS) { i++ }                                    # skip escaped char (\" \\ ...)
                else if (c == DQ) st = "NONE"                           # close double
            }
        }
        printf "%s", out
    }'
}

is_executional_command() {
    local cmd="$1"
    # Remove heredoc bodies first (DEF-1h): their document text is data, not
    # command-position tokens (QA TUNE-0474).
    cmd="$(strip_heredoc_bodies "$cmd")"
    # Then collapse quoted string-literal bodies (DEF-1m, TUNE-0486): a
    # multi-line `-m "..."` message must not surface prose lines as segments.
    cmd="$(strip_quoted_bodies "$cmd")"
    # Split on shell control operators into segments; inspect each segment's
    # command-position token independently. sed normalizes multi-char
    # operators (&&, ||) and single-char (|, ;) to newlines.
    local segments
    segments=$(printf '%s' "$cmd" | sed -E 's/(&&|\|\||[|;])/\n/g')

    local seg
    while IFS= read -r seg; do
        # Tokenize the segment (word-splitting is intentional here — we only
        # need positional tokens, not full shell semantics).
        # shellcheck disable=SC2206
        local tokens=($seg)
        [ "${#tokens[@]}" -gt 0 ] || continue

        # Skip leading VAR=value env-assignment tokens to find the real
        # command-position token.
        local idx=0
        while [ "$idx" -lt "${#tokens[@]}" ]; do
            case "${tokens[$idx]}" in
                [A-Za-z_][A-Za-z0-9_]*=*) idx=$((idx + 1)) ;;
                *) break ;;
            esac
        done
        [ "$idx" -lt "${#tokens[@]}" ] || continue

        local first_tok="${tokens[$idx]}"
        local first_base
        first_base="$(basename "$first_tok" 2>/dev/null || printf '%s' "$first_tok")"

        # Direct slash-command invocation at segment start.
        case "$first_tok" in
            /dr-[a-z]*) return 0 ;;
        esac

        # Direct claude/codex invocation (by basename, so absolute paths match).
        if [ "$first_base" = "claude" ] || [ "$first_base" = "codex" ]; then
            return 0
        fi
    done <<< "$segments"

    return 1
}

is_doctor_invocation() {
    local cmd="$1"
    case "$cmd" in
        *datarim-doctor.sh*|*"/dr-doctor"*) return 0 ;;
    esac
    return 1
}

is_dispatch_invocation() {
    local cmd="$1"
    case "$cmd" in
        *datarim-dispatch.sh*) return 0 ;;
    esac
    return 1
}

input=$(cat)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty')
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')

if [ "$event" = "SessionStart" ] || [ -z "$tool" ]; then
    exit 0
fi

case "$tool" in
    Bash|shell|exec_command) ;;
    *) exit 0 ;;
esac

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -n "$cmd" ] || exit 0

session_cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -n "$session_cwd" ] || session_cwd="$PWD"

# The dispatch channel itself is never gated (T3 anti-obstruction).
if is_dispatch_invocation "$cmd"; then
    exit 0
fi

# Repair-class exemption checked BEFORE the executional-command filter: a
# doctor invocation may not match the /dr-*|claude|codex shape (e.g. a bare
# `bash .../datarim-doctor.sh --fix`) but must still be resolved against the
# workspace binding to emit the audit-log line (operator amendment
# 2026-07-12: /dr-doctor works locally regardless of invocation shape).
doctor_call=0
if is_doctor_invocation "$cmd"; then
    doctor_call=1
fi

if [ "$doctor_call" -eq 0 ]; then
    is_executional_command "$cmd" || exit 0
fi

root="$(resolve_datarim_root "$session_cwd" 2>/dev/null || true)"
[ -n "$root" ] || exit 0

binding="$(lookup_binding "$root" 2>/dev/null || true)"
[ -n "$binding" ] || exit 0

IFS=$'\t' read -r req_host aliases ip user default_agent allowed_agents space <<< "$binding"

if [ "$doctor_call" -eq 1 ]; then
    audit_log "allowed-doctor-local" "$root" "$req_host" "n/a"
    exit 0
fi

# Operator override marker: datarim/.exec-local-override
if [ -f "$root/datarim/.exec-local-override" ]; then
    audit_log "allowed-override" "$root" "$req_host" "n/a"
    exit 0
fi

reason="Datarim execution для этого workspace ($space) привязан к $req_host ($ip, ssh $user@). Локальное исполнение на этой машине запрещено (TUNE-0471). Делегируй: dev-tools/datarim-dispatch.sh --workspace $root --task <TASK-ID> [--agent <${default_agent}|...>] (default_agent=${default_agent}; allowed: ${allowed_agents})."
audit_log "denied" "$root" "$req_host" "$default_agent"
emit_deny "$reason"
exit 0
