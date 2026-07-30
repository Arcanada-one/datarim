# shellcheck shell=bash
# wizard-state.sh — append-only JSONL state engine for the interactive
# task-spec wizard (TUNE-0390). Sourced library: no shebang, no top-level
# side-effects. Drives the /dr-wizard interview (discovery + consilium
# composition); the arcana CLI/TUI carrier is ARAS-0028, the Munera graph
# sink is MUN-0036.
#
# State model. Two append-only JSONL artefacts per task, under the gitignored
# runtime tree resolved from --root:
#   <root>/datarim/wizard/<TASK-ID>.wizard.jsonl   — interview event log
#   <root>/datarim/wizard/<TASK-ID>.graph.jsonl    — knowledge/dependency graph
# Current state is a PROJECTION (fold) over events — resume = replay, branching
# = a derived drill-stack. Every event carries "v" (schema_version) and a
# monotonic "seq". Drill context is captured as qid REFERENCES ("refs"), never a
# copy of the answer text (bounded; resolves at pop). A terminal "finalized"
# event closes the interview; open drill frames are popped as "abandoned".
#
# Public API (each takes a <TASK-ID> and --root <dir>):
#   wizard_init <id>                          create the state file (meta line)
#   wizard_add_question <id> <qid> <cat> <text>
#   wizard_answer <id> <qid> <text>
#   wizard_get_answer <id> <qid>              stdout: latest answer for qid
#   wizard_drill_push <id> <parent-qid> <refs-csv>
#   wizard_drill_pop <id> <conclusion>        writes conclusion back to parent
#   wizard_rescope <id> <research|plan|both> <note>
#   wizard_flags <id>                         stdout: NAME=on|off per set flag
#   wizard_finalize <id>                      pop-all abandoned + finalized event
#   wizard_status <id>                        stdout: status/questions/answered/drill_depth
#   wizard_validate <id>                      exit 0 valid, non-zero on violation
#   wizard_graph_node <id> <node-id> <type> <label>
#   wizard_graph_edge <id> <from> <to> <relation>
#
# Dependency floor: pure bash (3.2+) + awk + grep + sed + date. No jq/yq/python.
#
# Security (Mandate S1/S5/S9): every scalar is untrusted.
#   - S9 injection: text values escape \ then " then TAB; LF/CR/other C0/DEL
#     are rejected (preserves one-line-per-record). qid/node-id allowlist
#     ^[A-Za-z0-9_-]+$; category slug ^[a-z][a-z0-9_-]*$; type/relation/flag
#     closed enums.
#   - S5 path: TASK-ID must match ^[A-Z]{2,10}-[0-9]{4}$ (rejects .. / and
#     leading dash); target must be a real file, never a symlink; append under
#     an mkdir-lock (>> is atomic only <= PIPE_BUF).
#   - S1 redaction: graph.jsonl flows OUTBOUND to Munera/LTM — node labels are
#     redacted (token shapes, Bearer, PRIVATE KEY, user:pass@host, home paths,
#     RFC1918) before write. The local wizard.jsonl keeps raw interview text.

# ---- input gates --------------------------------------------------------

_wz_valid_id() {  # $1=id → ^[A-Za-z0-9_-]+$
    [ -n "$1" ] || return 1
    printf '%s' "$1" | grep -Eq '^[A-Za-z0-9_-]+$'
}

_wz_valid_taskid() {  # $1=task-id → ^[A-Z]{2,10}-[0-9]{4}$ (also the path gate)
    printf '%s' "$1" | grep -Eq '^[A-Z]{2,10}-[0-9]{4}$'
}

_wz_valid_slug() {  # $1=category → ^[a-z][a-z0-9_-]*$
    printf '%s' "$1" | grep -Eq '^[a-z][a-z0-9_-]*$'
}

# Reject LF/CR and any C0 control or DEL EXCEPT TAB (tab is escaped, not rejected).
_wz_reject_ctrl() {  # $1=value → return 1 if it carries a forbidden control byte
    case "$1" in *$'\n'*|*$'\r'*) return 1 ;; esac
    local stripped
    stripped=$(printf '%s' "$1" | tr -d '\011')   # drop TAB, then any remaining ctrl is illegal
    printf '%s' "$stripped" | LC_ALL=C grep -q '[[:cntrl:]]' && return 1
    return 0
}

