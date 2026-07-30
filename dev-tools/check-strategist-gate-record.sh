#!/usr/bin/env bash
# Validate a parent-normalized /dr-plan strategist gate record.
# This helper is deliberately structural: it does not classify prose, invoke
# agents, write records, select routes, or open evidence paths.

set -euo pipefail
IFS=$' \t\n'

usage() {
    cat <<'EOF'
Usage: check-strategist-gate-record.sh \
  --root <workspace-root> \
  --record datarim/.auto/strategist-gate/<task>/<invocation>.record \
  --task <task-id> \
  --complexity L1|L2|L3|L4 \
  --invocation <invocation-id> \
  --scope-digest <sha256>

Exit 0: advancing or normal-route record
Exit 1: valid non-advancing record
Exit 2: malformed or untrusted record
Exit 64: command-line misuse
EOF
}

usage_error() {
    printf 'check-strategist-gate-record: %s\n' "$1" >&2
    exit 64
}

malformed() {
    printf 'check-strategist-gate-record: %s\n' "$1" >&2
    exit 2
}

stat_follow() {
    target=$1
    if stat -Lc '%d:%i:%u:%a:%s:%Y' "$target" >/dev/null 2>&1; then
        stat -Lc '%d:%i:%u:%a:%s:%Y' "$target" 2>/dev/null
        return
    fi
    stat -Lf '%d:%i:%u:%Lp:%z:%m' "$target" 2>/dev/null
}

emit_result() {
    printf 'result=%s\nreason=%s\n' "$1" "$2"
}

ROOT=
RECORD_REL=
TASK=
COMPLEXITY=
INVOCATION=
SCOPE_DIGEST=

while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --root|--record|--task|--complexity|--invocation|--scope-digest)
            flag=$1
            shift
            [ "$#" -gt 0 ] || usage_error "$flag requires a value"
            case "$flag" in
                --root) ROOT=$1 ;;
                --record) RECORD_REL=$1 ;;
                --task) TASK=$1 ;;
                --complexity) COMPLEXITY=$1 ;;
                --invocation) INVOCATION=$1 ;;
                --scope-digest) SCOPE_DIGEST=$1 ;;
            esac
            shift
            ;;
        *) usage_error 'unknown flag' ;;
    esac
done

[ -n "$ROOT" ] || usage_error 'missing --root'
[ -n "$RECORD_REL" ] || usage_error 'missing --record'
[ -n "$TASK" ] || usage_error 'missing --task'
[ -n "$COMPLEXITY" ] || usage_error 'missing --complexity'
[ -n "$INVOCATION" ] || usage_error 'missing --invocation'
[ -n "$SCOPE_DIGEST" ] || usage_error 'missing --scope-digest'

LC_ALL=C
export LC_ALL
[ "${#TASK}" -le 96 ] || usage_error 'invalid task id'
printf '%s' "$TASK" | grep -Eq '^[A-Z][A-Z0-9]{1,9}-[0-9]{4,}(-[A-Za-z0-9][A-Za-z0-9-]{0,63})?$' \
    || usage_error 'invalid task id'
[ "${#INVOCATION}" -le 96 ] || usage_error 'invalid invocation id'
printf '%s' "$INVOCATION" | grep -Eq '^[a-z0-9][A-Za-z0-9._-]{0,95}$' \
    || usage_error 'invalid invocation id'
case "$COMPLEXITY" in L1|L2|L3|L4) ;; *) usage_error 'invalid complexity' ;; esac
printf '%s' "$SCOPE_DIGEST" | grep -Eq '^[a-f0-9]{64}$' \
    || usage_error 'invalid scope digest'
