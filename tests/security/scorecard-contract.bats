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
