#!/usr/bin/env bats
# Product scans retain clean fixture coverage; unsafe controls are checked separately.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "local shellcheck runs a native executable without a container" {
    python3 - "$REPO_ROOT" <<'PY_CONFIG'
import sys
from pathlib import Path
import yaml
root = Path(sys.argv[1])
config = yaml.safe_load((root / '.pre-commit-config.yaml').read_text())
entries = [(repo, hook) for repo in config['repos'] for hook in repo['hooks']
           if hook['id'] == 'shellcheck']
assert len(entries) == 1
repo, hook = entries[0]
assert repo['repo'] == 'local' and hook['language'] == 'system'
assert hook['entry'] == 'shellcheck' and hook['args'] == ['--severity=warning']
assert 'native `shellcheck`' in (root / 'CONTRIBUTING.md').read_text()
PY_CONFIG
}

@test "local and CI Bandit exclude only the intentional unsafe fixture among canaries" {
    python3 - "$REPO_ROOT" <<'PY_CONFIG'
import re
import sys
from pathlib import Path
import yaml
root = Path(sys.argv[1])
config = yaml.safe_load((root / '.pre-commit-config.yaml').read_text())
repo, hook = next((repo, hook) for repo in config['repos'] for hook in repo['hooks']
                  if hook['id'] == 'bandit')
assert repo['rev'] == '1.9.4'
assert hook['args'] == ['-ll', '-ii']
pattern = re.compile(hook['exclude'])
assert pattern.fullmatch('tests/security/fixtures/sast-unsafe.py')
for path in ['tests/security/fixtures/sast-clean.py', 'scripts/example.py',
             'tests/security/fixtures/sast-unsafe.py.extra',
             'tests/security/fixtures/new-product.py']:
    assert not pattern.search(path), path
ci = yaml.safe_load((root / '.github/workflows/security.yml').read_text())
steps = ci['jobs']['bandit']['steps']
run = next(step['run'] for step in steps if step.get('name') == 'Run bandit on .py files')
assert '-x ./_extracted,./.git,./tests/security/fixtures/sast-unsafe.py\n' in run
assert "-not -path './tests/security/fixtures/sast-unsafe.py'" in run
assert any(step.get('run') == 'python3 tests/security/check-bandit-controls.py' for step in steps)
PY_CONFIG
}

@test "Bandit rejects the exact unsafe controls and accepts the clean canary" {
    # CI's bandit job executes this same direct control. The regression-bats
    # job lacks Bandit by design, so do not confuse unavailable tooling with PASS.
    if ! command -v bandit >/dev/null 2>&1; then
        skip "Bandit controls run separately in the required bandit CI job"
    fi
    run python3 "$REPO_ROOT/tests/security/check-bandit-controls.py"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"B307", "B602"'* ]]
}