# Escape the JSON-string-breaking chars. Order matters: backslash first.
_wz_json_escape() {  # $1=value → stdout escaped
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

# Reverse of _wz_json_escape for projection reads (get_answer).
_wz_json_unescape() {  # stdin → stdout
    sed -e 's/\\t/\t/g' -e 's/\\"/"/g' -e 's/\\\\/\\/g'
}

# Redact common secret shapes before a label crosses the graph-sink boundary.
_wz_redact() {  # $1=value → stdout redacted
    printf '%s' "$1" | sed -E \
        -e 's/sk-[A-Za-z0-9_]{6,}/[REDACTED]/g' \
        -e 's/ghp_[A-Za-z0-9]{6,}/[REDACTED]/g' \
        -e 's/AKIA[0-9A-Z]{8,}/[REDACTED]/g' \
        -e 's/[Bb]earer +[A-Za-z0-9._~+/-]+=*/[REDACTED]/g' \
        -e 's/-----BEGIN[A-Z ]*PRIVATE KEY-----/[REDACTED]/g' \
        -e 's#[A-Za-z0-9._%+-]+:[^@ /]+@[A-Za-z0-9.-]+#[REDACTED]#g' \
        -e 's#/(home|Users)/[A-Za-z0-9._/-]+#[REDACTED]#g' \
        -e 's/(10|192\.168|172\.(1[6-9]|2[0-9]|3[01]))(\.[0-9]{1,3})+/[REDACTED]/g'
}

# ---- path resolution ----------------------------------------------------

# Resolve <root>/datarim/wizard/<TASK-ID>.<suffix>.jsonl with S5 containment.
_wz_resolve_path() {  # $1=task-id $2=root $3=suffix(wizard|graph) → stdout path
    local task="$1" root="$2" suffix="$3"
    _wz_valid_taskid "$task" || return 1
    case "$suffix" in wizard|graph) ;; *) return 1 ;; esac
    [ -n "$root" ] || root="$PWD"
    local dir="$root/datarim/wizard"
    mkdir -p "$dir" 2>/dev/null || return 1
    # pwd -P resolves any symlink in the directory prefix (portable, no realpath -m).
    local rdir; rdir=$(cd "$dir" 2>/dev/null && pwd -P) || return 1
    local f="$rdir/$task.$suffix.jsonl"
    # Refuse a pre-planted symlink at the target (shared-workspace attack).
    [ -L "$f" ] && return 1
    printf '%s' "$f"
}

# ---- projection helpers -------------------------------------------------

_wz_next_seq() {  # $1=file → next monotonic seq (0 for empty/missing)
    local f="$1" max
    [ -f "$f" ] || { printf 0; return; }
    max=$(grep -oE '"seq":[0-9]+' "$f" | grep -oE '[0-9]+$' | sort -n | tail -1)
    [ -n "$max" ] || { printf 0; return; }
    printf '%s' "$((max + 1))"
}

_wz_drill_depth() {  # $1=file → pushes - pops
    local f="$1" p q
    [ -f "$f" ] || { printf 0; return; }
    p=$(grep -c '"kind":"drill_push"' "$f"); q=$(grep -c '"kind":"drill_pop"' "$f")
    printf '%s' "$((p - q))"
}

