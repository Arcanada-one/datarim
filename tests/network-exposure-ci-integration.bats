#!/usr/bin/env bats
# Phase 3 CI integration: workflow YAML structural assertions, four-fixture
# simulated-CI runs (mirroring what `network-exposure-lint.yml` runs on a
# real GitHub-hosted runner), and the V-AC9 performance budget.
#
# The bats suite proves the linter portion of the workflow stays well inside
# the 30-second median budget; the full workflow runtime (which adds
# `actions/checkout` + `yq` install) is verified out-of-band via
# `gh run view --json duration` after the first real CI run on a consumer
# repository.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/dev-tools/network-exposure-check.sh"
    F="$REPO_ROOT/tests/fixtures/network-exposure"
    WF="$REPO_ROOT/.github/workflows/network-exposure-lint.yml"
    TODAY="2026-05-06"
}

# --- Workflow file: structural validation -------------------------------------

@test "workflow: file exists and yq parses YAML cleanly" {
    [ -f "$WF" ]
    run yq eval '.' "$WF"
    [ "$status" -eq 0 ]
}

@test "workflow: top-level name is network-exposure-lint" {
    run yq -r '.name' "$WF"
    [ "$status" -eq 0 ]
    [ "$output" = "network-exposure-lint" ]
}

@test "workflow: workflow_call inputs include all six contract fields" {
    run yq -r '.on.workflow_call.inputs | keys | .[]' "$WF"
    [ "$status" -eq 0 ]
    for k in compose_paths redis_conf_paths postgres_conf_paths systemd_socket_paths strict datarim_ref; do
        [[ "$output" == *"$k"* ]] || {
            echo "missing input: $k" >&2
            return 1
        }
    done
}

@test "workflow: strict input default is true" {
    run yq -r '.on.workflow_call.inputs.strict.default' "$WF"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "workflow: lint job runs on ubuntu-latest" {
    run yq -r '.jobs.lint."runs-on"' "$WF"
    [ "$status" -eq 0 ]
    [ "$output" = "ubuntu-latest" ]
}

@test "workflow: permissions block restricts contents to read" {
    run yq -r '.permissions.contents' "$WF"
    [ "$status" -eq 0 ]
    [ "$output" = "read" ]
}

@test "workflow: lint job invokes network-exposure-check.sh from .datarim" {
    run grep -F ".datarim/dev-tools/network-exposure-check.sh" "$WF"
    [ "$status" -eq 0 ]
}

@test "workflow: actionlint clean (when available)" {
    if ! command -v actionlint >/dev/null 2>&1; then
        skip "actionlint not installed"
    fi
    run actionlint "$WF"
    [ "$status" -eq 0 ]
}

# --- 4 fixture-repo simulated CI runs ----------------------------------------

@test "fixture-repo: compose-pass-1270 → exit 0 (V-AC1 surface)" {
    run "$SCRIPT" --compose "$F/compose-pass-1270.yml" --today "$TODAY"
    [ "$status" -eq 0 ]
}

@test "fixture-repo: compose-pass-justified → exit 0 (V-AC3 surface)" {
    run "$SCRIPT" --compose "$F/compose-pass-justified.yml" --today "$TODAY"
    [ "$status" -eq 0 ]
}

@test "fixture-repo: compose-fail-0000 → exit 1 with file:line (V-AC2 surface)" {
    run "$SCRIPT" --compose "$F/compose-fail-0000.yml" --today "$TODAY"
    [ "$status" -eq 1 ]
    [[ "$output" =~ compose-fail-0000\.yml:[0-9]+ ]]
}

@test "fixture-repo: compose-fail-short → exit 1 with file:line (V-AC4 surface)" {
    run "$SCRIPT" --compose "$F/compose-fail-short.yml" --today "$TODAY"
    [ "$status" -eq 1 ]
    [[ "$output" =~ compose-fail-short\.yml:[0-9]+ ]]
}

# --- V-AC9: linter median runtime ≤ 30s across 10 runs ----------------------

@test "V-AC9: median linter runtime over 10 runs ≤ 30s on combined input" {
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not available for monotonic timing"
    fi
    run python3 - <<PY "$SCRIPT" "$F" "$TODAY"
import subprocess, sys, time
script, fixtures_dir, today = sys.argv[1], sys.argv[2], sys.argv[3]
args = [
    script,
    "--compose", f"{fixtures_dir}/compose-pass-1270.yml",
    "--compose", f"{fixtures_dir}/compose-pass-justified.yml",
    "--redis-conf", f"{fixtures_dir}/redis-pass-loopback.conf",
    "--postgres-conf", f"{fixtures_dir}/postgresql-pass.conf",
    "--systemd-socket", f"{fixtures_dir}/svc-pass.socket",
    "--today", today,
]
runtimes = []
for _ in range(10):
    t0 = time.monotonic()
    rc = subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
    runtimes.append(time.monotonic() - t0)
    if rc != 0:
        print(f"linter exited {rc} on run {len(runtimes)}", file=sys.stderr)
        sys.exit(2)
runtimes.sort()
median = (runtimes[4] + runtimes[5]) / 2.0
budget = 30.0
print(f"median={median:.4f}s p95={runtimes[-1]:.4f}s budget={budget}s")
sys.exit(0 if median <= budget else 1)
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"median="* ]]
}
