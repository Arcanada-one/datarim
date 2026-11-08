#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
}

@test "framework lint uses generic validators without consumer-private inputs" {
  cd "$REPO_ROOT"
  [ ! -e .github/actionlint.yaml ]
  [ -x dev-tools/check-customer-delivery.sh ]
  run python3 - <<'PY'
from pathlib import Path
import yaml
workflow = yaml.safe_load(Path('.github/workflows/dev-tools-lint.yml').read_text())
assert workflow['permissions'] == {'contents': 'read'}
events = workflow.get('on', workflow.get(True))
assert isinstance(events, dict)
assert all(not path.startswith('datarim/insights/') for path in events['pull_request']['paths'])
for job in workflow['jobs'].values():
    for step in job.get('steps', []):
        for line in step.get('run', '').splitlines():
            assert 'research-projection.py' not in line
            assert 'datarim/insights/' not in line
PY
  [ "$status" -eq 0 ]
}

@test "superseded mutable SHA bridge implementation is absent" {
  cd "$REPO_ROOT"
  retired=(
    .github/workflows/sha-bridge-currency-audit.yml
    dev-tools/sha-bridge-audit.sh
    tests/sha-bridge-audit.bats
    dev-tools/.state/sha-bridge-audit.state.decommissioned_at
  )
  for path in "${retired[@]}"; do
    [ ! -e "$path" ]
  done
  ! rg -n 'sha-bridge-currency-audit|sha-bridge-audit\.sh' \
    .github dev-tools tests --glob '!tests/security/scorecard-contract.bats'
}

@test "Python tools installed by workflows are exactly version pinned" {
  cd "$REPO_ROOT"
  run python3 - <<'PY'
from pathlib import Path
bad = []
paths = list(Path('.github/workflows').glob('*.yml'))
paths += list(Path('.github/scripts/workflow').glob('*.sh'))
for path in paths:
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if ('pip install' in line or 'pipx install' in line) and '==' not in line and '--require-hashes' not in line:
            bad.append(f'{path}:{number}:{line.strip()}')
if bad:
    raise SystemExit('\n'.join(bad))
PY
  [ "$status" -eq 0 ]
}

@test "SAST is exact-head local Semgrep plus Python CodeQL" {
  cd "$REPO_ROOT"
  for rule in datarim.python.subprocess-shell-true datarim.python.dynamic-eval; do
    grep -F "$rule" .semgrep.yml
  done
  grep -F 'github.event.pull_request.head.sha || github.sha' .github/workflows/security.yml
  ! grep -n -- '--config p/' .github/workflows/security.yml
  [ "$(grep -c 'security-events: write' .github/workflows/security.yml)" -eq 2 ]
}

@test "Dependabot write authority is bound to the complete trusted event tuple" {
  cd "$REPO_ROOT"
  workflow=.github/workflows/dependabot-auto-merge.yml
  grep -F 'github.event.sender.id == 49699333' "$workflow"
  grep -F 'github.event.pull_request.user.id == 49699333' "$workflow"
  grep -F 'github.event.pull_request.head.repo.full_name == github.repository' "$workflow"
  grep -F "github.event.pull_request.base.ref == 'main'" "$workflow"
  grep -F "startsWith(github.event.pull_request.head.ref, 'dependabot/')" "$workflow"
  grep -F 'startsWith(github.event.pull_request.html_url' "$workflow"
  ! grep -F 'actions/checkout' "$workflow"
}