_wz_open_parent() {  # $1=file → parent qid of the most recent unmatched push
    local f="$1" line parent; local stack=()
    [ -f "$f" ] || return 0
    while IFS= read -r line; do
        case "$line" in
            *'"kind":"drill_push"'*)
                parent=$(printf '%s' "$line" | sed -E 's/.*"parent":"([^"]*)".*/\1/')
                stack[${#stack[@]}]="$parent" ;;
            *'"kind":"drill_pop"'*)
                [ ${#stack[@]} -gt 0 ] && unset 'stack[${#stack[@]}-1]' ;;
        esac
    done < "$f"
    [ ${#stack[@]} -gt 0 ] && printf '%s' "${stack[${#stack[@]}-1]}"
    return 0
}

# ---- atomic append ------------------------------------------------------

# Serialize seq assignment + append under an mkdir-lock. $3 = trailing JSON
# fields (already-escaped, leading comma), e.g. ',"qid":"q1","text":"..."'.
_wz_append() {  # $1=file $2=kind $3=rest
    local f="$1" kind="$2" rest="$3"
    local lock="${f}.lock" i=0
    until mkdir "$lock" 2>/dev/null; do
        i=$((i + 1)); [ "$i" -ge 50 ] && { echo "wizard: lock timeout" >&2; return 2; }
        sleep 0.1
    done
    local seq ts
    seq=$(_wz_next_seq "$f")
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '{"v":1,"seq":%s,"kind":"%s","ts":"%s"%s}\n' "$seq" "$kind" "$ts" "$rest" >> "$f"
    rmdir "$lock" 2>/dev/null
    return 0
}

# ---- argument parsing ---------------------------------------------------

# Extract --root into _WZ_ROOT and leave positionals in the _WZ_POS array.
_wz_parse() {
    _WZ_ROOT=""; _WZ_POS=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --root) _WZ_ROOT="$2"; shift 2 ;;
            *) _WZ_POS[${#_WZ_POS[@]}]="$1"; shift ;;
        esac
    done
}

# ---- public API: interview ----------------------------------------------

wizard_init() {
    _wz_parse "$@"; local task="${_WZ_POS[0]:-}"
    local f; f=$(_wz_resolve_path "$task" "$_WZ_ROOT" wizard) || return 1
    [ -f "$f" ] && return 0
    _wz_append "$f" meta ",\"task_id\":\"$task\""
}

wizard_add_question() {
    _wz_parse "$@"
    local task="${_WZ_POS[0]:-}" qid="${_WZ_POS[1]:-}" cat="${_WZ_POS[2]:-}" text="${_WZ_POS[3]:-}"
    _wz_valid_id "$qid" || { echo "wizard: invalid qid" >&2; return 2; }
    _wz_valid_slug "$cat" || { echo "wizard: invalid category" >&2; return 2; }
    _wz_reject_ctrl "$text" || { echo "wizard: text rejected (control char)" >&2; return 2; }
    local f; f=$(_wz_resolve_path "$task" "$_WZ_ROOT" wizard) || return 1
    local et; et=$(_wz_json_escape "$text")
    _wz_append "$f" question ",\"qid\":\"$qid\",\"category\":\"$cat\",\"text\":\"$et\""
}

wizard_answer() {
    _wz_parse "$@"
    local task="${_WZ_POS[0]:-}" qid="${_WZ_POS[1]:-}" text="${_WZ_POS[2]:-}"
    _wz_valid_id "$qid" || { echo "wizard: invalid qid" >&2; return 2; }
    _wz_reject_ctrl "$text" || { echo "wizard: text rejected (control char)" >&2; return 2; }
    local f; f=$(_wz_resolve_path "$task" "$_WZ_ROOT" wizard) || return 1
    local et; et=$(_wz_json_escape "$text")
    _wz_append "$f" answer ",\"qid\":\"$qid\",\"text\":\"$et\""
}

wizard_get_answer() {
    _wz_parse "$@"
    local task="${_WZ_POS[0]:-}" qid="${_WZ_POS[1]:-}"
    local f; f=$(_wz_resolve_path "$task" "$_WZ_ROOT" wizard) || return 1
    [ -f "$f" ] || return 1
    local line
    line=$(grep '"kind":"answer"' "$f" | grep "\"qid\":\"$qid\"" | tail -1)
    [ -n "$line" ] || return 1
    printf '%s' "$line" | sed -E 's/.*"text":"(.*)"}$/\1/' | _wz_json_unescape
}

wizard_drill_push() {
    _wz_parse "$@"
    local task="${_WZ_POS[0]:-}" parent="${_WZ_POS[1]:-}" refs_csv="${_WZ_POS[2]:-}"
    _wz_valid_id "$parent" || { echo "wizard: invalid parent qid" >&2; return 2; }
    # Build a validated JSON array of qid references (no answer text copied).
    local refs_json="[" first=1 r oldifs="$IFS"
    IFS=','
    for r in $refs_csv; do
        [ -n "$r" ] || continue
        _wz_valid_id "$r" || { IFS="$oldifs"; echo "wizard: invalid ref qid" >&2; return 2; }
        if [ "$first" -eq 1 ]; then refs_json="$refs_json\"$r\""; first=0
        else refs_json="$refs_json,\"$r\""; fi
    done
    IFS="$oldifs"
    refs_json="$refs_json]"
    local f; f=$(_wz_resolve_path "$task" "$_WZ_ROOT" wizard) || return 1
    _wz_append "$f" drill_push ",\"parent\":\"$parent\",\"refs\":$refs_json"
}

wizard_drill_pop() {
    _wz_parse "$@"
    local task="${_WZ_POS[0]:-}" concl="${_WZ_POS[1]:-}"
    _wz_reject_ctrl "$concl" || { echo "wizard: conclusion rejected (control char)" >&2; return 2; }
    local f; f=$(_wz_resolve_path "$task" "$_WZ_ROOT" wizard) || return 1
    local parent; parent=$(_wz_open_parent "$f")
    [ -n "$parent" ] || { echo "wizard: no open drill frame" >&2; return 2; }
    local ec; ec=$(_wz_json_escape "$concl")
    _wz_append "$f" drill_pop ",\"parent\":\"$parent\",\"status\":\"resolved\",\"conclusion\":\"$ec\""
    # Write the conclusion back to the parent question as its answer.
    _wz_append "$f" answer ",\"qid\":\"$parent\",\"text\":\"$ec\""
}

wizard_rescope() {
    _wz_parse "$@"
    local task="${_WZ_POS[0]:-}" kind="${_WZ_POS[1]:-}" note="${_WZ_POS[2]:-}"
    _wz_reject_ctrl "$note" || { echo "wizard: note rejected (control char)" >&2; return 2; }
    local flags
    case "$kind" in
        research) flags="research_dirty" ;;
        plan) flags="plan_dirty" ;;
        both) flags="research_dirty plan_dirty" ;;
        *) echo "wizard: invalid rescope kind" >&2; return 2 ;;
    esac
    local f; f=$(_wz_resolve_path "$task" "$_WZ_ROOT" wizard) || return 1
    local en fl; en=$(_wz_json_escape "$note")
    for fl in $flags; do
        _wz_append "$f" flag ",\"flag\":\"$fl\",\"value\":\"on\",\"note\":\"$en\""
    done
}

