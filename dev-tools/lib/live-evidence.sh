#!/usr/bin/env bash
# Structured implementation of check-live-evidence.sh; not a separate gate.
# Read-only: verifies case coverage, current content/revision, and stage order.
# Dependencies: python3, jq, git, sha256sum or shasum. Never executes evidence commands.
# Exit 0 STAGE_PASS/preflight receipt; 1 BLOCKED; 2 invocation/runtime error.
set -euo pipefail

summary_mode=0
summary_flag_count=0
for argument in "$@"; do
    if [[ "$argument" == --summary-json ]]; then
        summary_mode=1
        summary_flag_count=$((summary_flag_count + 1))
    fi
done

# Summary streams contain only the fixed JSON object. Any diagnostic produced
# by a nested command is private implementation detail and must not escape.
if [[ "$summary_mode" == 1 ]]; then
    exec 2>/dev/null
fi

summary_task_binding=NOT_MEASURED
summary_input_binding=NOT_MEASURED
summary_revision_available=0
summary_revision_value=''
summary_criteria_available=0 summary_criteria_value=''
summary_cases_available=0 summary_cases_value=''
summary_due_available=0 summary_due_value=''
summary_pending_available=0 summary_pending_value=''
summary_validated_available=0 summary_validated_value=''

summary_count_json() {
    local available=$1 value=$2
    if [[ "$available" == 1 && "$value" =~ ^[0-9]+$ ]]; then
        printf '{"availability":"AVAILABLE","value":%s}' "$value"
    else
        printf '{"availability":"NOT_MEASURED","value":null}'
    fi
}

summary_emit() {
    local verdict=$1 reason=$2 exit_code=$3 stage_json=null revision_json
    case "$stage" in
        preflight|snapshot|do|write|edit|publish|qa|compliance|archive|quick)
            stage_json="\"$stage\""
            ;;
    esac
    if [[ "$summary_revision_available" == 1 && "$summary_revision_value" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
        revision_json="{\"availability\":\"AVAILABLE\",\"value\":\"$summary_revision_value\"}"
    else
        revision_json='{"availability":"NOT_MEASURED","value":null}'
    fi
    printf '{"schema":"datarim.live-evidence-summary/v1","verdict":"%s","reason_code":"%s","exit_code":%s,"stage":%s,"identity":{"task_binding":"%s","source_revision":%s,"input_binding":"%s"},"counts":{"criteria_defined":%s,"cases_defined":%s,"cases_due":%s,"cases_validated":%s,"cases_pending":%s}}\n' \
        "$verdict" "$reason" "$exit_code" "$stage_json" \
        "$summary_task_binding" "$revision_json" "$summary_input_binding" \
        "$(summary_count_json "$summary_criteria_available" "$summary_criteria_value")" \
        "$(summary_count_json "$summary_cases_available" "$summary_cases_value")" \
        "$(summary_count_json "$summary_due_available" "$summary_due_value")" \
        "$(summary_count_json "$summary_validated_available" "$summary_validated_value")" \
        "$(summary_count_json "$summary_pending_available" "$summary_pending_value")"
}

summary_block_reason() {
    case "$1" in
        'missing regular contract') printf contract_missing ;;
        'ambiguous or invalid contract JSON') printf contract_json_invalid ;;
        'contract must contain exactly one JSON document') printf contract_document_invalid ;;
        'invalid acceptance contract') printf contract_schema_invalid ;;
        'invalid relative path'|'control character in path'|'traversal in path'|'symlink in evidence scope'|'invalid task binding path'|'scope path is not a regular file'|'invalid evidence artifact path') printf unsafe_path ;;
        'canonical task description missing') printf task_description_missing ;;
        'invalid canonical task metadata') printf task_metadata_invalid ;;
        'task identity, complexity, or type mismatch') printf task_identity_mismatch ;;
        'invalid scope') printf scope_invalid ;;
        'invalid input manifest'|'input path is not a regular file'|'invalid input kind') printf input_manifest_invalid ;;
        'contract changed during verification') printf contract_changed ;;
        'missing regular evidence bundle') printf evidence_missing ;;
        'ambiguous or invalid evidence JSON') printf evidence_json_invalid ;;
        'evidence must contain exactly one JSON document') printf evidence_document_invalid ;;
        'evidence coverage, freshness, or stage order failed') printf evidence_validation_failed ;;
        'evidence artifact missing') printf evidence_artifact_missing ;;
        'evidence artifact hash mismatch') printf evidence_artifact_hash_mismatch ;;
        'evidence changed during verification') printf evidence_changed ;;
        'task metadata changed during verification') printf task_description_changed ;;
        'scope changed during verification') printf scope_changed ;;
        'inputs changed during verification') printf inputs_changed ;;
        'revision changed during verification') printf source_revision_changed ;;
        *) printf evidence_validation_failed ;;
    esac
}

