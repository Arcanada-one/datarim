#!/usr/bin/env bats
# Fail closed when any job in .github/workflows targets a GitHub-hosted runner.
# Every runs-on must resolve to a label set that includes self-hosted (literal,
# matrix.runner value, or workflow_call runner_labels default).

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WF_DIR="$ROOT/.github/workflows"
}

job_runs_on_is_self_hosted() {
    local wf="$1" job="$2"
    /usr/bin/python3 - "$wf" "$job" <<'PY'
import json
import subprocess
import sys

wf, job = sys.argv[1], sys.argv[2]

def yq(*args):
    return subprocess.check_output(["yq", *args, wf], text=True).rstrip("\n")

runs_raw = yq("-o=json", "-I0", f'.jobs."{job}"."runs-on" // null')
runs = json.loads(runs_raw)
if runs is None:
    raise SystemExit(f"{wf}:{job}: missing runs-on")

def has_self_hosted(value):
    if isinstance(value, str):
        return "self-hosted" in value
    if isinstance(value, list):
        return any(isinstance(item, str) and item == "self-hosted" for item in value) or any(
            isinstance(item, str) and "self-hosted" in item for item in value
        )
    return False

if has_self_hosted(runs):
    raise SystemExit(0)

if isinstance(runs, str) and "fromJSON(inputs.runner_labels)" in runs:
    default = yq("-r", '.on.workflow_call.inputs.runner_labels.default // ""')
    if "self-hosted" in default:
        raise SystemExit(0)
    raise SystemExit(f"{wf}:{job}: runner_labels default lacks self-hosted ({default!r})")

if isinstance(runs, str) and "matrix.runner" in runs:
    matrix_raw = yq("-o=json", "-I0", f'.jobs."{job}".strategy.matrix // null')
    matrix = json.loads(matrix_raw)
    if matrix is None:
        raise SystemExit(f"{wf}:{job}: matrix.runner without strategy.matrix")
    blobs = [json.dumps(matrix)]
    if isinstance(matrix, dict) and "include" in matrix:
        blobs.append(json.dumps(matrix["include"]))
    if any("self-hosted" in blob for blob in blobs):
        # Every include entry that supplies runner must include self-hosted.
        include = matrix.get("include") if isinstance(matrix, dict) else None
        if isinstance(include, list):
            for idx, entry in enumerate(include):
                if not isinstance(entry, dict) or "runner" not in entry:
                    continue
                if not has_self_hosted(entry["runner"]):
                    raise SystemExit(f"{wf}:{job}: matrix.include[{idx}].runner lacks self-hosted")
        raise SystemExit(0)
    raise SystemExit(f"{wf}:{job}: matrix.runner lacks self-hosted in matrix")

raise SystemExit(f"{wf}:{job}: runs-on lacks self-hosted: {runs!r}")
PY
}

@test "every workflow job runs-on includes self-hosted" {
    local f job bad=0
    for f in "$WF_DIR"/*.yml; do
        while IFS= read -r job; do
            [ -z "$job" ] && continue
            if ! job_runs_on_is_self_hosted "$f" "$job"; then
                bad=1
            fi
        done < <(yq -r '.jobs | keys | .[]' "$f")
    done
    [ "$bad" -eq 0 ]
}

@test "no workflow file names a GitHub-hosted runner label" {
    local f bad=0
    for f in "$WF_DIR"/*.yml; do
        if grep -nE 'runs-on:[[:space:]]*(ubuntu-latest|ubuntu-[0-9]|macos-latest|macos-[0-9]|windows-latest|windows-[0-9])' "$f"; then
            echo "hosted runner label in $(basename "$f")" >&2
            bad=1
        fi
        if grep -nE 'runner:[[:space:]]*(ubuntu-latest|ubuntu-[0-9]|macos-latest|macos-[0-9]|windows-latest|windows-[0-9])' "$f"; then
            echo "hosted matrix.runner in $(basename "$f")" >&2
            bad=1
        fi
    done
    [ "$bad" -eq 0 ]
}