wizard_flags() {
    _wz_parse "$@"
    local task="${_WZ_POS[0]:-}"
    local f; f=$(_wz_resolve_path "$task" "$_WZ_ROOT" wizard) || return 1
    [ -f "$f" ] || return 0
    local fl last val
    for fl in research_dirty plan_dirty; do
        last=$(grep '"kind":"flag"' "$f" | grep "\"flag\":\"$fl\"" | tail -1)
        [ -n "$last" ] || continue
        val=$(printf '%s' "$last" | sed -E 's/.*"value":"([^"]*)".*/\1/')
        printf '%s=%s\n' "$fl" "$val"
    done
}

wizard_finalize() {
    _wz_parse "$@"
    local task="${_WZ_POS[0]:-}"
    local f; f=$(_wz_resolve_path "$task" "$_WZ_ROOT" wizard) || return 1
    [ -f "$f" ] || return 1
    # Pop-all open drill frames as abandoned (no conclusion, no write-back).
    local guard=0 parent
    while [ "$(_wz_drill_depth "$f")" -gt 0 ]; do
        parent=$(_wz_open_parent "$f")
        _wz_append "$f" drill_pop ",\"parent\":\"$parent\",\"status\":\"abandoned\",\"conclusion\":\"\""
        guard=$((guard + 1)); [ "$guard" -ge 1000 ] && break
    done
    _wz_append "$f" finalized ""
}

wizard_status() {
    _wz_parse "$@"
    local task="${_WZ_POS[0]:-}"
    local f; f=$(_wz_resolve_path "$task" "$_WZ_ROOT" wizard) || return 1
    [ -f "$f" ] || { echo "wizard: no state" >&2; return 1; }
    local st="active" q a d
    grep -q '"kind":"finalized"' "$f" && st="finalized"
    q=$(grep '"kind":"question"' "$f" | sed -E 's/.*"qid":"([^"]*)".*/\1/' | sort -u | grep -c .)
    a=$(grep '"kind":"answer"' "$f" | sed -E 's/.*"qid":"([^"]*)".*/\1/' | sort -u | grep -c .)
    d=$(_wz_drill_depth "$f")
    printf 'status=%s\nquestions=%s\nanswered=%s\ndrill_depth=%s\n' "$st" "$q" "$a" "$d"
}

# ---- public API: knowledge/dependency graph (MUN-0036 ingestion contract) ----

wizard_graph_node() {
    _wz_parse "$@"
    local task="${_WZ_POS[0]:-}" nid="${_WZ_POS[1]:-}" type="${_WZ_POS[2]:-}" label="${_WZ_POS[3]:-}"
    _wz_valid_id "$nid" || { echo "wizard: invalid node id" >&2; return 2; }
    case "$type" in concept|requirement|decision) ;; *) echo "wizard: invalid node type" >&2; return 2 ;; esac
    _wz_reject_ctrl "$label" || { echo "wizard: label rejected (control char)" >&2; return 2; }
    local f; f=$(_wz_resolve_path "$task" "$_WZ_ROOT" graph) || return 1
    [ -f "$f" ] || _wz_append "$f" meta ",\"task_id\":\"$task\",\"artifact\":\"wizard-graph\""
    # S1: redact BEFORE escaping — the label crosses the outbound sink boundary.
    local rl; rl=$(_wz_redact "$label"); rl=$(_wz_json_escape "$rl")
    _wz_append "$f" node ",\"id\":\"$nid\",\"type\":\"$type\",\"label\":\"$rl\""
}