block() {
    if [[ "$summary_mode" == 1 ]]; then
        # A nested command substitution must fail silently; its explicit outer
        # boundary owns the single public summary object.
        if (( BASH_SUBSHELL > 0 )); then exit 1; fi
        if [[ "$1" == 'revision changed during verification' ]]; then
            summary_revision_available=0
            summary_revision_value=''
        fi
        summary_emit BLOCKED "$(summary_block_reason "$1")" 1
        exit 1
    fi
    echo "BLOCKED: $*" >&2
    exit 1
}

usage() {
    local reason=${1:-invalid_arguments}
    if [[ "$summary_mode" == 1 ]]; then
        case "$reason" in
            invalid_arguments|invalid_stage|dependency_unavailable|hash_utility_unavailable|repository_root_invalid|legacy_mode_unsupported) ;;
            *) reason=invalid_arguments ;;
        esac
        summary_emit USAGE_ERROR "$reason" 2
        exit 2
    fi
    echo "evidence gate: --contract FILE --evidence FILE --root DIR --stage preflight|snapshot|do|write|edit|publish|qa|compliance|archive|quick" >&2
    exit 2
}

contract='' evidence='' root='' stage=''
if [[ "$summary_mode" == 1 ]]; then
    [[ "$summary_flag_count" == 1 ]] || usage invalid_arguments
    summary_seen=0
    contract_seen=0 evidence_seen=0 root_seen=0 stage_seen=0
    for argument in "$@"; do
        case "$argument" in
            --expectations|--qa-report|--report) usage legacy_mode_unsupported ;;
        esac
    done
    while (($#)); do
        case "$1" in
            --summary-json)
                [[ "$summary_seen" == 0 ]] || usage invalid_arguments
                summary_seen=1
                shift
                ;;
            --contract|--evidence|--root|--stage)
                (($# >= 2)) || usage invalid_arguments
                [[ "$2" != --* ]] || usage invalid_arguments
                case "$1" in
                    --contract)
                        [[ "$contract_seen" == 0 && -n "$2" ]] || usage invalid_arguments
                        contract_seen=1
                        contract=$2
                        ;;
                    --evidence)
                        [[ "$evidence_seen" == 0 && -n "$2" ]] || usage invalid_arguments
                        evidence_seen=1
                        evidence=$2
                        ;;
                    --root)
                        [[ "$root_seen" == 0 && -n "$2" ]] || usage invalid_arguments
                        root_seen=1
                        root=$2
                        ;;
                    --stage)
                        [[ "$stage_seen" == 0 && -n "$2" ]] || usage invalid_arguments
                        stage_seen=1
                        stage=$2
                        ;;
                esac
                shift 2
                ;;
            *) usage invalid_arguments ;;
        esac
    done
    [[ "$summary_seen" == 1 ]] || usage invalid_arguments
    [[ -n "$contract" && -n "$evidence" && -n "$root" ]] || usage invalid_arguments
    [[ -d "$root" ]] || usage repository_root_invalid
    case "$stage" in
        preflight|snapshot|do|write|edit|publish|qa|compliance|archive|quick) ;;
        *) usage invalid_stage ;;
    esac
else
    while (($#)); do
        (($# >= 2)) || usage
        case "$1" in
            --contract) [[ -z "$contract" ]] || usage; contract=$2 ;;
            --evidence) [[ -z "$evidence" ]] || usage; evidence=$2 ;;
            --root) [[ -z "$root" ]] || usage; root=$2 ;;
            --stage) [[ -z "$stage" ]] || usage; stage=$2 ;;
            *) usage ;;
        esac
        shift 2
    done
    [[ -n "$contract" && -n "$evidence" && -d "$root" ]] || usage
    case "$stage" in preflight|snapshot|do|write|edit|publish|qa|compliance|archive|quick) ;; *) usage ;; esac
