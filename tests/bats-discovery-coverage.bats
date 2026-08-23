#!/usr/bin/env bats
#
# tests/bats-discovery-coverage.bats
#
# Anti-decay wiring for the repo-wide bats gate.
#
# The failure mode this guards against is the one that produced the gap in the
# first place: CI enumerating suites by name, a new suite landing, nobody adding
# it to the list, and no signal anywhere that it is dark. These assertions make
# the discovery mechanism itself falsifiable — if someone reverts `bats.yml` to
# an explicit list, adds a `paths:` filter, or lets the exclusion registry rot,
# this suite goes red.

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    RUNNER="$ROOT/tests/run-bats-discovery.sh"
    WF="$ROOT/.github/workflows/bats.yml"
    CI_PYTHON="${CUSTOMER_CI_PYTHON:-/usr/bin/python3}"
    export ROOT RUNNER WF
}

# --- the runner itself -------------------------------------------------------

@test "bats workflow remains syntactically valid YAML" {
    "$CI_PYTHON" - "$WF" <<'PY'
import sys
import yaml
with open(sys.argv[1], encoding="utf-8") as handle:
    workflow = yaml.safe_load(handle)
assert isinstance(workflow, dict) and isinstance(workflow.get("jobs"), dict)
PY
}

@test "discovery runner exists and is shellcheck-clean" {
    [ -f "$RUNNER" ]
    if ! command -v shellcheck >/dev/null 2>&1; then
        skip "shellcheck not installed"
    fi
    run shellcheck "$RUNNER"
    [ "$status" -eq 0 ]
}

