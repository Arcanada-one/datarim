#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
}

@test "retired TALO replay surface is absent while research evidence remains" {
  cd "$REPO_ROOT"
  retired=(
    .github/actionlint.yaml
    .github/workflows/talo-0001-trusted-replay.yml
    dev-tools/check-talo-0001-workflow-contract.py
    dev-tools/check-talo-0001-trusted-authority.py
    dev-tools/preflight-talo-0001-workflow-run.sh
    dev-tools/provision-talo-0001-trusted-runner.sh
    dev-tools/publish-talo-0001-check.sh
    dev-tools/trusted-talo-0001-replay.sh
    dev-tools/systemd/talo-0001-trusted-runner.service
    dev-tools/tests/check-talo-0001-workflow-contract.bats
    dev-tools/tests/fixtures/talo-0001-command-mock.sh
  )
  for path in "${retired[@]}"; do
    [ ! -e "$path" ]
  done
  [ -s dev-tools/check-talo-0001-research-projection.py ]
  ! rg -n 'talo-0001-trusted-replay\.yml|trusted-talo-0001-replay\.sh' \
    .github dev-tools tests --glob '!tests/security/scorecard-contract.bats'
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
for path in Path('.github/workflows').glob('*.yml'):
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
  grep -F 'workflow_dispatch:' "$workflow"
  grep -F 'release_tag:' "$workflow"
  ! grep -F "tags: ['v*']" "$workflow"
  grep -F 'gpg.ssh.allowedSignersFile=.github/ssh-signing-allowed-signers' "$workflow"
  grep -F 'test "$EXPECTED_REF" = refs/heads/main' "$workflow"
  grep -F 'test "$(git cat-file -t "$tag")" = tag' "$workflow"
  grep -F 'git tag --merged "${release_sha}^" --list' "$workflow"
  grep -F -- '--from "$previous_tag" --to "$release_sha"' "$workflow"
  ! grep -F -- '--from v2.67.1' "$workflow"
  grep -F 'ref: ${{ needs.classify.outputs.release_sha }}' "$workflow"
  [ "$(wc -l < .github/ssh-signing-allowed-signers)" -eq 1 ]
  grep -E '^dev@veritasarcana\.ai ssh-ed25519 [A-Za-z0-9+/=]+$' .github/ssh-signing-allowed-signers
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