fi

command -v python3 >/dev/null || usage dependency_unavailable
command -v jq >/dev/null || usage dependency_unavailable
command -v git >/dev/null || usage dependency_unavailable
if command -v sha256sum >/dev/null; then
    hash() { sha256sum | cut -d ' ' -f 1; }
elif command -v shasum >/dev/null; then
    hash() { shasum -a 256 | cut -d ' ' -f 1; }
else
    usage hash_utility_unavailable
fi
# JSON object keys are identities in the acceptance contract. jq normally keeps
# the last duplicate, which could erase an earlier case or failed status.
unique_json_keys() {
    python3 - "$1" <<'PYJSON'
import json
import sys

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result

def invalid_constant(_value):
    raise ValueError("non-JSON constant")

try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        json.load(stream, object_pairs_hook=unique_object, parse_constant=invalid_constant)
except (OSError, UnicodeError, ValueError):
    sys.exit(1)
PYJSON
}

root=$(cd "$root" && pwd -P)
revision=$(git -C "$root" rev-parse --verify HEAD) || usage repository_root_invalid
[[ $(git -C "$root" rev-parse --show-toplevel) == "$root" ]] || usage repository_root_invalid
if [[ "$revision" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
    summary_revision_value=$revision
    summary_revision_available=1
else
    usage repository_root_invalid
fi
[[ -f "$contract" && ! -L "$contract" ]] || block 'missing regular contract'
contract_hash=$(hash < "$contract")
unique_json_keys "$contract" || block 'ambiguous or invalid contract JSON'
jq -se 'length == 1 and (.[0] | type == "object")' "$contract" >/dev/null 2>&1 \
    || block 'contract must contain exactly one JSON document'
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
contract_counts=$(jq -er --arg now "$now" '
    . as $contract |
    (
    def text: type == "string" and test("\\S");
    def stamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$") and (try (. as $original | fromdateiso8601 | todateiso8601 == $original) catch false);
    def ordered($allowed): . as $route | [$allowed[] | . as $s | select($route | index($s))] == $route;
    .workflow.route as $route |
    .version == 1 and (.task_id | text) and (.defined_at | stamp) and .defined_at <= $now
    and (.task_id | test("^[A-Z][A-Z0-9]{1,9}-[0-9]{4}(-[A-Za-z0-9]+)*$"))
    and (.workflow | type == "object")
    and (.workflow.complexity | type == "string" and IN("L1","L2","L3","L4"))
    and (.workflow.task_type | text and (test("[[:cntrl:]]") | not))
    and ($route | type == "array" and length > 0 and length == (unique|length)
        and all(.[]; type == "string" and IN("do","write","edit","publish","qa","compliance","archive","quick")))
    and (if $route == ["quick"] then .workflow.complexity == "L1" else
        $route[-1] == "archive"
        and (if .workflow.task_type == "content" then
            ($route | ordered(["write","edit","publish","qa","compliance","archive"]))
            and any($route[]; IN("write","edit","publish"))
          else $route[0] == "do" and ($route | ordered(["do","qa","compliance","archive"])) end)
        and (if .workflow.complexity | IN("L3","L4") then
            ($route | index("qa") != null and index("compliance") != null) else true end)
        and (if $route | index("compliance") then ($route | index("qa") != null) else true end)
      end)
    and (.scope | type == "array" and length > 0 and length == (unique | length) and all(.[]; text and (test("[[:cntrl:]]") | not)))
    and (if has("inputs") then
        (.inputs | type == "array")
        and all(.inputs[];
            type == "object" and
            (if .kind == "file" then
                (keys == ["kind","path"] and (.path | text and (test("[[:cntrl:]]") | not)))
             elif .kind == "argv" then
                (keys == ["kind","name","sha256"] and (.name | text and (test("[[:cntrl:]]") | not))
                 and (.sha256 | type == "string" and test("^[0-9a-f]{64}$")))
             elif .kind == "env" then
                (keys == ["kind","name","sha256","synthetic"]
                 and (.name | text and (test("[[:cntrl:]]") | not))
                 and (.sha256 | type == "string" and test("^[0-9a-f]{64}$"))
                 and .synthetic == true)
             else false end))
        and ([.inputs[] | if .kind == "file" then ["file",.path] else [.kind,.name] end | tojson]
            | length == (unique | length))
      else true end)
    and (.criteria | type == "array" and length > 0 and (map(.id) | length == (unique | length)))
    and all(.criteria[];
        type == "object" and (.id | text) and (.expected | text) and (.environment | text)
        and (.evidence_type | type == "string" and IN("static", "empirical", "measurement"))
        and (.cases | type == "object" and length > 0)
        and all(.cases | to_entries[];
            (.key | text) and (.value | type == "object") and (.value.expected | text)
            and (.value.expected_exit_code | type == "number" and floor == . and . >= 0 and . <= 255)
            and (.value.required_stage | type == "string" and (. as $s | $route | any(. == $s)))))
    ) as $valid |
    if $valid then
        [($contract.criteria | length), ([$contract.criteria[] | (.cases | length)] | add)] | @tsv
    else empty end
' "$contract" 2>/dev/null) || block 'invalid acceptance contract'
# Counts become reportable only after the full schema validator succeeds and
# the source definition has been accepted. They are never inferred on refusals
# that precede that validation boundary.
IFS=$'\t' read -r summary_criteria_value summary_cases_value <<< "$contract_counts"
[[ "$summary_criteria_value" =~ ^[0-9]+$ && "$summary_cases_value" =~ ^[0-9]+$ ]] || block 'invalid acceptance contract'
summary_criteria_available=1
summary_cases_available=1

# Reject traversal, control characters, and symlinks at every component, even
# for a planned file that does not exist yet. No caller-controlled eval/globs.
safe_path() {
    local relative=$1 segment current=$root
    [[ -n "$relative" && "$relative" != /* && "$relative" != */ ]] || block 'invalid relative path'
    [[ ! "$relative" =~ [[:cntrl:]] ]] || block 'control character in path'
    local -a components
    IFS=/ read -r -a components <<< "$relative"
    for segment in "${components[@]}"; do
        [[ -n "$segment" && "$segment" != . && "$segment" != .. ]] || block 'traversal in path'
        current="$current/$segment"
        [[ ! -L "$current" ]] || block 'symlink in evidence scope'
    done
    printf '%s' "$current"
}
task=$(jq -r '.task_id' "$contract")
task_file=$(safe_path "datarim/tasks/$task-task-description.md") || block 'invalid task binding path'
[[ -f "$task_file" ]] || block 'canonical task description missing'
task_hash=$(hash < "$task_file")
# Canonical task metadata is a flat frontmatter contract. Read only these
# identity/routing scalars, reject duplicate fields and non-scalar encodings.
metadata=$(awk '
    NR == 1 { if ($0 != "---") exit 1; next }
    /^---$/ { closed=1; exit }
    /^(id|complexity|type):/ {
        key=$0; sub(/:.*/, "", key)
        value=$0; sub(/^[^:]+:[[:space:]]*/, "", value); sub(/[[:space:]]+$/, "", value)
        quote=substr(value,1,1)
        if (quote == "\"" || quote == sprintf("%c",39)) {
            if (length(value) < 2 || substr(value,length(value),1) != quote) exit 1
            value=substr(value,2,length(value)-2)
        }
        printf "%s\t%s\n", key, value
    }
    END { if (!closed) exit 1 }
' "$task_file" | jq -Rse '
    split("\n") | map(select(length > 0) | split("\t")) |
    if length == 3 and (map(.[0]) | unique | length) == 3
       and all(.[]; length == 2 and (.[1] | test("\\S") and (test("[[:cntrl:]]") | not)))
    then map({key:.[0],value:.[1]}) | from_entries else error("invalid task metadata") end
') || block 'invalid canonical task metadata'
jq -e --argjson metadata "$metadata" '
    .task_id == $metadata.id and .workflow.complexity == $metadata.complexity
    and .workflow.task_type == $metadata.type
' "$contract" >/dev/null || block 'task identity, complexity, or type mismatch'
summary_task_binding=VERIFIED
scope_digest() {
    local scope_manifest='' relative path digest executable
    while IFS= read -r relative; do
        path=$(safe_path "$relative") || return 1
        if [[ -f "$path" ]]; then
            digest=$(hash < "$path") || return 1
            executable=0
            [[ ! -x "$path" ]] || executable=1
        elif [[ -e "$path" ]]; then
            block 'scope path is not a regular file'
        else
            digest=MISSING
            executable=0
        fi
        scope_manifest+="$relative:$digest:executable=$executable"$'\n'
    done < <(jq -r '.scope | sort[]' "$contract")
    printf '%s' "$scope_manifest" | hash
}
scope_hash=$(scope_digest) || block 'invalid scope'
inputs_present=$(jq -r 'has("inputs")' "$contract")
inputs_digest() {
    local manifest='' record kind name relative path digest executable entry
    while IFS= read -r record; do
        kind=$(jq -r '.kind' <<< "$record")
        case "$kind" in
            file)
                relative=$(jq -r '.path' <<< "$record")
                path=$(safe_path "$relative") || return 1
                if [[ -f "$path" ]]; then
                    digest=$(hash < "$path") || return 1
                    executable=0
                    [[ ! -x "$path" ]] || executable=1
                elif [[ -e "$path" ]]; then
                    block 'input path is not a regular file'
                else
                    digest=MISSING
                    executable=0
                fi
                entry=$(jq -cnS --arg path "$relative" --arg digest "$digest" \
                    --argjson executable "$executable" \
                    '{kind:"file",path:$path,sha256:$digest,executable:$executable}') || return 1
                ;;
            argv)
                name=$(jq -r '.name' <<< "$record")
                digest=$(jq -r '.sha256' <<< "$record")
                entry=$(jq -cnS --arg name "$name" --arg sha256 "$digest" \
                    '{kind:"argv",name:$name,sha256:$sha256}') || return 1
                ;;
            env)
                name=$(jq -r '.name' <<< "$record")
                digest=$(jq -r '.sha256' <<< "$record")
                entry=$(jq -cnS --arg name "$name" --arg sha256 "$digest" \
                    '{kind:"env",name:$name,sha256:$sha256}') || return 1
                ;;
            *) block 'invalid input kind' ;;
        esac
        manifest+="$entry"$'\n'
    done < <(jq -c '.inputs[]' "$contract")
    printf '%s' "$manifest" | LC_ALL=C sort | hash
}
inputs_hash=''
compatibility_note=''
if [[ "$inputs_present" == true ]]; then
    inputs_hash=$(inputs_digest) || block 'invalid input manifest'
    summary_input_binding=BOUND