@test "discovery finds every .bats file on disk minus the registry" {
    local on_disk discovered excluded
    on_disk="$(find "$ROOT" -type f -name '*.bats' ! -path "$ROOT/.git/*" | wc -l)"
    discovered="$(bash "$RUNNER" --root "$ROOT" --list | wc -l)"
    excluded="$(grep -cE '^[[:space:]]*-[[:space:]]+path:' "$ROOT/tests/bats-exclusions.yml" || true)"

    [ "$discovered" -eq "$(( on_disk - excluded - 3 ))" ]
}

@test "managed customer-delivery suites leave monolithic discovery and retain exact shard coverage" {
    local discovered
    discovered="$(bash "$RUNNER" --root "$ROOT" --list)"
    [[ "$discovered" != *"dev-tools/tests/check-customer-delivery.bats"* ]] \
        && [[ "$discovered" != *"dev-tools/tests/customer-delivery-schema.bats"* ]] \
        && [[ "$discovered" != *"dev-tools/tests/customer-delivery-mutation.bats"* ]] \
        && /usr/bin/python3 "$ROOT/tests/run-customer-delivery-shard.py" --check
}

@test "discovery is non-empty (a broken glob must not read as 'all clean')" {
    local n
    n="$(bash "$RUNNER" --root "$ROOT" --list | wc -l)"
    # The repo has hundreds of suites; anything near zero means the find
    # predicate broke, not that the suites vanished.
    [ "$n" -ge 100 ]
}

@test "discovery reaches suites in nested directories" {
    # `bats <dir>` is NOT recursive. That single fact is why tests/security/
    # and tests/install-matrix/ were invisible to the old job. Assert the
    # runner descends.
    run bash "$RUNNER" --root "$ROOT" --list
    [ "$status" -eq 0 ]
    [[ "$output" == *"tests/security/"* ]]
    [[ "$output" == *"tests/install-matrix/"* ]]
}

@test "discovery reaches every test root, not just tests/" {
    run bash "$RUNNER" --root "$ROOT" --list
    [ "$status" -eq 0 ]
    [[ "$output" == *"cli/tests/"* ]]
    [[ "$output" == *"dev-tools/tests/"* ]]
    [[ "$output" == *"plugins/dr-orchestrate/tests/"* ]]
    [[ "$output" == *"plugins/dr-fleet-evolution/tests/"* ]]
}

# --- sharding ----------------------------------------------------------------

@test "shards partition the suite list exactly — no gaps, no overlaps" {
    local full parts
    full="$(bash "$RUNNER" --root "$ROOT" --list | LC_ALL=C sort)"

    parts=""
    local n
    for n in 1 2 3 4 5 6 7 8; do
        parts="${parts}$(bash "$RUNNER" --root "$ROOT" --list | awk -v n="$n" 'NR%8+1==n')
"
    done
    parts="$(printf '%s' "$parts" | grep -c . || true)"

    local full_count
    full_count="$(printf '%s\n' "$full" | grep -c . || true)"
    [ "$parts" -eq "$full_count" ]
}

@test "an out-of-range shard is a usage error, not a silent no-op" {
    run bash "$RUNNER" --root "$ROOT" --shard 9/8 --list
    [ "$status" -eq 2 ]
}

# --- exclusion registry ------------------------------------------------------

@test "exclusion registry validates (no stale paths, no missing fields)" {
    run bash "$RUNNER" --root "$ROOT" --check-registry
    [ "$status" -eq 0 ]
}

@test "a stale registry entry fails the registry check" {
    local tmp="$BATS_TEST_TMPDIR/stale.yml"
    cat >"$tmp" <<'YAML'
schema_version: 1
entries:
  - path: tests/this-suite-does-not-exist.bats
    reason: "placeholder reason long enough to be meaningful"
    owner: nobody
    follow_up: none
    added: 2026-07-31
YAML
    run bash "$RUNNER" --root "$ROOT" --registry "$tmp" --check-registry
    [ "$status" -eq 1 ]
    [[ "$output" == *"stale registry entry"* ]]
}

@test "a registry entry missing required fields fails the registry check" {
    local tmp="$BATS_TEST_TMPDIR/thin.yml"
    cat >"$tmp" <<'YAML'
schema_version: 1
entries:
  - path: tests/bats-discovery-coverage.bats
    reason: "reason present but owner/follow_up/added are not"
YAML
    run bash "$RUNNER" --root "$ROOT" --registry "$tmp" --check-registry
    [ "$status" -eq 1 ]
}

# --- workflow wiring ---------------------------------------------------------

@test "bats.yml drives the discovery runner rather than naming suites" {
    [ -f "$WF" ]
    grep -q 'run-bats-discovery.sh' "$WF"
}

@test "bats.yml has no paths filter (a release PR must still run the gate)" {
    # A `paths:` filter here is how a full regression gate ends up skipping on
    # exactly the PR that most needs it.
    run grep -E '^[[:space:]]+paths:' "$WF"
    [ "$status" -ne 0 ]
}

@test "bats.yml validates the exclusion registry before running shards" {
    grep -q -- '--check-registry' "$WF"
}

@test "bats.yml pins every action to a commit SHA" {
    # Security Mandate S4: no floating tags on third-party actions.
    local bad
    bad="$(grep -E '^\s*(-\s*)?uses:' "$WF" | grep -vE '@[0-9a-f]{40}' || true)"
    [ -z "$bad" ] || {
        echo "unpinned action reference(s): $bad"
        return 1
    }
}

@test "bats.yml declares least-privilege permissions" {
    grep -qE '^permissions:' "$WF"
    grep -qE '^\s+contents:\s*read' "$WF"
    run grep -E '^\s+(contents|packages|id-token|actions):\s*write' "$WF"
    [ "$status" -ne 0 ]
}

@test "the CI toolchain installer pins bats and yq by digest" {
    local inst="$ROOT/tests/ci-install-bats-deps.sh"
    [ -f "$inst" ]
    # bats by 40-char commit SHA, yq by sha256.
    grep -qE 'BATS_SHA="[0-9a-f]{40}"' "$inst"
    grep -qE 'YQ_SHA256="[0-9a-f]{64}"' "$inst"
    # and the digest is actually checked, not merely recorded
    grep -q 'sha256sum -c -' "$inst"
}

@test "the CI Python dependency contract pins and probes date-time validation" {
    local inst="$ROOT/tests/ci-install-bats-deps.sh"
    [ -f "$inst" ]
    grep -q '^PY_RFC3339_VALIDATOR="rfc3339-validator==0\.1\.4"$' "$inst"
    grep -q '"$PY_RFC3339_VALIDATOR"' "$inst"
    grep -q 'rfc3339_validator' "$inst"
    grep -q 'FormatChecker.*date-time' "$inst"
    grep -q 'distutils-precedence\.pth' "$inst"
    grep -q 'unexpected executable Python path file' "$inst"
}

@test "customer-delivery crypto fixtures use one pinned Python helper without PHP" {
    local inst="$ROOT/tests/ci-install-bats-deps.sh"
    local helper="$ROOT/tests/customer-delivery-ed25519.py"
    [ -f "$helper" ] \
        && grep -q '^PY_CRYPTOGRAPHY="cryptography==43\.0\.3"$' "$inst" \
        && grep -q '"$PY_CRYPTOGRAPHY"' "$inst" \
        && grep -q 'import cryptography' "$inst" \
        && ! grep -qE 'php -r|sodium_|command -v php' \
            "$ROOT/dev-tools/tests/check-customer-delivery.bats" \
            "$ROOT/dev-tools/tests/customer-delivery-schema.bats" \
            "$ROOT/dev-tools/tests/customer-delivery-mutation.bats"
}

@test "macOS CI installs pinned A2 dependencies and runs both A2 suites in bounded steps" {
    grep -q 'brew install bats-core yq openssl@3' "$WF" \
        && grep -q -- '--python-only' "$WF" \
        && grep -q 'run-customer-delivery-shard.py' "$WF" \
        && grep -q 'customer-delivery-macos' "$WF" \
        && grep -q 'customer-delivery-linux' "$WF" \
        && [ "$(grep -c -- '--python-bin "$clt_python" --python-site "$dependency_site"' "$WF")" -eq 2 ] \
        && grep -q 'tests/bats-discovery-coverage.bats' "$WF"
}

@test "macOS portability contracts use the pinned dependency-bearing Python environment" {
    grep -q '/usr/bin/python3 -m venv "\$RUNNER_TEMP/portability-venv"' "$WF" \
        && grep -q 'dependency_site="\$RUNNER_TEMP/portability-venv/lib/python${clt_version}/site-packages"' "$WF" \
        && grep -q -- '--python-bin "$clt_python" --python-site "$dependency_site"' "$WF" \
        && grep -q 'CUSTOMER_CI_PYTHON="\$RUNNER_TEMP/portability-venv/bin/python" bats tests/bats-discovery-coverage.bats' "$WF"
}

@test "CI installer supports a pinned Python-only dependency mode" {
    local inst="$ROOT/tests/ci-install-bats-deps.sh"
    grep -q -- '--python-only' "$inst" \
        && grep -q -- '--python-bin' "$inst" \
        && grep -q -- '--python-site' "$inst" \
        && grep -q 'PYTHON_BIN' "$inst"
}

@test "Linux and macOS customer-delivery jobs pass an absolute interpreter to every shard" {
    local explicit_count
    explicit_count="$(grep -c -- "--python-bin \"\$RUNNER_TEMP/customer-delivery-venv/bin/python\"" "$WF")"
    [ "$explicit_count" -eq 3 ] \
        && [ "$(grep -c '/bin/ln -sf /usr/bin/python3 "\$RUNNER_TEMP/customer-delivery-venv/bin/python"' "$WF")" -eq 2 ] \
        && ! grep -qE 'bats dev-tools/tests/(check-customer-delivery|customer-delivery-schema|customer-delivery-mutation)\.bats' "$WF"
}

@test "Linux and macOS customer-delivery jobs preflight launcher runtime identity and dependencies" {
    local preflight="$ROOT/tests/check-customer-delivery-python-runtime.sh"
    local validator="$ROOT/dev-tools/check-customer-delivery.sh"
    [ -x "$preflight" ] \
        && [ "$(grep -c 'bash tests/check-customer-delivery-python-runtime.sh "\$RUNNER_TEMP/customer-delivery-venv/bin/python"' "$WF")" -eq 2 ] \
        && grep -q '/usr/bin/python3 -m venv "\$RUNNER_TEMP/discovery-venv"' "$WF" \
        && [ "$(grep -c 'DEVELOPER_DIR=/Library/Developer/CommandLineTools' "$WF")" -ge 3 ] \
        && grep -q '/bin/ln -sf /usr/bin/python3 "\$RUNNER_TEMP/portability-venv/bin/python"' "$WF" \
        && grep -q 'dependency_site="\$RUNNER_TEMP/customer-delivery-venv/lib/python${clt_version}/site-packages"' "$WF" \
        && grep -q 'trusted_python_site="${python_venv_root}/lib/python${runtime_major}.${runtime_minor}/site-packages"' "$validator" \
        && grep -q 'CUSTOMER_CI_PYTHON="\$RUNNER_TEMP/discovery-venv/bin/python" bash tests/run-bats-discovery.sh' "$WF" \
        && grep -q 'DEVELOPER_DIR=/Library/Developer/CommandLineTools CUSTOMER_CI_PYTHON="\$RUNNER_TEMP/portability-venv/bin/python" bats tests/bats-discovery-coverage.bats' "$WF" \
        || return 1
    [[ -n "${CUSTOMER_CI_PYTHON:-}" ]] || skip 'CUSTOMER_CI_PYTHON is required; every CI invocation provides a pinned venv'
    "$preflight" "$CI_PYTHON"
}

@test "customer-delivery CI matrices come only from the canonical shard registry" {
    grep -q 'linux_matrix:.*steps.customer_delivery_matrix.outputs.linux' "$WF" \
        && grep -q 'macos_matrix:.*steps.customer_delivery_matrix.outputs.macos' "$WF" \
        && grep -q 'linux=.*run-customer-delivery-shard.py --matrix linux' "$WF" \
        && grep -q 'macos=.*run-customer-delivery-shard.py --matrix macos' "$WF" \
        && grep -q 'include:.*fromJSON(needs.registry.outputs.linux_matrix)' "$WF" \
        && grep -q 'include:.*fromJSON(needs.registry.outputs.macos_matrix)' "$WF" \
        && ! grep -qE '^\s+- \{ suite: (functional|schema|mutation),' "$WF"
}

@test "customer-delivery aggregate verifies exact Linux and macOS result inventories" {
    grep -q '^  customer-delivery-aggregate:' "$WF" \
        && grep -q 'needs: \[registry, customer-delivery-linux, customer-delivery-macos\]' "$WF" \
        && grep -q -- '--check-results linux' "$WF" \
        && grep -q -- '--check-results macos' "$WF" \
        && [ "$(grep -c 'actions/upload-artifact@' "$WF")" -eq 2 ] \
        && [ "$(grep -c 'actions/download-artifact@' "$WF")" -eq 2 ] \
        && [ "$(grep -c -- '--result-file' "$WF")" -eq 2 ]
}

@test "every customer-delivery checkout is pinned to and verifies the triggering PR head" {
    /usr/bin/python3 - "$WF" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
expected = "${{ github.event.pull_request.head.sha || github.sha }}"
assert f"EXPECTED_HEAD_SHA: {expected}" in text
jobs = list(re.finditer(r"(?m)^  ([a-z][a-z0-9-]+):\n", text))
sections = {
    match.group(1): text[match.start() : jobs[index + 1].start() if index + 1 < len(jobs) else None]
    for index, match in enumerate(jobs)
}
for job in ("registry", "customer-delivery-linux", "customer-delivery-macos", "customer-delivery-aggregate"):
    section = sections[job]
    assert section.count(f"ref: {expected}") == 1, job
    assert section.count('test "$(git rev-parse HEAD)" = "$EXPECTED_HEAD_SHA"') == 1, job
PY
}