wizard_graph_edge() {
    _wz_parse "$@"
    local task="${_WZ_POS[0]:-}" from="${_WZ_POS[1]:-}" to="${_WZ_POS[2]:-}" rel="${_WZ_POS[3]:-}"
    _wz_valid_id "$from" || { echo "wizard: invalid from id" >&2; return 2; }
    _wz_valid_id "$to" || { echo "wizard: invalid to id" >&2; return 2; }
    case "$rel" in dependency|refines|resolves) ;; *) echo "wizard: invalid relation" >&2; return 2 ;; esac
    local f; f=$(_wz_resolve_path "$task" "$_WZ_ROOT" graph) || return 1
    [ -f "$f" ] || _wz_append "$f" meta ",\"task_id\":\"$task\",\"artifact\":\"wizard-graph\""
    _wz_append "$f" edge ",\"from\":\"$from\",\"to\":\"$to\",\"relation\":\"$rel\""
}

# ---- public API: integrity ----------------------------------------------

# Graph-file integrity: kinds meta|node|edge, monotonic seq, edges ref nodes.
_wz_validate_graph() {  # $1=graph-file → 0 valid, 1 invalid
    local g="$1" nodes gline gkind gseq gprev=-1 ref
    nodes=$(grep '"kind":"node"' "$g" | sed -E 's/.*"id":"([^"]*)".*/\1/')
    while IFS= read -r gline; do
        [ -n "$gline" ] || continue
        printf '%s' "$gline" | grep -q '"v":1' || { echo "wizard: graph bad schema_version" >&2; return 1; }
        gkind=$(printf '%s' "$gline" | sed -E 's/.*"kind":"([^"]*)".*/\1/')
        gseq=$(printf '%s' "$gline" | sed -E 's/.*"seq":([0-9]+).*/\1/')
        case "$gkind" in meta|node|edge) ;; *) echo "wizard: unknown graph kind '$gkind'" >&2; return 1 ;; esac
        [ "$gseq" -gt "$gprev" ] 2>/dev/null || { echo "wizard: graph non-monotonic seq" >&2; return 1; }
        gprev="$gseq"
        if [ "$gkind" = "edge" ]; then
            for ref in \
                "$(printf '%s' "$gline" | sed -E 's/.*"from":"([^"]*)".*/\1/')" \
                "$(printf '%s' "$gline" | sed -E 's/.*"to":"([^"]*)".*/\1/')"; do
                printf '%s\n' "$nodes" | grep -qx "$ref" || { echo "wizard: edge references unknown node '$ref'" >&2; return 1; }
            done
        fi
    done < "$g"
    return 0
}

wizard_validate() {
    _wz_parse "$@"
    local task="${_WZ_POS[0]:-}"
    local f; f=$(_wz_resolve_path "$task" "$_WZ_ROOT" wizard) || return 1
    [ -f "$f" ] || { echo "wizard: no state" >&2; return 2; }

    local line kind seq prev=-1 depth=0 finalized=0
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        printf '%s' "$line" | grep -q '"v":1' || { echo "wizard: bad/absent schema_version" >&2; return 1; }
        kind=$(printf '%s' "$line" | sed -E 's/.*"kind":"([^"]*)".*/\1/')
        seq=$(printf '%s' "$line" | sed -E 's/.*"seq":([0-9]+).*/\1/')
        case "$kind" in
            meta|question|answer|drill_push|drill_pop|flag|finalized) ;;
            *) echo "wizard: unknown event kind '$kind'" >&2; return 1 ;;
        esac
        [ "$seq" -gt "$prev" ] 2>/dev/null || { echo "wizard: non-monotonic seq" >&2; return 1; }
        prev="$seq"
        case "$kind" in
            drill_push) depth=$((depth + 1)) ;;
            drill_pop) [ "$depth" -gt 0 ] || { echo "wizard: drill_pop without push" >&2; return 1; }; depth=$((depth - 1)) ;;
            finalized) finalized=1 ;;
        esac
    done < "$f"
    if [ "$finalized" -eq 1 ] && [ "$depth" -ne 0 ]; then
        echo "wizard: finalized with $depth open drill frame(s)" >&2; return 1
    fi

    # Graph file (if present): kinds meta|node|edge, monotonic seq, edges ref nodes.
    local g; g=$(_wz_resolve_path "$task" "$_WZ_ROOT" graph 2>/dev/null) || g=""
    if [ -n "$g" ] && [ -f "$g" ]; then
        _wz_validate_graph "$g" || return 1
    fi
    return 0
}
