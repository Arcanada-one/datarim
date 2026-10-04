#!/usr/bin/env bash
# Structured implementation of check-live-evidence.sh; not a separate gate.
# Read-only: verifies case coverage, current content/revision, and stage order.
# Dependencies: python3, jq, git, sha256sum or shasum. Never executes evidence commands.
# Exit 0 STAGE_PASS/preflight receipt; 1 BLOCKED; 2 invocation/runtime error.
set -euo pipefail

block() { echo "BLOCKED: $*" >&2; exit 1; }
usage() { echo "evidence gate: --contract FILE --evidence FILE --root DIR --stage preflight|snapshot|do|write|edit|publish|qa|compliance|archive|quick" >&2; exit 2; }
contract='' evidence='' root='' stage=''
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
command -v python3 >/dev/null || usage
command -v jq >/dev/null || usage
command -v git >/dev/null || usage
if command -v sha256sum >/dev/null; then
    hash() { sha256sum | cut -d ' ' -f 1; }
elif command -v shasum >/dev/null; then
    hash() { shasum -a 256 | cut -d ' ' -f 1; }
else
    usage
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
revision=$(git -C "$root" rev-parse --verify HEAD) || usage
[[ $(git -C "$root" rev-parse --show-toplevel) == "$root" ]] || usage
[[ -f "$contract" && ! -L "$contract" ]] || block 'missing regular contract'
contract_hash=$(hash < "$contract")
unique_json_keys "$contract" || block 'ambiguous or invalid contract JSON'
jq -se 'length == 1 and (.[0] | type == "object")' "$contract" >/dev/null 2>&1 \
    || block 'contract must contain exactly one JSON document'
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -e --arg now "$now" '
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
    and (.criteria | type == "array" and length > 0 and (map(.id) | length == (unique | length)))
    and all(.criteria[];
        type == "object" and (.id | text) and (.expected | text) and (.environment | text)
        and (.evidence_type | type == "string" and IN("static", "empirical", "measurement"))
        and (.cases | type == "object" and length > 0)
        and all(.cases | to_entries[];
            (.key | text) and (.value | type == "object") and (.value.expected | text)
            and (.value.expected_exit_code | type == "number" and floor == . and . >= 0 and . <= 255)
            and (.value.required_stage | type == "string" and (. as $s | $route | any(. == $s)))))
' "$contract" >/dev/null 2>&1 || block 'invalid acceptance contract'

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
if [[ "$stage" == preflight || "$stage" == snapshot ]]; then
    [[ $(hash < "$contract") == "$contract_hash" ]] || block 'contract changed during verification'
    jq -n --arg stage "$stage" --arg task_id "$task" --arg timestamp "$now" --arg revision "$revision" \
        --arg contract_sha256 "$contract_hash" --arg scope_sha256 "$scope_hash" \
        '{stage:$stage, task_id:$task_id, timestamp:$timestamp, revision:$revision,
          contract_sha256:$contract_sha256, scope_sha256:$scope_sha256}'
    exit 0
fi
[[ -f "$evidence" && ! -L "$evidence" ]] || block 'missing regular evidence bundle'
evidence_hash=$(hash < "$evidence")
unique_json_keys "$evidence" || block 'ambiguous or invalid evidence JSON'
jq -se 'length == 1 and (.[0] | type == "object")' "$evidence" >/dev/null 2>&1 \
    || block 'evidence must contain exactly one JSON document'

# Each due case is matched by both IDs; report-wide keywords never count.
selection=$(jq -ce --slurpfile contract "$contract" --arg task "$task" --arg now "$now" \
    --arg stage "$stage" --arg revision "$revision" --arg ch "$contract_hash" --arg sh "$scope_hash" '
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
        and (.preflight.revision | type == "string" and test("^([0-9a-f]{40}|[0-9a-f]{64})$"))
        and (.preflight.timestamp | stamp) and (.implementation_started_at | stamp)
        and $c.defined_at <= .preflight.timestamp
        and .preflight.timestamp <= .implementation_started_at and .implementation_started_at <= $now;
        "missing or invalid pre-work baseline") |
    require(all(.attempts[]; type == "object" and (.actor | text)
        and (.revision | type == "string" and test("^([0-9a-f]{40}|[0-9a-f]{64})$"))
        and (.contract_sha256 | digest) and (.scope_sha256 | digest)
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

while IFS= read -r record; do
    relative=$(jq -r '.relative_path' <<< "$record")
    expected=$(jq -r '.sha256' <<< "$record")
    path=$(safe_path "$relative")
    [[ -f "$path" ]] || block 'evidence artifact missing'
    [[ $(hash < "$path") == "$expected" ]] || block 'evidence artifact hash mismatch'
done < <(jq -c '.selected[].cases[].artifact' <<< "$selection")

# Recheck inputs after inspection to avoid certifying a concurrently edited bundle.
[[ $(hash < "$contract") == "$contract_hash" ]] || block 'contract changed during verification'
[[ $(hash < "$evidence") == "$evidence_hash" ]] || block 'evidence changed during verification'
[[ $(hash < "$task_file") == "$task_hash" ]] || block 'task metadata changed during verification'
[[ $(scope_digest) == "$scope_hash" ]] || block 'scope changed during verification'
[[ $(git -C "$root" rev-parse HEAD) == "$revision" ]] || block 'revision changed during verification'
jq -n --arg stage "$stage" --arg task_id "$task" --argjson pending "$(jq '.pending' <<< "$selection")" \
    '{verdict:"STAGE_PASS",task_id:$task_id,stage:$stage,pending:$pending}'