else
    compatibility_note='Legacy contract omits inputs[]; freshness remains bound to HEAD, contract, and scope only.'
    summary_input_binding=LEGACY_OMITTED
fi
if [[ "$stage" == preflight || "$stage" == snapshot ]]; then
    [[ $(hash < "$contract") == "$contract_hash" ]] || block 'contract changed during verification'
    if [[ "$summary_mode" == 1 ]]; then
        if [[ "$stage" == preflight ]]; then
            summary_emit PREFLIGHT_RECEIPT preflight_receipt_created 0
        else
            summary_emit SNAPSHOT_RECEIPT snapshot_receipt_created 0
        fi
        exit 0
    fi
    jq -n --arg stage "$stage" --arg task_id "$task" --arg timestamp "$now" --arg revision "$revision" \
        --arg contract_sha256 "$contract_hash" --arg scope_sha256 "$scope_hash" \
        --arg inputs_sha256 "$inputs_hash" --arg compatibility_note "$compatibility_note" \
        --argjson inputs_present "$inputs_present" \
        '{stage:$stage, task_id:$task_id, timestamp:$timestamp, revision:$revision,
          contract_sha256:$contract_sha256, scope_sha256:$scope_sha256} +
         (if $inputs_present then {inputs_sha256:$inputs_sha256}
          else {compatibility_note:$compatibility_note} end)'
    exit 0