@test "release authority is trusted main plus one SSH-signed annotated tag" {
  cd "$REPO_ROOT"
  workflow=.github/workflows/release.yml
  classify_helper=.github/scripts/workflow/release-classify-01-authenticate-signed-tag-on-protected-main-and-cl.sh
  validate_helper=.github/scripts/workflow/release-release-01-validate-tag-format.sh
  surface="$BATS_TEST_TMPDIR/release-surface.txt"
  cat "$workflow" .github/scripts/workflow/release-*.sh >"$surface"
  verifier=dev-tools/verify-release-tag.sh
  grep -F 'workflow_dispatch:' "$workflow"
  grep -F 'release_tag:' "$workflow"
  ! grep -F "tags: ['v*']" "$workflow"
  grep -F '[[ "$workflow_ref" == refs/heads/main ]]' "$verifier"
  grep -F 'gpg.ssh.allowedSignersFile=$allowed_signers' "$verifier"
  grep -F 'verify-tag "$ref"' "$verifier"
  grep -F '[[ "$(git -C "$repo" cat-file -t "$ref")" == tag ]]' "$verifier"
  grep -F 'merge-base --is-ancestor "$fetched_sha" "$main_sha"' "$verifier"
  grep -F 'bash .github/scripts/workflow/release-classify-01-authenticate-signed-tag-on-protected-main-and-cl.sh' "$workflow"
  grep -F 'dev-tools/verify-release-tag.sh classify' "$classify_helper"
  grep -F 'git tag --merged "${release_sha}^" --list' "$classify_helper"
  grep -F 'classification_sha="$release_sha"' "$classify_helper"
  grep -F -- '--from "$previous_tag" --to "$classification_sha"' "$classify_helper"
  grep -F 'python3 dev-tools/check-history-bootstrap.py --repo . --mode release' "$classify_helper"
  grep -F -- '--source-sha "$source_sha" --release-sha "$release_sha" --tree-sha "$tree_sha"' "$classify_helper"
  grep -F 'classification_sha="$source_sha"' "$classify_helper"
  ! grep -F -- '--from v2.67.1' "$surface"
  grep -F 'ref: ${{ needs.classify.outputs.release_sha }}' "$workflow"
  [ "$(wc -l < .github/ssh-signing-allowed-signers)" -eq 1 ]
  grep -E '^Arcanada ssh-ed25519 [A-Za-z0-9+/=]+$' .github/ssh-signing-allowed-signers
  run python3 - <<'PY'
from pathlib import Path
import yaml
workflow = yaml.safe_load(Path('.github/workflows/release.yml').read_text())
classify_helper = Path('.github/scripts/workflow/release-classify-01-authenticate-signed-tag-on-protected-main-and-cl.sh').read_text()
validate_helper = Path('.github/scripts/workflow/release-release-01-validate-tag-format.sh').read_text()
classify = workflow['jobs']['classify']
assert classify['outputs']['root_release'] == '${{ steps.read.outputs.root_release }}'
read = next(step for step in classify['steps'] if step.get('id') == 'read')
assert 'release-classify-01-authenticate-signed-tag-on-protected-main-and-cl.sh' in read['run']
assert 'root_release=false' in classify_helper and 'root_release=true' in classify_helper
assert 'echo "root_release=${root_release}"' in classify_helper
release = workflow['jobs']['release']
validate = next(step for step in release['steps'] if step.get('name') == 'Validate tag format')
assert validate['env']['RELEASE_TAG'] == '${{ needs.classify.outputs.release_tag }}'
assert 'release-release-01-validate-tag-format.sh' in validate['run']
assert 'tag="$RELEASE_TAG"' in validate_helper
assert 'echo "TAG=$tag"' in validate_helper and '"$GITHUB_ENV"' in validate_helper
publish = next(step for step in release['steps'] if step.get('name') == 'Publish GitHub Release')['with']
assert publish['tag_name'] == '${{ env.TAG }}'
assert publish['generate_release_notes'] == "${{ needs.classify.outputs.root_release != 'true' }}"
assert 'https://github.com/Arcanada-one/datarim/blob/${{ env.TAG }}/CHANGELOG.md' in publish['body']
assert '/compare/' not in publish['body']
PY
  [ "$status" -eq 0 ]
}

@test "Scorecard residuals are explicitly bounded and re-evaluated" {
  cd "$REPO_ROOT"
  for marker in \
    "Token-Permissions / release" \
    "Token-Permissions / Dependabot" \
    "Code-Review" \
    "Fuzzing" \
    "CII Best Practices"
  do
    grep -F "$marker" SECURITY.md
  done
  grep -F "accepted limitations, not silent exceptions" SECURITY.md
  grep -F "must be reopened if the trust model or executable surface changes" SECURITY.md
}
