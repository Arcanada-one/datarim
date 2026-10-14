#!/usr/bin/env bats
# Synthetic controls for enabled-and-selected product-discovery agent fragments.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    GATE="$REPO_ROOT/dev-tools/read-product-profile.sh"
    PLUGIN_TOOL="$REPO_ROOT/scripts/dr-plugin.sh"
    PLUGIN="$REPO_ROOT/plugins/product-discovery"
    FIXTURE="${BATS_TEST_TMPDIR:?}"
    ROOT="$FIXTURE/workspace"
    RUNTIME="$ROOT/.datarim-runtime/local"
    TASK=TASK-1234
    RESEARCHER_FRAGMENT=skills/product-discovery/hypothesis-validation/researcher.product-discovery.md
    STRATEGIST_FRAGMENT=skills/product-discovery/decision-record/strategist.product-discovery.md
    mkdir -p "$ROOT/datarim/tasks" "$ROOT/.datarim-runtime"
    # Synthetic project-local runtime marker: this suite tests plugin asset
    # placement and profile selection, not the interactive framework installer.
    python3 - "$ROOT" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1]).resolve()
(root/'.datarim-runtime/installation.json').write_text(json.dumps({
    'schema': 1,
    'project': str(root),
    'contexts': [],
})+'\n')
PY
    cat >"$ROOT/datarim/tasks/$TASK-task-description.md" <<'TASK'
## Requirements
Synthetic test input.
TASK
}

teardown() {
    rm -rf "$FIXTURE"
}

select_profile() {
    cat >"$ROOT/datarim/tasks/$TASK-task-description.md" <<'TASK'
## Profile
profile: product-discovery
TASK
}

enable_plugin() {
    DR_PLUGIN_WORKSPACE="$ROOT" "$PLUGIN_TOOL" enable "$PLUGIN"
}

load_profile_fragment() {
    local rel="$1" gate path
    gate="$("$GATE" --root "$ROOT" --task "$TASK" --runtime "$RUNTIME")" || return $?
    [ "$gate" = profile_active ] || return 0
    path="$RUNTIME/$rel"
    if [ ! -f "$path" ] || [ ! -r "$path" ]; then
        printf 'required product-discovery fragment missing: %s\n' "$path" >&2
        return 2
    fi
    python3 - "$path" <<'PY'
import hashlib, pathlib, sys
p=pathlib.Path(sys.argv[1])
p.read_bytes()  # The receipt is emitted only after reading the installed path.
print(f'loaded {p} sha256:{hashlib.sha256(p.read_bytes()).hexdigest()}')
PY
}

@test "enabled and selected profile reads both fragments from installed paths with receipts" {
    enable_plugin
    select_profile

    run load_profile_fragment "$RESEARCHER_FRAGMENT"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^loaded\ .*researcher\.product-discovery\.md\ sha256:[0-9a-f]{64}$ ]]

    run load_profile_fragment "$STRATEGIST_FRAGMENT"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^loaded\ .*strategist\.product-discovery\.md\ sha256:[0-9a-f]{64}$ ]]
}

@test "selected profile with disabled plugin does not read a fragment" {
    select_profile
    run load_profile_fragment "$RESEARCHER_FRAGMENT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -e "$RUNTIME/$RESEARCHER_FRAGMENT" ]
}

@test "enabled plugin with profile off does not read an installed fragment" {
    enable_plugin
    run load_profile_fragment "$RESEARCHER_FRAGMENT"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -r "$RUNTIME/$RESEARCHER_FRAGMENT" ]
}

@test "active profile with a missing installed fragment fails loudly" {
    enable_plugin
    select_profile
    rm "$RUNTIME/$RESEARCHER_FRAGMENT"

    run load_profile_fragment "$RESEARCHER_FRAGMENT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"required product-discovery fragment missing: $RUNTIME/$RESEARCHER_FRAGMENT"* ]]
}

@test "agent references stay inside the product-discovery profile gate" {
    python3 - "$REPO_ROOT/agents/researcher.md" "$REPO_ROOT/agents/strategist.md" <<'PY'
import pathlib, sys
checks = {
    pathlib.Path(sys.argv[1]): '${DATARIM_RUNTIME:?}/local/skills/product-discovery/hypothesis-validation/researcher.product-discovery.md',
    pathlib.Path(sys.argv[2]): '${DATARIM_RUNTIME:?}/local/skills/product-discovery/decision-record/strategist.product-discovery.md',
}
for path, ref in checks.items():
    lines = path.read_text().splitlines()
    active = False
    in_gate = []
    outside = []
    for line in lines:
        if line.strip() == '### Product discovery profile gate':
            active = True
            continue
        if active and line.startswith('### '):
            active = False
        if ref in line:
            (in_gate if active else outside).append(line)
    if len(in_gate) != 1 or outside:
        raise SystemExit(f'profile gate reference mismatch: {path}')
print('gated references verified')
PY
    }