case "$ROOT" in /*) ;; *) usage_error 'root must be absolute' ;; esac
[ -d "$ROOT" ] || usage_error 'root is not a directory'
[ ! -L "$ROOT" ] || malformed 'workspace root is a symlink'

ROOT_PHYSICAL=$(cd -P "$ROOT" 2>/dev/null && pwd -P) \
    || usage_error 'cannot resolve workspace root'
[ "$ROOT_PHYSICAL" = "${ROOT%/}" ] || malformed 'workspace root is not canonical'

EXPECTED_REL="datarim/.auto/strategist-gate/$TASK/$INVOCATION.record"
[ "$RECORD_REL" = "$EXPECTED_REL" ] || malformed 'record path binding mismatch'

DATARIM_DIR="$ROOT_PHYSICAL/datarim"
AUTO_DIR="$DATARIM_DIR/.auto"
GATE_DIR="$AUTO_DIR/strategist-gate"
TASK_DIR="$GATE_DIR/$TASK"
RECORD_ABS="$ROOT_PHYSICAL/$RECORD_REL"

for component in "$DATARIM_DIR" "$AUTO_DIR" "$GATE_DIR" "$TASK_DIR"; do
    [ -e "$component" ] || malformed 'required record parent is missing'
    [ ! -L "$component" ] || malformed 'symlinked path component'
    [ -d "$component" ] || malformed 'record parent is not a directory'
done

TASK_PHYSICAL=$(cd -P "$TASK_DIR" 2>/dev/null && pwd -P) \
    || malformed 'cannot resolve task directory'
[ "$TASK_PHYSICAL" = "$TASK_DIR" ] || malformed 'task directory escaped root'

CURRENT_UID=$(id -u) || malformed 'cannot determine current uid'
TASK_META_BEFORE=$(stat_follow "$TASK_DIR") || malformed 'cannot stat task directory'
IFS=: read -r _ _ task_uid task_mode _ _ <<EOF
$TASK_META_BEFORE
EOF
[ -n "$task_mode" ] || malformed 'invalid task directory metadata'
[ "$task_uid" = "$CURRENT_UID" ] || malformed 'task directory owner mismatch'
[ "$task_mode" = 700 ] || malformed 'task directory mode mismatch'

[ -e "$RECORD_ABS" ] || malformed 'record is missing'
[ ! -L "$RECORD_ABS" ] || malformed 'record is a symlink'
[ -f "$RECORD_ABS" ] || malformed 'record is not regular'
RECORD_META_PATH=$(stat_follow "$RECORD_ABS") || malformed 'cannot stat record'
IFS=: read -r _ _ record_uid record_mode record_size _ <<EOF
$RECORD_META_PATH
EOF
[ -n "$record_mode" ] || malformed 'invalid record metadata'
[ "$record_uid" = "$CURRENT_UID" ] || malformed 'record owner mismatch'
[ "$record_mode" = 600 ] || malformed 'record mode mismatch'

exec 3<"$RECORD_ABS" || malformed 'cannot open record'
FD_PATH="/proc/$$/fd/3"
[ -e "$FD_PATH" ] || FD_PATH="/dev/fd/3"
RECORD_META_FD_BEFORE=$(stat_follow "$FD_PATH") || malformed 'cannot stat record descriptor'
[ "$RECORD_META_FD_BEFORE" = "$RECORD_META_PATH" ] \
    || malformed 'record changed before descriptor open'
TASK_META_OPEN=$(stat_follow "$TASK_DIR") || malformed 'cannot restat task directory'
[ "$TASK_META_OPEN" = "$TASK_META_BEFORE" ] || malformed 'task directory changed before record open'

schema_version=__UNSET__
task_id=__UNSET__
invocation_id=__UNSET__
scope_digest=__UNSET__
complexity=__UNSET__
classification=__UNSET__
positive_scope_test=__UNSET__
no_new_behavior_test=__UNSET__
scope_evidence=__UNSET__
invocation_reason=__UNSET__
strategist_invoked=__UNSET__
verdict=__UNSET__
worth_building=__UNSET__
rationale=__UNSET__
most_efficient_path=__UNSET__
safety_assessment=__UNSET__
gate_status=__UNSET__
route=__UNSET__
seen='|'
line_count=0
parsed_bytes=0
last_line_had_newline=0

while :; do
    line=
    if IFS= read -r line <&3; then
        line_had_newline=1
    else
        [ -n "$line" ] || break
        line_had_newline=0
    fi
    line_count=$((line_count + 1))
    parsed_bytes=$((parsed_bytes + ${#line} + line_had_newline))
    last_line_had_newline=$line_had_newline
    [ "$line_count" -le 18 ] || malformed 'unexpected or duplicate key'
    printf '%s' "$line" | grep -q '[^ -~]' && malformed 'record contains non-ascii or control bytes'
    case "$line" in *=*) ;; *) malformed 'record line is not key=value' ;; esac
    key=${line%%=*}
    value=${line#*=}
    [ -n "$key" ] || malformed 'empty record key'
    [ "${#value}" -le 500 ] || malformed 'record value exceeds 500 bytes'
    case "$seen" in *"|$key|"*) malformed 'duplicate record key' ;; esac
    seen="${seen}${key}|"
    case "$key" in
        schema_version) schema_version=$value ;;
        task_id) task_id=$value ;;
        invocation_id) invocation_id=$value ;;
        scope_digest) scope_digest=$value ;;
        complexity) complexity=$value ;;
        classification) classification=$value ;;
        positive_scope_test) positive_scope_test=$value ;;
        no_new_behavior_test) no_new_behavior_test=$value ;;
        scope_evidence) scope_evidence=$value ;;
        invocation_reason) invocation_reason=$value ;;
        strategist_invoked) strategist_invoked=$value ;;
        verdict) verdict=$value ;;
        worth_building) worth_building=$value ;;
        rationale) rationale=$value ;;
        most_efficient_path) most_efficient_path=$value ;;
        safety_assessment) safety_assessment=$value ;;
        gate_status) gate_status=$value ;;
        route) route=$value ;;
        *) malformed 'unknown record key' ;;
    esac
done
RECORD_META_FD_AFTER=$(stat_follow "$FD_PATH") || malformed 'cannot restat record descriptor'
exec 3<&-

[ "$line_count" -eq 18 ] || malformed 'record is missing required keys'
[ "$parsed_bytes" -eq "$record_size" ] || malformed 'record contains NUL bytes'
[ "$last_line_had_newline" -eq 1 ] || malformed 'record lacks a final newline'
[ "$RECORD_META_FD_AFTER" = "$RECORD_META_FD_BEFORE" ] \
    || malformed 'record descriptor changed during validation'
RECORD_META_PATH_AFTER=$(stat_follow "$RECORD_ABS") || malformed 'record path disappeared during validation'
[ ! -L "$RECORD_ABS" ] || malformed 'record path became a symlink'
[ "$RECORD_META_PATH_AFTER" = "$RECORD_META_FD_AFTER" ] \
    || malformed 'record path changed during validation'
TASK_META_AFTER=$(stat_follow "$TASK_DIR") || malformed 'task directory disappeared during validation'
[ "$TASK_META_AFTER" = "$TASK_META_BEFORE" ] || malformed 'task directory changed during validation'
for component in "$DATARIM_DIR" "$AUTO_DIR" "$GATE_DIR" "$TASK_DIR"; do
    [ ! -L "$component" ] || malformed 'path component changed to a symlink'
    [ -d "$component" ] || malformed 'record parent changed type'
done
TASK_PHYSICAL_AFTER=$(cd -P "$TASK_DIR" 2>/dev/null && pwd -P) \
    || malformed 'cannot re-resolve task directory'
[ "$TASK_PHYSICAL_AFTER" = "$TASK_PHYSICAL" ] || malformed 'task directory escaped during validation'

[ "$schema_version" = 1 ] || malformed 'schema version mismatch'
[ "$task_id" = "$TASK" ] || malformed 'task binding mismatch'
[ "$invocation_id" = "$INVOCATION" ] || malformed 'invocation binding mismatch'
[ "$scope_digest" = "$SCOPE_DIGEST" ] || malformed 'scope digest binding mismatch'
[ "$complexity" = "$COMPLEXITY" ] || malformed 'complexity binding mismatch'
case "$classification" in redundancy_only|non_matching|ambiguous) ;; *) malformed 'invalid classification' ;; esac
case "$positive_scope_test" in pass|fail|unknown) ;; *) malformed 'invalid positive scope result' ;; esac
case "$no_new_behavior_test" in pass|fail|unknown) ;; *) malformed 'invalid no-new-behavior result' ;; esac
case "$invocation_reason" in none|complexity_gate|redundancy_gate|both) ;; *) malformed 'invalid invocation reason' ;; esac
case "$strategist_invoked" in yes|no) ;; *) malformed 'invalid strategist invocation marker' ;; esac
case "$verdict" in GO|NO_GO|PIVOT|NOT_APPLICABLE|INCOMPLETE) ;; *) malformed 'invalid verdict' ;; esac
case "$worth_building" in yes|no|conditional|not_applicable) ;; *) malformed 'invalid worth-building value' ;; esac
case "$gate_status" in pass|block|not_applicable) ;; *) malformed 'invalid gate status' ;; esac
case "$route" in proceed|return_to_prd) ;; *) malformed 'invalid route' ;; esac

if [ -z "$scope_evidence" ] || [ "$scope_evidence" = __UNSET__ ]; then
    malformed 'scope evidence is missing'
fi
case "$scope_evidence" in ,*|*,|*,,*) malformed 'invalid scope evidence list' ;; esac
IFS=, read -r -a evidence_references <<EOF
$scope_evidence
EOF
for reference in "${evidence_references[@]}"; do
    printf '%s' "$reference" | grep -Eq "^datarim/tasks/${TASK}-(init-task|task-description)\\.md:[1-9][0-9]*$|^datarim/prd/PRD-${TASK}\\.md:[1-9][0-9]*$" \
        || malformed 'invalid scope evidence reference'
done

for text_value in "$rationale" "$most_efficient_path" "$safety_assessment"; do
    if [ -z "$text_value" ] || [ "$text_value" = __UNSET__ ]; then
        malformed 'decision text is missing'
    fi
    printf '%s' "$text_value" | grep -Eiq \
        '(secret|password|token|credential)[[:space:]_/-]*[:=]|authorization[[:space:]_/-]*:[[:space:]]*bearer|(^|[^A-Za-z0-9])bearer[[:space:]]+[A-Za-z0-9._-]+|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|-----BEGIN [A-Z ]*PRIVATE KEY-----|api[[:space:]_/-]*key[[:space:]_/-]*[:=]|(^|[^A-Za-z0-9])route[[:space:]_/-]*[:=]|next[[:space:]_/-]*step[[:space:]_/-]*[:=]|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|(^|[^0-9])\+?[0-9][0-9 ()-]{7,}[0-9]' \
        && malformed 'unsafe decision text'
    printf '%s' "$text_value" | grep -Eq '(^|[^A-Za-z0-9_.-])\.\./|(^|[^A-Za-z0-9_.-])/[A-Za-z0-9._/-]|(^|[^A-Za-z0-9_.-])path[[:space:]_/-]*=' \
        && malformed 'unsafe path in decision text'
done

case "$positive_scope_test/$no_new_behavior_test" in
    pass/pass) PREDICATE_CLASS=reductive ;;
    unknown/unknown|unknown/pass|pass/unknown) PREDICATE_CLASS=ambiguous ;;
    fail/fail|fail/pass|fail/unknown|pass/fail|unknown/fail) PREDICATE_CLASS=non_matching ;;
    *) malformed 'invalid predicate pair' ;;
esac
case "$classification/$PREDICATE_CLASS" in
    redundancy_only/reductive|ambiguous/ambiguous|non_matching/non_matching) ;;
    *) malformed 'classification contradicts predicate results' ;;
esac

case "$COMPLEXITY" in
    L1|L2) REQUIRED_REASON=redundancy_gate ;;
    L3|L4) REQUIRED_REASON=both ;;
esac

case "$classification" in
    redundancy_only)
        [ "$invocation_reason" = "$REQUIRED_REASON" ] || malformed 'wrong redundancy invocation reason'
        [ "$strategist_invoked" = yes ] || malformed 'strategist was not invoked'
        case "$verdict/$worth_building/$gate_status/$route" in
            GO/yes/pass/proceed)
                RESULT=advance
                REASON=strategist_go
                EXIT_CODE=0
                ;;
            NO_GO/no/block/return_to_prd)
                RESULT=block
                REASON=strategist_no_go
                EXIT_CODE=1
                ;;
            PIVOT/conditional/block/return_to_prd)
                RESULT=block
                REASON=strategist_pivot
                EXIT_CODE=1
                ;;
            INCOMPLETE/conditional/block/return_to_prd)
                RESULT=block
                REASON=strategist_incomplete
                EXIT_CODE=1
                ;;
            *) malformed 'invalid redundancy decision tuple' ;;
        esac
        [ "$rationale" != not_applicable ] || malformed 'redundancy rationale is missing'
        [ "$most_efficient_path" != not_applicable ] || malformed 'efficient path is missing'
        [ "$safety_assessment" != not_applicable ] || malformed 'safety assessment is missing'
        ;;
    ambiguous)
        [ "$invocation_reason" = "$REQUIRED_REASON" ] || malformed 'wrong ambiguous invocation reason'
        [ "$strategist_invoked" = yes ] || malformed 'strategist was not invoked'
        [ "$verdict/$worth_building/$gate_status/$route" = INCOMPLETE/conditional/block/return_to_prd ] \
            || malformed 'invalid ambiguous decision tuple'
        [ "$rationale" != not_applicable ] || malformed 'ambiguous rationale is missing'
        [ "$most_efficient_path" != not_applicable ] || malformed 'ambiguous path is missing'
        [ "$safety_assessment" != not_applicable ] || malformed 'ambiguous safety assessment is missing'
        RESULT=block
        REASON=scope_ambiguous
        EXIT_CODE=1
        ;;
    non_matching)
        case "$COMPLEXITY:$invocation_reason:$strategist_invoked" in
            L1:none:no|L2:none:no|L1:redundancy_gate:yes|L2:redundancy_gate:yes|L3:complexity_gate:yes|L4:complexity_gate:yes|L3:both:yes|L4:both:yes) ;;
            *) malformed 'invalid non-matching invocation tuple' ;;
        esac
        [ "$verdict/$worth_building/$gate_status/$route" = NOT_APPLICABLE/not_applicable/not_applicable/proceed ] \
            || malformed 'invalid non-matching decision tuple'
        [ "$rationale" = not_applicable ] || malformed 'non-matching rationale must be not_applicable'
        [ "$most_efficient_path" = not_applicable ] || malformed 'non-matching path must be not_applicable'
        [ "$safety_assessment" = not_applicable ] || malformed 'non-matching safety must be not_applicable'
        RESULT=normal_route
        REASON=not_applicable
        EXIT_CODE=0
        ;;
esac

emit_result "$RESULT" "$REASON"
exit "$EXIT_CODE"