fi
[[ -f "$evidence" && ! -L "$evidence" ]] || block 'missing regular evidence bundle'
evidence_hash=$(hash < "$evidence")
unique_json_keys "$evidence" || block 'ambiguous or invalid evidence JSON'
jq -se 'length == 1 and (.[0] | type == "object")' "$evidence" >/dev/null 2>&1 \
    || block 'evidence must contain exactly one JSON document'

# Each due case is matched by both IDs; report-wide keywords never count.
selection=$(jq -ce --slurpfile contract "$contract" --arg task "$task" --arg now "$now" \
    --arg stage "$stage" --arg revision "$revision" --arg ch "$contract_hash" --arg sh "$scope_hash" \
    --arg ih "$inputs_hash" --argjson has_inputs "$inputs_present" '
    def text: type == "string" and test("\\S");
    def stamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$") and (try (. as $original | fromdateiso8601 | todateiso8601 == $original) catch false);
    def digest: type == "string" and test("^[0-9a-f]{64}$");
    def case_record:
        type == "object" and (.criterion_id | text) and (.case_id | text)
        and (.observed | text) and (.command | text) and (.environment | text)
        and (.status | type == "string" and IN("pass","fail","blocked"))
        and (.evidence_type | type == "string" and IN("static","empirical","measurement"))
        and (.source | type == "string" and IN("static","fixture","live"))
        and (.exit_code | type == "number" and floor == . and . >= 0 and . <= 255)
        and (.artifact | type == "object" and (.relative_path | text) and (.sha256 | digest));
    def require($ok; $why): if $ok then . else error($why) end;
    $contract[0] as $c |
    $c.workflow.route as $route |
    def rank: . as $s | if type != "string" then error("non-scalar stage")
        else [$route | to_entries[] | select(.value == $s) | .key] |
            if length == 1 then .[0] else error("unknown stage") end end;
    require(($route | index($stage)) != null; "stage not in selected route") |
    [$c.criteria[] as $criterion | $criterion.cases | to_entries[] |
        {criterion_id:$criterion.id, case_id:.key, spec:.value,
         evidence_type:$criterion.evidence_type, environment:$criterion.environment}] as $cases |
    . as $bundle |
    require(.task_id == $task and (.attempts | type == "array" and length > 0); "invalid bundle") |
    require(.preflight.stage == "preflight" and .preflight.task_id == $task
        and .preflight.contract_sha256 == $ch and (.preflight.scope_sha256 | digest)
        and (if $has_inputs then .preflight.inputs_sha256 == $ih and (.preflight.inputs_sha256 | digest) else true end)
        and (.preflight.revision | type == "string" and test("^([0-9a-f]{40}|[0-9a-f]{64})$"))
        and (.preflight.timestamp | stamp) and (.implementation_started_at | stamp)
        and $c.defined_at <= .preflight.timestamp
        and .preflight.timestamp <= .implementation_started_at and .implementation_started_at <= $now;
        "missing or invalid pre-work baseline") |
    require(all(.attempts[]; type == "object" and (.actor | text)
        and (.revision | type == "string" and test("^([0-9a-f]{40}|[0-9a-f]{64})$"))
        and (.contract_sha256 | digest) and (.scope_sha256 | digest)
        and (if $has_inputs then (.inputs_sha256 | digest) else true end)
        and (.cases | type == "array" and all(.[]; case_record))
        and (.timestamp | stamp) and .timestamp >= $bundle.implementation_started_at
        and .timestamp <= $now and (.stage | rank) >= 0);
        "invalid attempt chronology") |
    require(all(range(1; .attempts|length); $bundle.attempts[.].timestamp >= $bundle.attempts[.-1].timestamp);
        "attempt history reordered") |
    [$route[0: (($stage|rank) + 1)][] |
        select(. != "archive" or any($cases[]; .spec.required_stage == "archive")
            or any($bundle.attempts[]; .stage == "archive"))] as $stages |
    [.attempts | to_entries[] as $entry | select($stages | index($entry.value.stage)) | $entry] as $entries |
    [$stages[] as $s | [$entries[] | select(.value.stage == $s)] | last] as $selected |
    require(all($selected[]; . != null); "missing stage evidence") |
    require(if $stage == "archive" or $stage == "quick" then
        ([$selected[-1].value.cases[] | {criterion_id,case_id}] | sort_by(.criterion_id,.case_id))
        == ([$cases[] | {criterion_id,case_id}] | sort_by(.criterion_id,.case_id))
        else true end; "terminal attempt must cover every contract case") |
    require(all(range(1; $selected|length); $selected[.].key > $selected[.-1].key);
        "correction requires downstream recheck") |
    require(all($selected[]; . as $review |
        all($selected[] | select(.key < $review.key);
            if $review.value.stage == "compliance" or $review.value.stage == "qa"
                or ($review.value.stage == "edit" and .value.stage == "write")
            then .value.actor != $review.value.actor else true end)); "review is not independent") |
    require(all($selected[].value;
        . as $a | ($a.stage | rank) as $r |
        [$cases[] | select((.spec.required_stage | rank) <= $r)] as $due |
        ($a.actor | text) and $a.revision == $revision and $a.contract_sha256 == $ch and $a.scope_sha256 == $sh
        and (if $has_inputs then $a.inputs_sha256 == $ih and ($a.inputs_sha256 | digest) else true end)
        and ($a.cases | type == "array" and length == ($due|length))
        and all($due[]; . as $d |
            [$a.cases[] | select(.criterion_id == $d.criterion_id and .case_id == $d.case_id)] as $matches |
            ($matches|length) == 1 and ($matches[0] |
                .status == "pass" and (.observed | text) and (.command | text)
                and .exit_code == $d.spec.expected_exit_code and .evidence_type == $d.evidence_type
                and .environment == $d.environment and (.artifact.relative_path | text) and (.artifact.sha256 | digest)
                and (if .evidence_type == "static" then (.source | IN("static","fixture","live")) else .source == "live" end))));
        "missing, stale, failed, or inapplicable case evidence") |
    {selected:[$selected[].value], pending:[$cases[] | select((.spec.required_stage|rank) > ($stage|rank)) |
        {criterion_id,case_id,required_stage:.spec.required_stage}]}
' "$evidence" 2>/dev/null) || block 'evidence coverage, freshness, or stage order failed'

if [[ "$summary_mode" == 1 ]]; then
    summary_pending_value=$(jq -r '.pending | length' <<< "$selection") || block 'evidence coverage, freshness, or stage order failed'
    [[ "$summary_pending_value" =~ ^[0-9]+$ ]] || block 'evidence coverage, freshness, or stage order failed'
    summary_pending_available=1
    summary_due_value=$((summary_cases_value - summary_pending_value))
    summary_due_available=1
fi

while IFS= read -r record; do
    relative=$(jq -r '.relative_path' <<< "$record")
    expected=$(jq -r '.sha256' <<< "$record")
    if [[ "$summary_mode" == 1 ]]; then
        path=$(safe_path "$relative") || block 'invalid evidence artifact path'
    else
        path=$(safe_path "$relative")
    fi
    [[ -f "$path" ]] || block 'evidence artifact missing'
    [[ $(hash < "$path") == "$expected" ]] || block 'evidence artifact hash mismatch'
done < <(jq -c '.selected[].cases[].artifact' <<< "$selection")

# Recheck inputs after inspection to avoid certifying a concurrently edited bundle.
[[ $(hash < "$contract") == "$contract_hash" ]] || block 'contract changed during verification'
[[ $(hash < "$evidence") == "$evidence_hash" ]] || block 'evidence changed during verification'
[[ $(hash < "$task_file") == "$task_hash" ]] || block 'task metadata changed during verification'
[[ $(scope_digest) == "$scope_hash" ]] || block 'scope changed during verification'
if [[ "$inputs_present" == true ]]; then
    [[ $(inputs_digest) == "$inputs_hash" ]] || block 'inputs changed during verification'
fi
[[ $(git -C "$root" rev-parse HEAD) == "$revision" ]] || block 'revision changed during verification'
if [[ "$summary_mode" == 1 ]]; then
    summary_validated_value=$summary_due_value
    summary_validated_available=$summary_due_available
    summary_emit STAGE_PASS evidence_stage_validated 0
    exit 0
fi
jq -n --arg stage "$stage" --arg task_id "$task" --argjson pending "$(jq '.pending' <<< "$selection")" \
    '{verdict:"STAGE_PASS",task_id:$task_id,stage:$stage,pending:$pending}'
