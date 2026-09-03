# TUNE-0599 Security Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `subagent-driven-development` (recommended, when your runtime supports spawning isolated agents) or `executing-plans` (single-session execution) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the twelve Scorecard alerts observed on `main` commit `6da8163963b778cce201d42abc745e804129401e` with fail-closed controls, explicitly accept only irreducible residuals, ship patch release `v2.67.2`, prove the release and fleet/site rollout, and finish with one clean `main` and complete TUNE-0599 evidence.

**Architecture:** Remove two obsolete privileged automation seams after measured decommission proofs, centralize every Python CI tool behind fully transitive hash locks, add immutable local SAST rules plus Python CodeQL on the exact event head, and authenticate automation from the complete GitHub event tuple. Move release authority from arbitrary tag-pushed workflow code to the workflow on protected `main`: an SSH-signed annotated SemVer tag must peel to the exact protected-main commit whose required resulting-main checks succeeded and verify against a tracked public trust root. After the code squash merge, clean the implementation lane, create a fresh exact-`origin/main` release/evidence worktree, install branch/tag/environment controls transactionally, and treat Datarim CI, Scorecard, release attestations, canonical site, workspace mirror, four-node fleet, KB runtime closure, workspace ledgers, post-release evidence, and final cleanup as separate gates.

**Tech Stack:** Bash, Bats, Python 3.9/3.12, pip-tools hash locks, GitHub Actions, GitHub REST API through `gh`, Semgrep SARIF, CodeQL Python, Cosign bundle mode, GitHub artifact attestations, Git SSH signing, PHP public-site surfaces, SSH/systemd fleet operations.

---

## Execution invariants

- The implementation worktree is `/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE`; the canonical Datarim root is `/home/dev/datarim-src`; the fresh post-merge release/evidence worktree is `/home/dev/.worktrees/datarim/TUNE-0599-RELEASE-EVIDENCE`; the canonical workspace root is `/home/dev/arcanada`; and the canonical site-repository root is `/home/dev/arcanada/Projects/Websites/datarim.club`. Every command below names its repository/worktree explicitly; no command inherits repository identity from a prior `cd`.
- Start from and preserve Datarim baseline/current `origin/main` `6da8163963b778cce201d42abc745e804129401e`. If either implementation `HEAD` or freshly fetched `origin/main` differs before the first implementation commit, stop and remap the plan.
- Before Task 2, the only allowed dirty entry is `?? datarim/plans/TUNE-0599-security-closure-plan.md`. Task 2 commits that plan. From Task 2 onward every task starts and ends with a clean tracked checkout except while its exact mapped change is in progress.
- Use isolated worktrees; never implement in a dirty shared checkout. Before every commit, compare `git -C <worktree> diff --name-only` with that task's exact file list.
- Strict TDD is mandatory. Run `bash /home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE/scripts/tdd-enforcement-state.sh` and require `required`. Each production change follows an observed, relevant RED test; tests are not weakened after RED.
- TALO and SHA-bridge deletion are hard-gated by current external proofs. Inaccessible, nonterminal, or contradictory evidence means `BLOCKED`.
- Preserve `datarim/insights/INSIGHTS-TALO-0001.md`, `datarim/insights/TALO-0001-research-authority-audit.json`, all archives/history, and unrelated Git state.
- Never check out or execute Dependabot candidate code in `pull_request_target`.
- Never run `gh auth switch`, impersonate `PavelValentov`, or create an approval in another principal's name. Record and retain the authenticated principal.
- Never call an accepted risk fixed. Use **accepted residual risk** for unavoidable release/Dependabot permissions and single-principal review, CII, and fuzzing residuals.
- Local, PR-head, resulting-main, release, deploy, live, and fleet evidence are distinct gates.
- No release, deploy, dismissal, GitHub policy mutation, or cleanup occurs until its preceding gate is green.
- All temporary policy, evidence, key, installer, and API snapshots are task-owned under a `mktemp -d` root, mode `0700`; JSON/key files are mode `0600`. Never store a private signing key, token, credential payload, or secret-bearing host file in Git or task evidence.
- Source retirement may merge before `/srv/talo-0001-trusted` is removed. Runtime removal occurs only after that code merge and fresh root inspection proves no credential/secret content, knowledge-commit ancestry to current `Arcanada-one/arcanada-workspace` main, and mode-only/no unique data.
- The immutable release commit does not claim later site/fleet/KB/archive facts. Those facts land only in distinct post-release evidence commits after direct proof.

## Exact file map

No repository file outside this map may change. Generated locks are committed source artifacts.

### Datarim repository — create

- `datarim/plans/TUNE-0599-security-closure-plan.md` — this executable reviewed plan; the sole allowed pre-Task-2 untracked path.
- `.github/ssh-signing-allowed-signers` — tracked public SSH signing trust root derived only from the existing public key; principal equals the measured tagger identity.

- `requirements/ci/bandit.in` — `bandit==1.9.4`.
- `requirements/ci/bandit-py312.txt` — fully transitive Python 3.12 hash lock.
- `requirements/ci/semgrep.in` — `semgrep==1.176.0`.
- `requirements/ci/semgrep-py312.txt` — fully transitive Python 3.12 hash lock.
- `requirements/ci/zizmor.in` — `zizmor==1.30.0`.
- `requirements/ci/zizmor-py312.txt` — fully transitive Python 3.12 hash lock.
- `requirements/ci/pip-audit.in` — `pip-audit==2.10.1`.
- `requirements/ci/pip-audit-py312.txt` — fully transitive Python 3.12 hash lock.
- `requirements/ci/schemathesis.in` — `schemathesis==4.25.2`.
- `requirements/ci/schemathesis-py312.txt` — fully transitive Python 3.12 hash lock.
- `requirements/ci/bats-python.in` — `jsonschema==4.23.0`, `rfc3339-validator==0.1.4`, `pyyaml==6.0.2`, `cryptography==43.0.3`.
- `requirements/ci/bats-python-py39.txt` — fully transitive Python 3.9 hash lock.
- `requirements/ci/bats-python-py312.txt` — fully transitive Python 3.12 hash lock.
- `.semgrep.yml` — immutable local Python security rules.
- `tests/ci-python-locks.bats` — lock shape, cold install, version, and bad-hash tests.
- `tests/security/fixtures/sast-unsafe.py` — unsafe fixture used only by SAST tests.
- `tests/security/fixtures/sast-clean.py` — equivalent safe fixture.
- `tests/security/sast-fixtures.bats` — unsafe/clean SARIF and workflow contract tests.
- `dev-tools/check-dependabot-event.py` — complete event-tuple validator.
- `tests/dependabot-auto-merge.bats` — valid and mutated tuple plus no-checkout tests.
- `dev-tools/release-trust-gate.sh` — signed-tag/exact-main/check/classifier gate.
- `tests/release-trust-gate.bats` — adversarial release-trust tests.
- `tests/security/scorecard-contract.bats` — retirement, permission, policy, and risk contract.
- `documentation/release-audit/release-2.67.2.md` — final release/site/fleet evidence.
- `documentation/archive/framework/archive-TUNE-0599.md` — final twelve-alert closure evidence.

### Datarim repository — modify

- `.github/dependabot.yml` — update locks under `/requirements/ci`.
- `.github/workflows/bats.yml` — use hashed Python 3.9/3.12 Bats locks.
- `.github/workflows/dependabot-auto-merge.yml` — validate the full tuple, no checkout.
- `.github/workflows/dev-tools-lint.yml` — remove only the retired replay path; retain research projection gates.
- `.github/workflows/dr-orchestrate-contract.yml` — use the Schemathesis lock.
- `.github/workflows/release.yml` — use protected-main workflow code and publish one checked SHA.
- `.github/workflows/reusable-security-audit.yml` — hash-lock pip-audit.
- `.github/workflows/security.yml` — hash-lock tools; add exact-head Semgrep SARIF and Python CodeQL.
- `.github/environments-policy.yml` — authorize protected `main` for Datarim release.
- `dev-tools/check-release-env-policy.sh` — validate that policy fail-closed.
- `dev-tools/provision-release-env.sh` — provision/read back tag plus `main` deployment policy.
- `dev-tools/release-gate.sh` — signed annotated tag and trusted-main dispatch.
- `tests/ci-install-bats-deps.sh` — choose the interpreter-specific hash lock.
- `tests/bats-discovery-coverage.bats` — replace bare-install expectations and cover new suites.
- `tests/check-release-env-policy.bats` — main-policy rejection/acceptance.
- `tests/provision-release-env.bats` — exact API payload tests.
- `tests/release-gate.bats` — signed tag, classifier, dispatch tests.
- `tests/test-role-registry.bats` — replace the bare-pip operator hint with the hashed Bats lock command.
- `tests/security/baseline.json` — honest SAST/automation control state.
- `tests/security/run-all.sh` — include new security contract tests.
- `SECURITY.md` — five bounded accepted residual risks.
- `documentation/how-to/provision-release-environment.md` — protected-main environment procedure.
- `documentation/how-to/release-process.md` — signed tag plus trusted-main dispatch.
- `documentation/how-to/release-verification.md` — `refs/heads/main` identity and tag/SHA proof.
- `skills/release-verify/SKILL.md` — same consumer identity contract.
- `VERSION`, `CHANGELOG.md`, `README.md`, `CLAUDE.md` — patch version/public release surfaces.

### Datarim repository — delete

- `.github/actionlint.yaml` — only permits retired label `talo-0001-trusted`.
- `.github/workflows/talo-0001-trusted-replay.yml`
- `dev-tools/check-talo-0001-workflow-contract.py`
- `dev-tools/check-talo-0001-trusted-authority.py`
- `dev-tools/preflight-talo-0001-workflow-run.sh`
- `dev-tools/provision-talo-0001-trusted-runner.sh`
- `dev-tools/publish-talo-0001-check.sh`
- `dev-tools/trusted-talo-0001-replay.sh`
- `dev-tools/systemd/talo-0001-trusted-runner.service`
- `dev-tools/tests/check-talo-0001-workflow-contract.bats`
- `dev-tools/tests/fixtures/talo-0001-command-mock.sh`
- `.github/workflows/sha-bridge-currency-audit.yml`
- `dev-tools/sha-bridge-audit.sh`
- `tests/sha-bridge-audit.bats`
- `dev-tools/.state/sha-bridge-audit.state.decommissioned_at`

### Arcanada workspace mirror repository — modify in a separate clean worktree and PR

- `Projects/Datarim/CLAUDE.md` — public version `2.67.2`.
- `Projects/Datarim/README.md` — public version `2.67.2`.
- `Projects/Websites/datarim.club/config.php` — tracked workspace mirror of site version `2.67.2`; never deploy from this repository.
- `Projects/Websites/datarim.club/pages/changelog.php` — tracked workspace mirror of the bilingual release entry; never deploy from this repository.
- `spaces/arcanada/space.yml` — fleet pin `v2.67.2`, exact release SHA, and four-node target set.

### Datarim site repository (`Arcanada-one/datarim-club-site`) — modify in its own clean worktree and PR

- `config.php` — canonical deployable site version `2.67.2`.
- `pages/changelog.php` — canonical English/Russian visible release entry.

### Arcanada workspace closure repository — create or reuse in a final isolated worktree/PR

- `documentation/archive/infrastructure/archive-INFRA-0476.md`
- `documentation/archive/search/archive-SRCH-0037.md`
- `documentation/archive/search/archive-SRCH-0044.md`
- `documentation/archive/research/archive-LTM-0026.md`
- `documentation/archive/infrastructure/archive-INFRA-0264.md`
- `documentation/archive/research/archive-LTM-0009.md` — reuse and amend the existing archive; do not create a duplicate.
- `documentation/archive/search/archive-SRCH-0052.md`
- `documentation/archive/search/archive-SRCH-0053.md`
- `documentation/archive/arcanada-ecosystem/archive-ARCA-0192.md`
- `documentation/archive/research/archive-LTM-0027.md`
- `documentation/archive/search/archive-SRCH-0060.md`
- `documentation/archive/infrastructure/archive-INFRA-0493.md`
- `documentation/archive/infrastructure/archive-INFRA-0494.md`
- `documentation/archive/search/archive-SRCH-0057.md`
- `documentation/archive/research/archive-LTM-0025.md`
- `documentation/archive/research/archive-LTM-0014.md`
- `documentation/archive/research/archive-LTM-0021.md`
- `documentation/archive/arcanada-ecosystem/archive-ARCA-0191.md`
- `documentation/archive/search/archive-SRCH-0054.md`
- `documentation/archive/framework/archive-TUNE-0599.md`
- `datarim/backlog.md`, `datarim/tasks.md`, `datarim/activeContext.md` — remove only rows for the exact related-ID allowlist above and retain every unrelated legacy row.

## Baseline evidence and hard stops

### Task 1: Freeze identity, alert inventory, and retirement prerequisites

**Files:** none.

- [ ] **Step 1: Prove exact local source, the single allowed untracked path, and TDD policy**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
test "$(git -C "$DR_IMPL" rev-parse HEAD)" = 6da8163963b778cce201d42abc745e804129401e
git -C "$DR_IMPL" fetch origin main
test "$(git -C "$DR_IMPL" rev-parse origin/main)" = 6da8163963b778cce201d42abc745e804129401e
test "$(git -C "$DR_IMPL" status --porcelain --untracked-files=all)" = \
  '?? datarim/plans/TUNE-0599-security-closure-plan.md'
test "$(bash "$DR_IMPL/scripts/tdd-enforcement-state.sh")" = required
test "$(git -C "$DR_IMPL" remote get-url origin)" = git@github.com:Arcanada-one/datarim.git
gh api user --jq .login
```

Expected: all tests exit `0`; the plan is the one and only allowed pre-Task-2 untracked path; record the authenticated login without changing it.

- [ ] **Step 2: Create a private task state/tool root and provision pinned tools without ambient bare-tool dependence**

Use `/tmp/TUNE-0599-SECURITY-CLOSURE-state` only for this task. On resume, require the existing directory to be owned by the current user and mode `0700`; otherwise stop. Put standalone binaries in `bin/`, Python tools in task-owned venvs, retain downloaded checksum manifests, and record every version/hash in `tool-provenance.txt` mode `0600`.

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
STATE_DIR=/tmp/TUNE-0599-SECURITY-CLOSURE-state
if test -e "$STATE_DIR"; then
  test -d "$STATE_DIR"
  test "$(stat -c %U "$STATE_DIR")" = "$(id -un)"
  test "$(stat -c %a "$STATE_DIR")" = 700
else
  install -d -m 0700 "$STATE_DIR"
fi
install -d -m 0700 "$STATE_DIR/bin" "$STATE_DIR/downloads"
install -m 0600 /dev/null "$STATE_DIR/tool-provenance.txt"
python3.12 -m venv "$STATE_DIR/py312"
"$STATE_DIR/py312/bin/python" -m pip install --disable-pip-version-check pip-tools==7.6.1
```

Provision `actionlint` `1.7.7`, `gitleaks` `8.30.1` (expected Linux x64 archive SHA-256 `551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb`), `trufflehog` `3.83.7`, and `osv-scanner` `2.3.5` into `$STATE_DIR/bin` using the exact download/checksum recipes pinned in `"$DR_IMPL/.github/workflows/security.yml"`; provision `cosign` `v3.0.6` with expected SHA-256 `c956e5dfcac53d52bcf058360d579472f0c1d2d9b69f55209e256fe7783f4c74` from `"$DR_IMPL/.github/workflows/release.yml"`; and provision `uv` `0.12.3` from the exact GitHub release asset only after its published checksum verifies. Downloads use `curl -fL --proto '=https' --tlsv1.2`; compare the selected asset to the pinned or upstream checksum before extraction; install only into `$STATE_DIR/bin`; never use `sudo` or `/usr/local/bin`. After Task 4 creates locks, install Bandit, Semgrep, and zizmor into `$STATE_DIR/py312` with `--require-hashes` from their mapped lock files. Every later local gate invokes `"$STATE_DIR/bin/<tool>"` or `"$STATE_DIR/py312/bin/<tool>"`, never a bare ambient executable.

- [ ] **Step 3: Capture exactly twelve open Scorecard alerts and bind the original tuple inventory**

```bash
gh api --paginate 'repos/Arcanada-one/datarim/code-scanning/alerts?state=open&tool_name=Scorecard&per_page=100' \
  --slurp > /tmp/TUNE-0599-SECURITY-CLOSURE-state/scorecard-original-pages.json
chmod 0600 /tmp/TUNE-0599-SECURITY-CLOSURE-state/scorecard-original-pages.json
jq -e 'add | map({number,rule:.rule.id,path:(.most_recent_instance.location.path//null),commit:.most_recent_instance.commit_sha}) | sort_by(.number) |
  map(.number) == [1,8,10,11,12,14,15,22,25,29,30,31] and
  all(.[]; .commit == "6da8163963b778cce201d42abc745e804129401e")' \
  /tmp/TUNE-0599-SECURITY-CLOSURE-state/scorecard-original-pages.json
jq 'add | map({number,rule:.rule.id,path:(.most_recent_instance.location.path//null),commit:.most_recent_instance.commit_sha}) | sort_by(.number)' \
  /tmp/TUNE-0599-SECURITY-CLOSURE-state/scorecard-original-pages.json
```

Expected: `1 BranchProtectionID`; `8 TokenPermissionsID` at `release.yml`; `10 CIIBestPracticesID`; `11 CodeReviewID`; `12 FuzzingID`; `14 SASTID`; `15 TokenPermissionsID` at `dependabot-auto-merge.yml`; `22 PinnedDependenciesID` at `dr-orchestrate-contract.yml`; `25 PinnedDependenciesID` at `reusable-security-audit.yml`; `29 TokenPermissionsID` at `sha-bridge-currency-audit.yml`; and `30`, `31 TokenPermissionsID` at `talo-0001-trusted-replay.yml`.

- [ ] **Step 4: Prove PR 394 exact closed-unmerged identity and no GitHub runner remains**

```bash
gh pr view 394 --repo Arcanada-one/datarim --json state,mergedAt,closedAt,headRefName,headRefOid,baseRefName \
  | tee /tmp/TUNE-0599-SECURITY-CLOSURE-state/pr394.json
chmod 0600 /tmp/TUNE-0599-SECURITY-CLOSURE-state/pr394.json
jq -e '.state=="CLOSED" and .mergedAt==null and .baseRefName=="main" and
  .headRefOid=="10bba642735323c7eb9f9ec55d2b681f2de4a350"' \
  /tmp/TUNE-0599-SECURITY-CLOSURE-state/pr394.json
gh api repos/Arcanada-one/datarim/actions/runners --jq '{total_count,runners}'
repo_id=$(gh api repos/Arcanada-one/datarim --jq .id)
for group_id in $(gh api --paginate 'orgs/Arcanada-one/actions/runner-groups?per_page=100' --jq '.runner_groups[].id'); do
  gh api --paginate "orgs/Arcanada-one/actions/runner-groups/${group_id}/repositories?per_page=100" --slurp \
    | jq -e --argjson id "$repo_id" 'add | all(.repositories[]?; .id != $id)'
done
```

Expected: PR `394` is `CLOSED`, `mergedAt:null`, base `main`, at exact head `10bba642735323c7eb9f9ec55d2b681f2de4a350`; repo runner count `0`; every paginated runner-group page excludes Datarim. Drift stops Task 2.

- [ ] **Step 5: Prove the measured dedicated-host partial state without a self-matching process probe**

```bash
ssh arcana-devs 'set -euo pipefail
test "$(hostname)" = arcana-devs
test -d /srv/talo-0001-trusted
test "$(stat -c %a /srv/talo-0001-trusted)" = 550
test "$(stat -c %U:%G /srv/talo-0001-trusted)" = nobody:nogroup
test ! -e /etc/systemd/system/talo-0001-trusted-runner.service
test ! -e /etc/systemd/system/multi-user.target.wants/talo-0001-trusted-runner.service
test ! -d /srv/talo-0001-trusted/runner
test "$(systemctl show -p LoadState --value talo-0001-trusted-runner.service)" = not-found
test "$(systemctl show -p MainPID --value talo-0001-trusted-runner.service)" = 0
test -z "$(ps -eo pid=,comm=,args= | awk '\''$2=="Runner.Listener" && $0 ~ /talo-0001-trusted/ {print}'\'')"'
```

Expected: the root exists at measured mode/owner, while runner subtree, unit, symlink, and actual listener process are absent. This permits source retirement but does not call the root retired; Task 13 owns its later guarded deletion.

- [ ] **Step 6: Compare the mutable v1 target and active consumers**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
remote_v1=$(git -C "$DR_IMPL" ls-remote --tags origin refs/tags/v1 | awk 'NR==1{print $1}')
test "$remote_v1" = bd061a7acf7c167b8dd683a5a03f659a3c62083b
git -C "$DR_IMPL" fetch --force origin refs/tags/v1:refs/tags/v1
test "$(git -C "$DR_IMPL" cat-file -t v1)" = commit
test "$(git -C "$DR_IMPL" rev-parse v1)" = "$remote_v1"
gh api repos/Arcanada-one/arcanada-workspace/contents/documentation/infrastructure/CI-Runners.md?ref=main --jq .content \
  | tr -d '\n' | base64 -d > /tmp/TUNE-0599-SECURITY-CLOSURE-state/ci-runners.md
chmod 0600 /tmp/TUNE-0599-SECURITY-CLOSURE-state/ci-runners.md
grep -Eq '^[[:space:]]*uses:[[:space:]]*Arcanada-one/datarim/.github/workflows/reusable-security-audit.yml@v1([[:space:]]|$)' /tmp/TUNE-0599-SECURITY-CLOSURE-state/ci-runners.md
! grep -E '^[[:space:]]*uses:.*reusable-security-audit.yml@[0-9a-f]{40}([[:space:]]|$)' /tmp/TUNE-0599-SECURITY-CLOSURE-state/ci-runners.md
gh api repos/Arcanada-one/arcanada-workspace/contents/documentation/mandates/preflight-mandate.md?ref=main --jq .content \
  | tr -d '\n' | base64 -d | grep -Eq 'reusable-security-audit.yml@v1([[:space:]`]|$)'
```

Expected: local and remote `v1` both equal `bd061a7acf7c167b8dd683a5a03f659a3c62083b`; active consumers use `@v1`; no executable `uses:` has an old SHA. A target mismatch blocks SHA-bridge deletion. Preserve historical prose. Task 14 installs immutable no-update/no-delete host protection before any later release/archive mutation.

- [ ] **Step 7: Snapshot current GitHub policy readback as private rollback inputs**

```bash
STATE_DIR=/tmp/TUNE-0599-SECURITY-CLOSURE-state
gh api repos/Arcanada-one/datarim/actions/permissions/workflow > "$STATE_DIR/workflow-permissions.before.json"
gh api repos/Arcanada-one/datarim/rulesets/15879567 > "$STATE_DIR/branch-ruleset.before.json"
gh api repos/Arcanada-one/datarim/rulesets > "$STATE_DIR/rulesets.before.json"
gh api repos/Arcanada-one/datarim/branches/main/protection > "$STATE_DIR/classic-protection.before.json"
for env_name in release-auto release-manual; do
  gh api "repos/Arcanada-one/datarim/environments/${env_name}" > "$STATE_DIR/environment-${env_name}.before.json"
  gh api --paginate "repos/Arcanada-one/datarim/environments/${env_name}/deployment-branch-policies?per_page=100" --slurp \
    > "$STATE_DIR/environment-${env_name}-branches.before.json"
done
chmod 0600 "$STATE_DIR"/*.json
jq -e . "$STATE_DIR"/*.json >/dev/null
```

Expected: current workflow/ruleset/classic/environment JSON is complete, valid, private, and available for bounded rollback; workflow default is `read` with approvals true; ruleset `15879567` is active/default/no bypass but deletion-only; classic protection is strict false, with no reviews/conversation-resolution. Any empty/invalid snapshot blocks every later settings mutation.

## Remove obsolete privileged seams

### Task 2: Retire TALO trusted replay and preserve research

**Files:** create `datarim/plans/TUNE-0599-security-closure-plan.md`, `tests/security/scorecard-contract.bats`; modify `.github/workflows/dev-tools-lint.yml`, `tests/security/run-all.sh`; delete the eleven TALO paths in the map.

- [ ] **Step 1: Write RED retirement tests**

Enumerate all eleven retired paths and assert each absent; assert the two TALO research files and their dev-tools-lint triggers remain; assert no non-archive tracked file contains `talo-0001-trusted`, `/srv/talo-0001-trusted`, or the unit name. Register the suite in `tests/security/run-all.sh`.

- [ ] **Step 2: Verify RED**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
(cd "$DR_IMPL" && bats tests/security/scorecard-contract.bats)
```

Expected: fails because `.github/workflows/talo-0001-trusted-replay.yml` still exists, not from syntax/fixture error.

- [ ] **Step 3: Delete the exact bundle and narrow lint paths**

Delete only the eleven mapped paths. In `.github/workflows/dev-tools-lint.yml`, remove only the replay workflow path; retain the insight Markdown/JSON and `check-talo-0001-research-projection.py` triggers/job. Do not edit research data.

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
git -C "$DR_IMPL" rm .github/actionlint.yaml .github/workflows/talo-0001-trusted-replay.yml \
  dev-tools/check-talo-0001-workflow-contract.py dev-tools/check-talo-0001-trusted-authority.py \
  dev-tools/preflight-talo-0001-workflow-run.sh dev-tools/provision-talo-0001-trusted-runner.sh \
  dev-tools/publish-talo-0001-check.sh dev-tools/trusted-talo-0001-replay.sh \
  dev-tools/systemd/talo-0001-trusted-runner.service \
  dev-tools/tests/check-talo-0001-workflow-contract.bats \
  dev-tools/tests/fixtures/talo-0001-command-mock.sh
```

Expected: exactly eleven deletion entries. The `.github/workflows/dev-tools-lint.yml` edit removes this one YAML scalar and no job:

```yaml
- '.github/workflows/talo-0001-trusted-replay.yml'
```

- [ ] **Step 4: Verify GREEN**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
STATE_DIR=/tmp/TUNE-0599-SECURITY-CLOSURE-state
(cd "$DR_IMPL" && bats tests/security/scorecard-contract.bats)
test -z "$(git -C "$DR_IMPL" diff --name-status -- datarim/insights)"
git -C "$DR_IMPL" grep -n TALO-0001 -- datarim/insights documentation/archive | head -n 20
(cd "$DR_IMPL" && "$STATE_DIR/bin/actionlint" .github/workflows/dev-tools-lint.yml)
```

Expected: Bats/actionlint pass; insight diff empty; historical evidence remains.

- [ ] **Step 5: Commit isolated retirement**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
git -C "$DR_IMPL" add datarim/plans/TUNE-0599-security-closure-plan.md \
  .github/actionlint.yaml .github/workflows/talo-0001-trusted-replay.yml \
  .github/workflows/dev-tools-lint.yml dev-tools/check-talo-0001-workflow-contract.py \
  dev-tools/check-talo-0001-trusted-authority.py dev-tools/preflight-talo-0001-workflow-run.sh \
  dev-tools/provision-talo-0001-trusted-runner.sh dev-tools/publish-talo-0001-check.sh \
  dev-tools/trusted-talo-0001-replay.sh dev-tools/systemd/talo-0001-trusted-runner.service \
  dev-tools/tests/check-talo-0001-workflow-contract.bats \
  dev-tools/tests/fixtures/talo-0001-command-mock.sh tests/security/scorecard-contract.bats tests/security/run-all.sh
git -C "$DR_IMPL" commit -m "security: retire TALO trusted replay runner"
test -z "$(git -C "$DR_IMPL" status --porcelain --untracked-files=all)"
```

Expected: the plan plus the exact retirement/test paths are committed in one commit, and the worktree is clean. The plan is not left untracked for later clean gates.

### Task 3: Retire the superseded SHA bridge

**Files:** modify `tests/security/scorecard-contract.bats`; delete the four SHA-bridge paths.

- [ ] **Step 1: Extend contract and verify RED**

Assert all four paths absent, tag `v1` exists, and no non-archive workflow/script invokes `sha-bridge-audit.sh`.

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
(cd "$DR_IMPL" && bats tests/security/scorecard-contract.bats)
```

Expected: RED on the still-present workflow/script/test/state.

- [ ] **Step 2: Delete only the four mapped paths and verify GREEN**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
git -C "$DR_IMPL" rm .github/workflows/sha-bridge-currency-audit.yml dev-tools/sha-bridge-audit.sh \
  tests/sha-bridge-audit.bats dev-tools/.state/sha-bridge-audit.state.decommissioned_at
(cd "$DR_IMPL" && bats tests/security/scorecard-contract.bats)
! git -C "$DR_IMPL" grep -n 'sha-bridge-audit\|sha-bridge-currency-audit' -- ':!documentation/archive/**' ':!CHANGELOG.md'
```

Expected: Bats passes; no active reference. Archives/history remain.

- [ ] **Step 3: Commit**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
git -C "$DR_IMPL" add .github/workflows/sha-bridge-currency-audit.yml dev-tools/sha-bridge-audit.sh \
  tests/sha-bridge-audit.bats dev-tools/.state/sha-bridge-audit.state.decommissioned_at \
  tests/security/scorecard-contract.bats
git -C "$DR_IMPL" commit -m "security: retire superseded SHA bridge audit"
```

Expected: only these five paths.

## Hash-lock every Python CI installation

### Task 4: Generate fully transitive interpreter-specific locks

**Files:** create the thirteen `requirements/ci/` files and `tests/ci-python-locks.bats`.

- [ ] **Step 1: Write RED lock-shape tests**

Require exact `==` direct pins; all seven locks; SHA-256 hashes on every requirement; no editable/URL/VCS/unpinned/index override; and a `pip check` in every cold-install path.

- [ ] **Step 2: Verify RED**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
(cd "$DR_IMPL" && bats tests/ci-python-locks.bats)
```

Expected: first failure is missing `requirements/ci/bandit.in`.

- [ ] **Step 3: Create direct inputs exactly**

The first five inputs each contain their single mapped pin. `bats-python.in` contains the four mapped existing pins, one per line. No ranges or compatible-release operators.

- [ ] **Step 4: Compile deterministic transitive hashes**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
STATE_DIR=/tmp/TUNE-0599-SECURITY-CLOSURE-state
for tool in bandit semgrep zizmor pip-audit schemathesis bats-python; do
  "$STATE_DIR/py312/bin/python" -m piptools compile --generate-hashes \
    --resolver=backtracking --allow-unsafe --strip-extras \
    --output-file "$DR_IMPL/requirements/ci/${tool}-py312.txt" "$DR_IMPL/requirements/ci/${tool}.in"
done
if test -x /usr/bin/python3.9; then
  /usr/bin/python3.9 -m venv "$STATE_DIR/py39"
  "$STATE_DIR/py39/bin/python" -m pip install --disable-pip-version-check pip-tools==7.6.1
  "$STATE_DIR/py39/bin/python" -m piptools compile --generate-hashes --resolver=backtracking \
    --allow-unsafe --strip-extras --output-file "$DR_IMPL/requirements/ci/bats-python-py39.txt" \
    "$DR_IMPL/requirements/ci/bats-python.in"
  "$STATE_DIR/py39/bin/python" -VV > "$STATE_DIR/python39-provenance.txt"
else
  uv_sha=$(sha256sum "$STATE_DIR/bin/uv" | awk '{print $1}')
  scp "$STATE_DIR/bin/uv" arcana-devs:/tmp/tune-0599-uv
  ssh arcana-devs "set -euo pipefail; test \"\$(sha256sum /tmp/tune-0599-uv | awk '{print \$1}')\" = '$uv_sha'; chmod 0700 /tmp/tune-0599-uv; /tmp/tune-0599-uv python install 3.9; /tmp/tune-0599-uv run --python 3.9 python -VV > /tmp/tune-0599-python39-provenance.txt"
  scp "$DR_IMPL/requirements/ci/bats-python.in" arcana-devs:/tmp/tune-0599-bats-python.in
  ssh arcana-devs 'set -euo pipefail; /tmp/tune-0599-uv run --python 3.9 --with pip-tools==7.6.1 python -m piptools compile --generate-hashes --resolver=backtracking --allow-unsafe --strip-extras --output-file /tmp/tune-0599-bats-python-py39.txt /tmp/tune-0599-bats-python.in'
  scp arcana-devs:/tmp/tune-0599-bats-python-py39.txt "$DR_IMPL/requirements/ci/bats-python-py39.txt"
  scp arcana-devs:/tmp/tune-0599-python39-provenance.txt "$STATE_DIR/python39-provenance.txt"
fi
chmod 0600 "$STATE_DIR/python39-provenance.txt"
```

Expected: seven fully transitive lock outputs, all records pinned and hashed. If local 3.9 is absent, the `dev` operating user on `arcana-devs` uses the task-owned, hash-verified `uv 0.12.3` binary and literal `uv python install 3.9`; interpreter `-VV` provenance is retained. Never substitute 3.12 output.

- [ ] **Step 5: Verify GREEN and commit**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
(cd "$DR_IMPL" && bats tests/ci-python-locks.bats)
git -C "$DR_IMPL" diff --check
git -C "$DR_IMPL" add requirements/ci tests/ci-python-locks.bats
git -C "$DR_IMPL" commit -m "build: add hashed Python CI dependency locks"
```

Expected: tests pass; commit contains thirteen input/lock files plus the test.

### Task 5: Route every CI install through `--require-hashes`

**Files:** modify `.github/dependabot.yml`, `.github/workflows/bats.yml`, `.github/workflows/dr-orchestrate-contract.yml`, `.github/workflows/reusable-security-audit.yml`, `.github/workflows/security.yml`, `tests/ci-install-bats-deps.sh`, `tests/bats-discovery-coverage.bats`, `tests/ci-python-locks.bats`, `tests/test-role-registry.bats`.

- [ ] **Step 1: Add RED exact-mapping assertions**

Require mappings: Bandit/Semgrep/zizmor to their Python 3.12 locks; pip-audit to its 3.12 lock; Schemathesis to its 3.12 lock; Bats Python to 3.9 on macOS and 3.12 on Linux. Every command uses `python -m pip install --disable-pip-version-check --no-cache-dir --require-hashes -r`. Reject `pipx install`, bare pip, pip upgrade, and unhashed requirements. Require Dependabot pip directory `/requirements/ci`.

- [ ] **Step 2: Verify RED**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
(cd "$DR_IMPL" && bats tests/ci-python-locks.bats tests/bats-discovery-coverage.bats)
```

Expected: failures name current pipx Bandit/Semgrep/zizmor, pip-audit bootstrap, Schemathesis, and Bats direct installs.

- [ ] **Step 3: Make minimal installer changes**

Replace each install with its mapped lock. `tests/ci-install-bats-deps.sh` selects only `3.9` or `3.12` from `sys.version_info`; another minor exits nonzero. Preserve `--target "$target"` together with `--require-hashes -r "$lock"`. Do not upgrade pip in CI.

In `tests/test-role-registry.bats`, replace both comment/skip suggestions with `python3 -m pip install --disable-pip-version-check --no-cache-dir --require-hashes -r requirements/ci/bats-python-py312.txt`; the test must not teach an unhashed escape path.

Every workflow replacement uses this exact command shape with the mapped filename substituted literally, never a computed remote input:

```yaml
- name: Install hash-locked Python tool
  run: python -m pip install --disable-pip-version-check --no-cache-dir --require-hashes -r requirements/ci/semgrep-py312.txt
```

Use the same line with `bandit-py312.txt`, `zizmor-py312.txt`, `pip-audit-py312.txt`, or `schemathesis-py312.txt` in its owning workflow. The Bats installer selects its lock with this complete branch:

```bash
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY_MINOR="$($PYTHON_BIN -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
case "$PY_MINOR" in
  3.9) PY_LOCK="$REPO_ROOT/requirements/ci/bats-python-py39.txt" ;;
  3.12) PY_LOCK="$REPO_ROOT/requirements/ci/bats-python-py312.txt" ;;
  *) echo "ERROR: unsupported CI Python minor: $PY_MINOR" >&2; exit 2 ;;
esac
if [[ -n "$PYTHON_SITE" ]]; then
  "$PYTHON_BIN" -I -S -c '
import runpy, sys
target, lock = sys.argv[1:]
sys.path.insert(0, target)
sys.argv = ["pip", "install", "--quiet", "--disable-pip-version-check", "--no-cache-dir", "--require-hashes", "--target", target, "-r", lock]
runpy.run_module("pip", run_name="__main__")
' "$PYTHON_SITE" "$PY_LOCK"
else
  "$PYTHON_BIN" -m pip install --quiet --disable-pip-version-check --no-cache-dir \
    --require-hashes -r "$PY_LOCK"
fi
```

- [ ] **Step 4: Prove cold installs and exact versions**

Each test uses a new venv, `--no-cache-dir --require-hashes`, and `pip check`. Require Bandit `1.9.4`, Semgrep `1.176.0`, zizmor `1.30.0`, pip-audit `2.10.1`, Schemathesis `4.25.2`.

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
(cd "$DR_IMPL" && CI_LOCK_COLD_INSTALL=1 bats tests/ci-python-locks.bats)
```

Expected: every cold install succeeds; `pip check` says `No broken requirements found.`; exact versions match.

- [ ] **Step 5: Prove corrupt hash fails closed**

The test copies `bandit-py312.txt`, changes the first digest to 64 zeroes, installs into an empty venv, and requires nonzero plus `THESE PACKAGES DO NOT MATCH THE HASHES FROM THE REQUIREMENTS FILE`.

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
(cd "$DR_IMPL" && bats --filter 'corrupt hash' tests/ci-python-locks.bats)
```

Expected: test passes only because pip rejects the corrupt hash.

- [ ] **Step 6: Audit every parser-visible and pipx path**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
STATE_DIR=/tmp/TUNE-0599-SECURITY-CLOSURE-state
rg -n '(python[0-9.]* -m )?pip(3)? install|pipx install' "$DR_IMPL/.github" "$DR_IMPL/tests" "$DR_IMPL/dev-tools" \
  | rg -v 'requirements/ci|ci-python-locks|documentation|fixtures'
(cd "$DR_IMPL" && bats tests/ci-python-locks.bats tests/bats-discovery-coverage.bats)
(cd "$DR_IMPL" && "$STATE_DIR/bin/actionlint" .github/workflows/bats.yml .github/workflows/dr-orchestrate-contract.yml \
  .github/workflows/reusable-security-audit.yml .github/workflows/security.yml)
```

Expected: no unaccounted CI install; Bats/actionlint pass.

- [ ] **Step 7: Commit**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
git -C "$DR_IMPL" add .github/dependabot.yml .github/workflows/bats.yml \
  .github/workflows/dr-orchestrate-contract.yml .github/workflows/reusable-security-audit.yml \
  .github/workflows/security.yml tests/ci-install-bats-deps.sh \
  tests/bats-discovery-coverage.bats tests/ci-python-locks.bats tests/test-role-registry.bats
git -C "$DR_IMPL" commit -m "security: require hashes for every Python CI install"
```

Expected: only nine mapped files.

## Add real exact-head SAST

### Task 6: Add immutable Semgrep SARIF and Python CodeQL

**Files:** create `.semgrep.yml`, `tests/security/fixtures/sast-unsafe.py`, `tests/security/fixtures/sast-clean.py`, `tests/security/sast-fixtures.bats`; modify `.github/workflows/security.yml`, `tests/security/run-all.sh`, `tests/security/baseline.json`, `tests/security/scorecard-contract.bats`.

- [ ] **Step 1: Write RED unsafe/clean and workflow tests**

The unsafe fixture passes attacker-controlled text to `subprocess.run(..., shell=True)` and `eval`; the clean fixture uses an argument vector and no dynamic evaluation. Tests require:

- local rule IDs `datarim.python.subprocess-shell-true` and `datarim.python.dynamic-eval` find the unsafe lines;
- the clean fixture produces zero findings;
- the production scan excludes only `tests/security/fixtures/`, not all tests;
- Semgrep emits SARIF category `semgrep-python-security-v1`;
- the Semgrep scan preserves its nonzero status, validates `semgrep.sarif`, and requires at least one SARIF result when failure is finding-driven;
- the Semgrep SARIF upload uses `if: always()` and fails if the SARIF file is absent;
- CodeQL initializes Python and analyzes category `codeql-python-v1`;
- both jobs run on PR and push-main, check out `${{ github.event.pull_request.head.sha || github.sha }}`, and use no remote `p/...` rules;
- `security-events: write` exists only in the two SARIF jobs; workflow/global permissions stay empty or read-only.

Write the two fixtures and local rule file with these complete bodies:

```python
# tests/security/fixtures/sast-unsafe.py
import subprocess

def unsafe(user_input: str) -> None:
    subprocess.run(user_input, shell=True, check=True)
    eval(user_input)
```

```python
# tests/security/fixtures/sast-clean.py
import subprocess

def safe(user_input: str) -> None:
    subprocess.run(["printf", "%s", user_input], check=True)
```

```yaml
# .semgrep.yml
rules:
  - id: datarim.python.subprocess-shell-true
    languages: [python]
    severity: ERROR
    message: Do not invoke a shell with attacker-controlled Python input.
    patterns:
      - pattern: subprocess.$METHOD(..., shell=True, ...)
  - id: datarim.python.dynamic-eval
    languages: [python]
    severity: ERROR
    message: Do not dynamically evaluate Python input.
    pattern-either:
      - pattern: eval(...)
      - pattern: exec(...)
```

The fixture test invokes `semgrep scan --config "$ROOT/.semgrep.yml" --json --error`; the unsafe case requires nonzero and both IDs in `.results[].check_id`; the clean case requires zero and `.results|length == 0`. Static workflow assertions grep the two exact categories, exact-head expression, pinned CodeQL SHA, and job-scoped permissions.

- [ ] **Step 2: Verify RED**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
(cd "$DR_IMPL" && bats tests/security/sast-fixtures.bats tests/security/scorecard-contract.bats)
```

Expected: RED because rules, fixtures, stable categories, and CodeQL jobs do not exist.

- [ ] **Step 3: Add immutable local rules and exact-head Semgrep**

Both YAML rules have exact IDs above and severity `ERROR`. The job has:

```yaml
permissions:
  contents: read
  security-events: write
env:
  EXPECTED_HEAD_SHA: ${{ github.event.pull_request.head.sha || github.sha }}
```

Checkout pins `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1`, with `ref: ${{ env.EXPECTED_HEAD_SHA }}` and `persist-credentials: false`. Python setup pins `actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97`. Install from `requirements/ci/semgrep-py312.txt`. Run Semgrep with `set +e`, save its status, restore `set -e`, then validate SARIF before returning the saved status:

```bash
set +e
semgrep scan --config .semgrep.yml --error --sarif --output semgrep.sarif --exclude tests/security/fixtures .
scan_status=$?
set -e
jq -e '.runs | type == "array"' semgrep.sarif >/dev/null
if test "$scan_status" -ne 0; then
  jq -e '[.runs[].results[]?] | length > 0' semgrep.sarif >/dev/null
fi
exit "$scan_status"
```

Upload with `if: always()`, `github/codeql-action/upload-sarif@db488ddef3bf6cb639b32c2e9a7c0a7ea8271d28`, `sarif_file: semgrep.sarif`, and category `semgrep-python-security-v1`.

- [ ] **Step 4: Add applicable Python CodeQL**

Add separate `codeql-python` with the same exact-head checkout and permissions. Pin `github/codeql-action/init` and `/analyze` to `db488ddef3bf6cb639b32c2e9a7c0a7ea8271d28`; initialize `languages: python`; analyze category `codeql-python-v1`. Python is a shipped implementation language, so CodeQL is applicable and must not be replaced by an omission note.

- [ ] **Step 5: Verify GREEN**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
STATE_DIR=/tmp/TUNE-0599-SECURITY-CLOSURE-state
(cd "$DR_IMPL" && bats tests/security/sast-fixtures.bats tests/security/scorecard-contract.bats)
(cd "$DR_IMPL" && "$STATE_DIR/py312/bin/semgrep" scan --config .semgrep.yml --error --exclude tests/security/fixtures .)
(cd "$DR_IMPL" && "$STATE_DIR/bin/actionlint" .github/workflows/security.yml)
(cd "$DR_IMPL" && "$STATE_DIR/py312/bin/zizmor" .github/workflows/security.yml)
```

Expected: unsafe sees both IDs; clean SARIF has zero results; production scan, actionlint, and zizmor pass. A real production finding requires a separately mapped fix, not a new exclusion.

- [ ] **Step 6: Update baseline honestly and commit**

Record Semgrep SARIF and Python CodeQL as enabled in `tests/security/baseline.json`; do not claim CII, independent review, or fuzzing is implemented.

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
python3 -m json.tool "$DR_IMPL/tests/security/baseline.json" >/dev/null
git -C "$DR_IMPL" add .semgrep.yml .github/workflows/security.yml tests/security/fixtures/sast-unsafe.py \
  tests/security/fixtures/sast-clean.py tests/security/sast-fixtures.bats \
  tests/security/scorecard-contract.bats tests/security/run-all.sh tests/security/baseline.json
git -C "$DR_IMPL" commit -m "security: add exact-head Semgrep and Python CodeQL"
```

Expected: exactly eight mapped files.

## Authenticate privileged automation

### Task 7: Validate the full Dependabot tuple without candidate checkout

**Files:** create `dev-tools/check-dependabot-event.py`, `tests/dependabot-auto-merge.bats`; modify `.github/workflows/dependabot-auto-merge.yml`.

- [ ] **Step 1: Write RED tuple tests**

Construct a test-owned valid `pull_request_target` JSON with:

```text
event: pull_request_target
actor, sender, PR author: dependabot[bot]
repository, base repo, head repo: Arcanada-one/datarim
base ref: main
head ref: dependabot/pip/requirements/ci/semgrep-1.176.1
head label: Arcanada-one:dependabot/pip/requirements/ci/semgrep-1.176.1
head SHA: 40 lowercase hex
URL: https://github.com/Arcanada-one/datarim/pull/599
```

Add independent mutation tests for actor, sender, author, repository, base ref/repo, head repo/ref/label/SHA, and URL. Static tests reject `actions/checkout` and any execution/read of the candidate branch.

- [ ] **Step 2: Verify RED**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
(cd "$DR_IMPL" && bats tests/dependabot-auto-merge.bats)
```

Expected: RED because the validator is absent.

- [ ] **Step 3: Implement standard-library fail-closed validation**

Read `GITHUB_EVENT_PATH`, `GITHUB_EVENT_NAME`, `GITHUB_ACTOR`, and `GITHUB_REPOSITORY`; validate every field above. Permit head refs only under `dependabot/github_actions/` or `dependabot/pip/`. Reject missing, non-string, extra-origin, malformed, and empty values. Write only validated `pr_url` and `head_sha` to `GITHUB_OUTPUT`; every rejection names the field and exits `1`. No third-party import.

Use this complete implementation shape; retain the exact constants and output names:

```python
#!/usr/bin/env python3
import json
import os
import re
import sys
from pathlib import Path

REPO = "Arcanada-one/datarim"
BOT = "dependabot[bot]"
HEAD_RE = re.compile(r"^dependabot/(?:github_actions|pip)/[A-Za-z0-9._/-]+$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")

def fail(field: str) -> None:
    print(f"dependabot-event: invalid {field}", file=sys.stderr)
    raise SystemExit(1)

def value(obj: object, path: tuple[str, ...]) -> str:
    current = obj
    for key in path:
        if not isinstance(current, dict) or key not in current:
            fail(".".join(path))
        current = current[key]
    if not isinstance(current, str) or not current:
        fail(".".join(path))
    return current

if os.environ.get("GITHUB_EVENT_NAME") != "pull_request_target":
    fail("event_name")
if os.environ.get("GITHUB_ACTOR") != BOT:
    fail("actor")
if os.environ.get("GITHUB_REPOSITORY") != REPO:
    fail("repository_env")

event_path = os.environ.get("GITHUB_EVENT_PATH", "")
output_path = os.environ.get("GITHUB_OUTPUT", "")
if not event_path or not output_path:
    fail("runtime_paths")
event = json.loads(Path(event_path).read_text(encoding="utf-8"))
pr = event.get("pull_request")
if not isinstance(pr, dict):
    fail("pull_request")

checks = {
    "repository": value(event, ("repository", "full_name")),
    "sender": value(event, ("sender", "login")),
    "author": value(pr, ("user", "login")),
    "base_repo": value(pr, ("base", "repo", "full_name")),
    "base_ref": value(pr, ("base", "ref")),
    "head_repo": value(pr, ("head", "repo", "full_name")),
}
for field in ("repository", "base_repo", "head_repo"):
    if checks[field] != REPO:
        fail(field)
for field in ("sender", "author"):
    if checks[field] != BOT:
        fail(field)
if checks["base_ref"] != "main":
    fail("base_ref")

head_ref = value(pr, ("head", "ref"))
head_label = value(pr, ("head", "label"))
head_sha = value(pr, ("head", "sha"))
if not HEAD_RE.fullmatch(head_ref) or head_label != f"Arcanada-one:{head_ref}":
    fail("head_identity")
if not SHA_RE.fullmatch(head_sha):
    fail("head_sha")
number = pr.get("number")
if not isinstance(number, int) or number < 1:
    fail("pull_request.number")
pr_url = value(pr, ("html_url",))
if pr_url != f"https://github.com/Arcanada-one/datarim/pull/{number}":
    fail("pull_request.html_url")
with Path(output_path).open("a", encoding="utf-8") as output:
    output.write(f"pr_url={pr_url}\nhead_sha={head_sha}\n")
```

- [ ] **Step 4: Wire validation before metadata, with no checkout**

Make the trusted-base validator the first job step. Feed metadata and `gh pr merge --auto` only its `pr_url`, never raw `github.event.pull_request.html_url`. Retain job-scoped `contents: write` and `pull-requests: write` because the API mutations require them; workflow-level permissions remain empty.

- [ ] **Step 5: Verify GREEN and commit**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
STATE_DIR=/tmp/TUNE-0599-SECURITY-CLOSURE-state
(cd "$DR_IMPL" && bats tests/dependabot-auto-merge.bats)
(cd "$DR_IMPL" && "$STATE_DIR/bin/actionlint" .github/workflows/dependabot-auto-merge.yml)
(cd "$DR_IMPL" && "$STATE_DIR/py312/bin/zizmor" .github/workflows/dependabot-auto-merge.yml)
git -C "$DR_IMPL" add dev-tools/check-dependabot-event.py tests/dependabot-auto-merge.bats \
  .github/workflows/dependabot-auto-merge.yml
git -C "$DR_IMPL" commit -m "security: authenticate Dependabot event provenance"
```

Expected: valid tuple emits two outputs; each mutation fails; no checkout; actionlint/zizmor pass; three files committed.

### Task 8: Move release authority to protected-main workflow code

**Files:** create `.github/ssh-signing-allowed-signers`, `dev-tools/release-trust-gate.sh`, `tests/release-trust-gate.bats`; modify `.github/workflows/release.yml`, `dev-tools/release-gate.sh`, `tests/release-gate.bats`. Keep `dev-tools/release-classify.sh` unchanged unless an observed RED test proves a genuine classifier defect rather than a bad expectation.

- [ ] **Step 1: Write adversarial RED tests**

Use temporary Git repositories and command mocks. Independently reject: non-`vMAJOR.MINOR.PATCH`; lightweight tag; unsigned annotated tag; SSH signature by a wrong key; correct key under a wrong allowed-signers principal; target unequal to `origin/main`; target not reachable from protected main; empty classifier; unknown or duplicate key; missing/nonterminal/failed/wrong-SHA/duplicate check. Valid cases require `bump=patch`, `api_diff=clean` or conditionally `api_diff=unavailable`, `zero_x=false`, `escalate=false`, nonempty one-line rationale, and eight successful required contexts at the tag commit. `api_diff=unavailable` is allowed only when the measured repository contract lacks an API baseline and the rationale explicitly says so; `api_diff=false` is invalid.

- [ ] **Step 2: Verify RED**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
(cd "$DR_IMPL" && bats tests/release-trust-gate.bats tests/release-gate.bats)
```

Expected: RED because the trust gate/trusted-main dispatch are absent and current classifier defaults are fail-open.

- [ ] **Step 3: Implement the fail-closed trust gate**

`dev-tools/release-trust-gate.sh` must:

1. require repository `Arcanada-one/datarim` and regex `^v[0-9]+\.[0-9]+\.[0-9]+$`;
2. require `git cat-file -t "$tag"` = `tag` and `git -c gpg.ssh.allowedSignersFile=.github/ssh-signing-allowed-signers verify-tag "$tag"` succeeds; the tracked allowed-signers file is derived from the existing public SSH key only and binds the measured tagger identity as principal;
3. peel `"$tag^{}"`, fetch `origin/main`, require target equals `origin/main`, and require `git merge-base --is-ancestor "$target" origin/main`;
4. call unchanged `release-classify.sh`, requiring every exact key once, `bump=patch`, `api_diff=clean|break|unavailable`, `zero_x=false`, `escalate=false`, nonempty one-line rationale, and no default; reject `break`, and accept `unavailable` only with a rationale naming the measured absence of an API baseline;
5. paginate exact-SHA check runs and machine-count `shellcheck`, `gitleaks`, `bandit`, `osv-scanner`, `trufflehog`, `diff-mirrored-scopes`, `semgrep-sarif`, and `codeql-python`; each expected name must occur exactly once with `head_sha==target`, `status==completed`, and `conclusion==success`;
6. emit only validated `release_sha`, `release_tag`, `bump_level`, and `rationale`.

Tests may inject named `GH_API_CMD` and `GIT_TAG_VERIFY_CMD` adapters; production defaults invoke real paginated `gh api` and `git -c gpg.ssh.allowedSignersFile=<tracked-file> verify-tag`. Negative fixtures generate independent SSH keys/principals so wrong-key and wrong-principal assertions demonstrably fail before implementation and pass afterward.

- [ ] **Step 4: Make release.yml run only trusted main code**

Replace tag-push with required string `workflow_dispatch` input `release_tag`. Gate job checks out protected `main` with full history, fetches only the requested tag, runs trust gate, and has only `contents: read`, `actions: read`, `checks: read`. Publish job depends on gate, checks out `needs.gate.outputs.release_sha`, asserts `HEAD` equal, archives that SHA, and publishes `needs.gate.outputs.release_tag`; keep only job-scoped `contents: write`, `id-token: write`, `attestations: write`.

Pin all actions. Preserve checkout SHA `3d3c42e5aac5ba805825da76410c181273ba90b1` and attestation SHA `4d101475d8b20a2381f78447822ac1eab6504dd8`. Remove `push.tags` and every `${value:=minor}`-style default.

- [ ] **Step 5: Make local gate sign one tag and dispatch main**

After exact classifier and protected-main proof, make tag creation idempotent and resumable. If local/remote tag is absent, create the SSH-signed annotated tag and push that ref only. If present, require the exact annotated object, trusted identity, and peeled `release_sha`; never update or delete it. Record the dispatch-start UTC before dispatch. The release selector later must require a new `workflow_dispatch` run with `headSha==release_sha`, `createdAt>=dispatch_started_at`, and input `release_tag=v2.67.2`; never select any old run.

```bash
DR_RELEASE=/home/dev/.worktrees/datarim/TUNE-0599-RELEASE-EVIDENCE
if ! git -C "$DR_RELEASE" show-ref --verify --quiet refs/tags/v2.67.2; then
  git -C "$DR_RELEASE" tag -s v2.67.2 -m "Datarim v2.67.2" "$release_sha"
fi
test "$(git -C "$DR_RELEASE" cat-file -t v2.67.2)" = tag
git -C "$DR_RELEASE" -c gpg.ssh.allowedSignersFile=.github/ssh-signing-allowed-signers verify-tag v2.67.2
test "$(git -C "$DR_RELEASE" rev-parse 'v2.67.2^{}')" = "$release_sha"
remote_tag=$(git -C "$DR_RELEASE" ls-remote --tags origin refs/tags/v2.67.2 | awk 'NR==1{print $1}')
if test -z "$remote_tag"; then git -C "$DR_RELEASE" push origin refs/tags/v2.67.2; else test "$remote_tag" = "$(git -C "$DR_RELEASE" rev-parse v2.67.2)"; fi
dispatch_started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
gh workflow run release.yml --repo Arcanada-one/datarim --ref main -f release_tag=v2.67.2
```

Derive the tag from `VERSION`, but require these exact commands in the regression. Remove `git push --tags` and warn-and-continue; tag push or dispatch failure exits nonzero.

- [ ] **Step 6: Verify GREEN and commit**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
STATE_DIR=/tmp/TUNE-0599-SECURITY-CLOSURE-state
(cd "$DR_IMPL" && bats tests/release-trust-gate.bats tests/release-gate.bats tests/release-classify.bats)
(cd "$DR_IMPL" && "$STATE_DIR/bin/actionlint" .github/workflows/release.yml)
(cd "$DR_IMPL" && "$STATE_DIR/py312/bin/zizmor" .github/workflows/release.yml)
git -C "$DR_IMPL" add .github/ssh-signing-allowed-signers dev-tools/release-trust-gate.sh tests/release-trust-gate.bats \
  .github/workflows/release.yml dev-tools/release-gate.sh tests/release-gate.bats
git -C "$DR_IMPL" commit -m "security: bind releases to checked protected main"
```

Expected: adversarial tests, actionlint, and zizmor pass; six mapped files are committed; the tracked trust root contains only the public key and its measured principal; classifier source remains unchanged unless its own regression demanded a fix.

### Task 9: Align environment and consumer verification

**Files:** modify `.github/environments-policy.yml`, `dev-tools/check-release-env-policy.sh`, `dev-tools/provision-release-env.sh`, `tests/check-release-env-policy.bats`, `tests/provision-release-env.bats`, `documentation/how-to/provision-release-environment.md`, `documentation/how-to/release-process.md`, `documentation/how-to/release-verification.md`, `skills/release-verify/SKILL.md`.

- [ ] **Step 1: Add RED protected-main policy/identity tests**

Require release environment branch `main`, reject wildcard branch, retain exact `v*` protected-tag policy where shared tooling requires it, and verify API payloads. Require certificate identity:

```text
https://github.com/Arcanada-one/datarim/.github/workflows/release.yml@refs/heads/main
```

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
(cd "$DR_IMPL" && bats tests/check-release-env-policy.bats tests/provision-release-env.bats tests/release-gate.bats)
```

Expected: RED against current tag-triggered policy/docs.

- [ ] **Step 2: Implement exact policy and docs**

Checker fails unless live Datarim environment has protected branch `main` and required tag rule. Provisioner applies/readbacks both without broad wildcard. Docs describe only: exact-main CI; signed annotated tag at that SHA; dispatch `--ref main`; workflow rechecks tag/SHA/checks; exact archive signed/checksummed/attested; consumer verifies `refs/heads/main` identity and tag/SHA.

Add `--branch-policy main` as a repeatable, regex-validated safe ref-name input and `--preserve-reviewers` as an apply-mode switch. The latter reads existing reviewer objects, validates every reviewer has exactly a supported `type` plus numeric `id`, transforms GitHub GET shape to the PUT shape `{type,id}`, and round-trips the same set after mutation; it must not byte-copy the incompatible GET envelope. Provision each policy with GitHub's exact deployment-branch-policy record shapes:

```json
{"name":"v*","type":"tag"}
{"name":"main","type":"branch"}
```

The checker requires one of each for both `release-auto` and `release-manual`; duplicate, wildcard branch, missing type, empty API response, or failed readback exits nonzero under `--strict`.

- [ ] **Step 3: Verify GREEN and stale-contract absence**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
(cd "$DR_IMPL" && bats tests/check-release-env-policy.bats tests/provision-release-env.bats tests/release-gate.bats)
! rg -n 'release\.yml@refs/tags|push --tags' "$DR_IMPL/documentation/how-to/release-process.md" \
  "$DR_IMPL/documentation/how-to/release-verification.md" "$DR_IMPL/skills/release-verify/SKILL.md" \
  "$DR_IMPL/dev-tools/release-gate.sh"
```

Expected: Bats passes; stale-contract grep has no match.

- [ ] **Step 4: Commit**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
git -C "$DR_IMPL" add .github/environments-policy.yml dev-tools/check-release-env-policy.sh \
  dev-tools/provision-release-env.sh tests/check-release-env-policy.bats \
  tests/provision-release-env.bats documentation/how-to/provision-release-environment.md \
  documentation/how-to/release-process.md documentation/how-to/release-verification.md \
  skills/release-verify/SKILL.md
git -C "$DR_IMPL" commit -m "docs: align release policy with trusted main"
```

Expected: exactly nine files.

## Document residuals and prepare v2.67.2

### Task 10: Record only honest accepted risks

**Files:** modify `SECURITY.md`, `tests/security/scorecard-contract.bats`.

- [ ] **Step 1: Add RED accepted-risk tests**

Require five dated entries, each with status `accepted residual risk`, exact surface, necessity, compensating control, and remaining impact:

1. release `contents: write`, `id-token: write`, `attestations: write`;
2. Dependabot `contents: write`, `pull-requests: write`;
3. zero approvals because one human principal cannot independently review;
4. no CII Best Practices enrollment/badge;
5. no continuous fuzzing service.

Reject `fixed`, `resolved`, or `closed` inside these entries. Require exact-main trust and full-tuple/no-checkout controls for the first two.

- [ ] **Step 2: Verify RED**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
(cd "$DR_IMPL" && bats tests/security/scorecard-contract.bats)
```

Expected: RED because the five-entry section is absent.

- [ ] **Step 3: Add minimal policy text and verify GREEN**

Add `## Accepted residual risks` dated `2026-09-03`; explicitly retain privileged-publisher/metadata mutation, non-independent review, missing governance signal, and lack of continuous fuzz exploration.

Use these exact IDs and claims, adapting only Markdown table/list syntax to the existing `SECURITY.md` style:

```text
AR-REL-PERMS — accepted residual risk (2026-09-03). The release job needs contents: write, id-token: write, and attestations: write to publish, keylessly sign, and attest v2.67.2. Protected-main workflow code, a signed annotated SemVer tag, exact protected-main SHA equality, and successful required-check readback constrain but do not remove the privileged publisher impact.
AR-DEP-PERMS — accepted residual risk (2026-09-03). Dependabot auto-merge needs contents: write and pull-requests: write to update PR metadata and request auto-merge. Full actor/repository/base/head tuple validation, no candidate checkout, and strict required checks constrain but do not remove metadata/merge-request mutation authority.
AR-SINGLE-REVIEW — accepted residual risk (2026-09-03). This single-principal repository requires zero approving reviews because the same principal cannot provide independent review. No bypass, strict up-to-date checks, conversation resolution, and disabled workflow approvals constrain but do not create independent human review.
AR-CII — accepted residual risk (2026-09-03). The project is not enrolled in CII Best Practices and exposes no CII badge. Repository policy and evidence gates do not replace that external governance signal.
AR-FUZZ — accepted residual risk (2026-09-03). The project has no continuous fuzzing service. Bats adversarial fixtures, Semgrep, and CodeQL constrain known classes but do not provide continuous input-space exploration.
```

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
(cd "$DR_IMPL" && bats tests/security/scorecard-contract.bats)
git -C "$DR_IMPL" add SECURITY.md tests/security/scorecard-contract.bats
git -C "$DR_IMPL" commit -m "docs: record bounded security residual risks"
```

Expected: tests pass; exactly two files committed.

### Task 11: Bump canonical source surfaces to 2.67.2

**Files:** modify `VERSION`, `CHANGELOG.md`, `README.md`, `CLAUDE.md`.

- [ ] **Step 1: Observe RED version consistency**

Change the first canonical version source to `2.67.2`, then run:

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
bash "$DR_IMPL/dev-tools/check-version-consistency.sh"
```

Expected: RED until all four mapped surfaces agree.

- [ ] **Step 2: Complete patch bump and changelog**

Set all surfaces to `2.67.2`. Add a changelog entry for obsolete privileged seam retirement, transitive hash locks, exact-head Semgrep/CodeQL, Dependabot tuple validation, protected-main signed release trust, and accepted residual risks. Preserve Unreleased and all older history.

Use this exact changelog content under the existing Unreleased section and date style:

```markdown
## [2.67.2] — 2026-09-03

### Security

- Retired the unused TALO-0001 trusted replay runner/workflow and superseded SHA-bridge audit after live decommission and consumer-tag proofs.
- Hash-locked every Python CI tool and transitive dependency, including Bandit, Semgrep, zizmor, pip-audit, Schemathesis, and Bats helper dependencies.
- Added exact-event-head Semgrep SARIF and Python CodeQL scanning with immutable rules/tool pins and job-scoped upload permission.
- Bound Dependabot auto-merge to the full actor/repository/base/head tuple without checking out candidate code.
- Bound release publication to trusted workflow code on protected main, a signed annotated SemVer tag, its exact successful resulting-main SHA, and fail-closed classification.
- Documented the narrowly scoped release/Dependabot permission and review/CII/fuzzing accepted residual risks in SECURITY.md; these residuals are not eliminated by v2.67.2.
```

- [ ] **Step 3: Verify GREEN/classification and commit**

```bash
DR_IMPL=/home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
bash "$DR_IMPL/dev-tools/check-version-consistency.sh"
bash "$DR_IMPL/dev-tools/release-classify.sh" --repo "$DR_IMPL" --from v2.67.1 --to HEAD --api-diff off
git -C "$DR_IMPL" add VERSION CHANGELOG.md README.md CLAUDE.md
git -C "$DR_IMPL" commit -m "fix: prepare Datarim 2.67.2 security release"
```

Expected: consistency passes; because this repository has no declared structural API baseline, classifier emits exactly `bump_level=patch`, `api_diff=unavailable`, `zero_x=false`, `escalate=false`, and nonempty rationale. The release trust gate records the separately measured no-API-baseline reason. If a baseline is discovered, run auto mode and require `api_diff=clean`; never encode `api_diff=false`. Commit contains four files.

## Local, PR-head, and resulting-main gates

### Task 12: Run complete local gates and deliver the code PR

**Files:** no new files; fixes remain inside the exact map.

- [ ] **Step 1: Run focused suites**

```bash
bats tests/ci-python-locks.bats \
  tests/security/sast-fixtures.bats \
  tests/dependabot-auto-merge.bats \
  tests/release-trust-gate.bats \
  tests/release-gate.bats \
  tests/release-classify.bats \
  tests/check-release-env-policy.bats \
  tests/provision-release-env.bats \
  tests/security/scorecard-contract.bats
```

Expected: all pass with no skipped load-bearing case.

- [ ] **Step 2: Run repository gates**

```bash
bash tests/run-bats-discovery.sh --check-registry
bash tests/run-bats-discovery.sh
bash tests/security/run-all.sh
bash dev-tools/check-version-consistency.sh
bash dev-tools/check-component-counts.sh --report
bash dev-tools/check-body-english.sh --scope all
bash dev-tools/release-ledger-report.sh --check
actionlint
zizmor .github/workflows
semgrep scan --config .semgrep.yml --error --exclude tests/security/fixtures .
bandit -r . -x ./tests/security/fixtures
git diff --check 6da8163963b778cce201d42abc745e804129401e..HEAD
```

Expected: every command exits `0`; counts are consistent; English/release-ledger gates pass; production SAST has no finding.

- [ ] **Step 3: Audit scope/secrets**

```bash
git diff --name-status 6da8163963b778cce201d42abc745e804129401e..HEAD
git log --oneline --decorate 6da8163963b778cce201d42abc745e804129401e..HEAD
gitleaks detect --source . --no-banner --redact --exit-code 1
git status --short
```

Expected: all changes are in the Datarim map, no secret, clean worktree. Correct an outside path surgically; never broadly reset.

- [ ] **Step 4: Push one task branch and open one code PR**

```bash
git push -u origin fix/tune-0599-security-closure
code_pr_url=$(gh pr create --repo Arcanada-one/datarim --base main \
  --head fix/tune-0599-security-closure \
  --title "security: close TUNE-0599 Scorecard gaps" \
  --body "Closes TUNE-0599 with obsolete privileged-seam retirement, fully hashed Python CI dependencies, exact-head SAST, authenticated automation provenance, and protected-main release trust. Verification is recorded separately for local, PR-head, resulting-main, Scorecard, release, site, and fleet gates.")
code_pr=${code_pr_url##*/}
```

Expected: one PR with the exact title/body above and no additional repository file.

- [ ] **Step 5: Prove exact PR-head CI**

```bash
head_sha=$(gh pr view "$code_pr" --repo Arcanada-one/datarim --json headRefOid --jq .headRefOid)
test "$head_sha" = "$(git rev-parse HEAD)"
gh pr checks "$code_pr" --repo Arcanada-one/datarim --watch --interval 10
gh api "repos/Arcanada-one/datarim/commits/${head_sha}/check-runs" \
  --jq '[.check_runs[]|{name,status,conclusion,head_sha}]|sort_by(.name)'
```

Expected: all PR checks terminal/success at `head_sha`; `semgrep-sarif` and `codeql-python` present/success. Queued, skipped, or missing is not green.

- [ ] **Step 6: Merge through policy and prove resulting main**

```bash
gh pr merge "$code_pr" --repo Arcanada-one/datarim --squash --delete-branch=false
git fetch origin main
main_sha=$(git rev-parse origin/main)
test "$(gh pr view "$code_pr" --repo Arcanada-one/datarim --json mergeCommit --jq .mergeCommit.oid)" = "$main_sha"
gh run list --repo Arcanada-one/datarim --branch main --commit "$main_sha" \
  --json databaseId,name,event,status,conclusion,headSha
```

Expected: PR `MERGED`; merge SHA equals `main_sha`; every resulting-main run at that exact SHA becomes terminal/success. Synthetic merge is not evidence.

## Apply GitHub controls and close Scorecard

### Task 13: Apply/read back public ruleset and workflow-approval settings

**Files:** none.

- [ ] **Step 1: Revalidate authority and exact main before mutation**

```bash
gh api user --jq .login
git fetch origin main
test "$(git rev-parse origin/main)" = "$main_sha"
gh api repos/Arcanada-one/datarim/rulesets/15879567
```

Expected: same principal; unchanged main; ruleset ID/name still active `protected-branches` on default branch. Drift stops mutation.

- [ ] **Step 2: PUT exact public ruleset with no bypass**

Use `jq -n` piped to `gh api --method PUT repos/Arcanada-one/datarim/rulesets/15879567 --input -`; do not create a policy file. Exact body:

```json
{
  "name":"protected-branches",
  "target":"branch",
  "enforcement":"active",
  "bypass_actors":[],
  "conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},
  "rules":[
    {"type":"deletion"},
    {"type":"non_fast_forward"},
    {"type":"pull_request","parameters":{"dismiss_stale_reviews_on_push":false,"require_code_owner_review":false,"require_last_push_approval":false,"required_approving_review_count":0,"required_review_thread_resolution":true}},
    {"type":"required_status_checks","parameters":{"do_not_enforce_on_create":false,"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"shellcheck"},{"context":"gitleaks"},{"context":"bandit"},{"context":"osv-scanner"},{"context":"trufflehog"},{"context":"diff-mirrored-scopes"},{"context":"semgrep-sarif"},{"context":"codeql-python"}]}}
  ]
}
```

Expected: active default-branch ruleset; no bypass; zero approvals; conversation resolution; strict eight-check policy.

- [ ] **Step 3: Align classic protection without weakening the ruleset**

Send this exact classic-protection body and read it back immediately:

```bash
jq -n '{
  required_status_checks:{strict:true,checks:[
    {context:"shellcheck",app_id:15368},
    {context:"gitleaks",app_id:15368},
    {context:"bandit",app_id:15368},
    {context:"osv-scanner",app_id:15368},
    {context:"trufflehog",app_id:15368},
    {context:"diff-mirrored-scopes",app_id:15368},
    {context:"semgrep-sarif",app_id:15368},
    {context:"codeql-python",app_id:15368}
  ]},
  enforce_admins:true,
  required_pull_request_reviews:{
    dismiss_stale_reviews:false,
    require_code_owner_reviews:false,
    required_approving_review_count:0,
    require_last_push_approval:false
  },
  restrictions:null,
  allow_force_pushes:false,
  allow_deletions:false,
  required_conversation_resolution:true
}' | gh api --method PUT repos/Arcanada-one/datarim/branches/main/protection --input -
gh api repos/Arcanada-one/datarim/branches/main/protection
```

Expected: `.required_status_checks.strict=true`; eight contexts; approval count `0`; conversation resolution/enforce admins true; force/delete false.

- [ ] **Step 4: Disable workflow-authored approvals**

```bash
gh api --method PUT repos/Arcanada-one/datarim/actions/permissions/workflow \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
gh api repos/Arcanada-one/datarim/actions/permissions/workflow
```

Expected: `default_workflow_permissions:read`, `can_approve_pull_request_reviews:false`. Autonomous merge remains status-driven; no approval is fabricated.

- [ ] **Step 5: Read back all invariants**

```bash
gh api repos/Arcanada-one/datarim/rulesets/15879567 --jq '{enforcement,bypass_actors,conditions,rules}'
gh api repos/Arcanada-one/datarim/branches/main/protection \
  --jq '{required_status_checks,required_pull_request_reviews,required_conversation_resolution,enforce_admins,allow_force_pushes,allow_deletions}'
```

Expected: default branch, no bypass, strict checks, zero approvals, conversation resolution, no force/delete. Save exact JSON for archive.

### Task 14: Re-run exact-main checks and dispose Scorecard alerts narrowly

**Files:** none until Task 18 evidence.

- [ ] **Step 1: Observe exact-main checks after policy change**

```bash
gh workflow run security.yml --repo Arcanada-one/datarim --ref main
gh workflow run bats.yml --repo Arcanada-one/datarim --ref main
gh run list --repo Arcanada-one/datarim --branch main --commit "$main_sha" \
  --json databaseId,name,event,status,conclusion,headSha
```

Expected: all eight required contexts for `main_sha` terminal/success. If dispatch is unsupported, use existing exact-SHA push runs; never another commit.

- [ ] **Step 2: Run Scorecard at exact main**

```bash
before_run=$(gh run list --repo Arcanada-one/datarim --workflow scorecard.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh workflow run scorecard.yml --repo Arcanada-one/datarim --ref main
scorecard_run=$(gh run list --repo Arcanada-one/datarim --workflow scorecard.yml --branch main --event workflow_dispatch --limit 10 \
  --json databaseId,headSha --jq --arg old "$before_run" --arg sha "$main_sha" \
  '[.[]|select((.databaseId|tostring)!=$old and .headSha==$sha)][0].databaseId')
test -n "$scorecard_run"
gh run watch "$scorecard_run" --repo Arcanada-one/datarim --exit-status
```

Expected: new exact-`main_sha` Scorecard run succeeds.

- [ ] **Step 3: Require remediated alerts to close naturally**

```bash
gh api --paginate 'repos/Arcanada-one/datarim/code-scanning/alerts?state=open&tool_name=Scorecard&per_page=100' \
  --jq '[.[]|{number,rule:.rule.id,path:(.most_recent_instance.location.path//null),commit:.most_recent_instance.commit_sha}]|sort_by(.number)'
```

Expected before residual disposition: no `BranchProtectionID`, `SASTID`, `PinnedDependenciesID`, or retired-workflow `TokenPermissionsID`. Never dismiss these to manufacture closure; diagnose and fix the control.

- [ ] **Step 4: Dismiss only allowlisted accepted residuals**

Allow only `CIIBestPracticesID`, `CodeReviewID` if still triggered by honest zero-approval policy, `FuzzingID`, and `TokenPermissionsID` only at release or Dependabot workflow. First assert every remaining rule/path tuple belongs to that set. Then PATCH each alert to state `dismissed`, reason `won't fix`, with a comment naming its `SECURITY.md` accepted residual risk, compensating control, `main_sha`, and `scorecard_run`. An unexpected tuple stops all dismissal.

Use this fail-before-write loop; the first `jq -e` validates the whole remaining set before any PATCH:

```bash
remaining=$(gh api --paginate 'repos/Arcanada-one/datarim/code-scanning/alerts?state=open&tool_name=Scorecard&per_page=100' --slurp)
printf '%s' "$remaining" | jq -e 'add | all(.;
  .rule.id=="CIIBestPracticesID" or
  .rule.id=="CodeReviewID" or
  .rule.id=="FuzzingID" or
  (.rule.id=="TokenPermissionsID" and
    ((.most_recent_instance.location.path==".github/workflows/release.yml") or
     (.most_recent_instance.location.path==".github/workflows/dependabot-auto-merge.yml"))))'
printf '%s' "$remaining" | jq -c 'add[]|{number,rule:.rule.id,path:(.most_recent_instance.location.path//"")}' |
while IFS= read -r alert; do
  number=$(printf '%s' "$alert" | jq -r .number)
  rule=$(printf '%s' "$alert" | jq -r .rule)
  path=$(printf '%s' "$alert" | jq -r .path)
  case "$rule:$path" in
    CIIBestPracticesID:*) risk=AR-CII ;;
    CodeReviewID:*) risk=AR-SINGLE-REVIEW ;;
    FuzzingID:*) risk=AR-FUZZ ;;
    TokenPermissionsID:.github/workflows/release.yml) risk=AR-REL-PERMS ;;
    TokenPermissionsID:.github/workflows/dependabot-auto-merge.yml) risk=AR-DEP-PERMS ;;
    *) exit 1 ;;
  esac
  comment="Accepted residual risk ${risk}; compensating controls are documented in SECURITY.md and proven at main ${main_sha}, Scorecard run ${scorecard_run}. This disposition does not claim the residual is fixed."
  gh api --method PATCH "repos/Arcanada-one/datarim/code-scanning/alerts/${number}" \
    -f state=dismissed -f dismissed_reason="won't fix" -f dismissed_comment="$comment"
done
```

- [ ] **Step 5: Prove open readback zero**

```bash
open_alerts=$(gh api --paginate 'repos/Arcanada-one/datarim/code-scanning/alerts?state=open&tool_name=Scorecard&per_page=100' --jq 'length' | awk '{s+=$1} END{print s+0}')
test "$open_alerts" -eq 0
gh api --paginate 'repos/Arcanada-one/datarim/code-scanning/alerts?state=dismissed&tool_name=Scorecard&per_page=100' \
  --jq '[.[]|select(.dismissed_at>="2026-09-03T00:00:00Z")|{number,rule:.rule.id,path:(.most_recent_instance.location.path//null),reason:.dismissed_reason,comment:.dismissed_comment}]|sort_by(.number)'
```

Expected: open count `0`; new dismissals are only allowlisted, reason `won't fix`, and never call the risk fixed.

## Signed release and independent verification

### Task 15: Create, publish, and verify exact-main v2.67.2

**Files:** none during operational steps; evidence is written in Task 18.

- [ ] **Step 1: Recheck environment and exact required checks**

```bash
bash dev-tools/provision-release-env.sh --repo Arcanada-one/datarim --env release-auto \
  --tag-policy 'v*' --branch-policy main --apply
bash dev-tools/provision-release-env.sh --repo Arcanada-one/datarim --env release-manual \
  --tag-policy 'v*' --branch-policy main --preserve-reviewers --apply
bash dev-tools/check-release-env-policy.sh --check --live --strict --repo Arcanada-one/datarim
test "$(git rev-parse origin/main)" = "$main_sha"
gh api "repos/Arcanada-one/datarim/commits/${main_sha}/check-runs" \
  --jq '[.check_runs[]|select(.name=="shellcheck" or .name=="gitleaks" or .name=="bandit" or .name=="osv-scanner" or .name=="trufflehog" or .name=="diff-mirrored-scopes" or .name=="semgrep-sarif" or .name=="codeql-python")|{name,status,conclusion,head_sha}]|sort_by(.name)'
```

Expected: both environment mutations/readbacks succeed without changing the existing manual reviewers; strict live check passes; exactly eight contexts at `main_sha`, all completed/success.

- [ ] **Step 2: Run signed-tag gate from clean origin/main**

```bash
bash dev-tools/release-gate.sh --repo "$PWD" --version 2.67.2 --registry gh
test "$(git cat-file -t v2.67.2)" = tag
git tag -v v2.67.2
test "$(git rev-parse 'v2.67.2^{}')" = "$main_sha"
```

Expected: patch/no-escalation classifier; annotated signed tag; peeled target `main_sha`; only this tag pushed; `release.yml` dispatched at `main`.

- [ ] **Step 3: Wait for exact trusted-main release run**

```bash
release_run=$(gh run list --repo Arcanada-one/datarim --workflow release.yml --branch main --event workflow_dispatch --limit 20 \
  --json databaseId,headSha --jq --arg sha "$main_sha" '[.[]|select(.headSha==$sha)][0].databaseId')
test -n "$release_run"
gh run watch "$release_run" --repo Arcanada-one/datarim --exit-status
gh release view v2.67.2 --repo Arcanada-one/datarim --json tagName,isDraft,isPrerelease,publishedAt,url,assets
```

Expected: exact-main workflow success; published/non-draft/non-prerelease release with archive, checksum, signature, certificate, and attestation assets.

- [ ] **Step 4: Verify download, checksum, signature, attestation, and source identity**

```bash
verify_dir=$(mktemp -d)
gh release download v2.67.2 --repo Arcanada-one/datarim --dir "$verify_dir"
cd "$verify_dir"
sha256sum --check SHA256SUMS
cosign verify-blob \
  --certificate-identity 'https://github.com/Arcanada-one/datarim/.github/workflows/release.yml@refs/heads/main' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  --certificate datarim-v2.67.2.tar.gz.pem \
  --signature datarim-v2.67.2.tar.gz.sig datarim-v2.67.2.tar.gz
gh attestation verify datarim-v2.67.2.tar.gz --repo Arcanada-one/datarim
```

Expected: all three verification layers pass and attestation binds to `Arcanada-one/datarim` trusted-main workflow. Extract the release archive and a fresh `git archive v2.67.2`; compare sorted path lists and SHA-256 of every extracted file. Expected: identical paths/digests. This content comparison avoids gzip timestamp ambiguity without weakening proof.

Run the content comparison exactly:

```bash
mkdir "$verify_dir/release-tree" "$verify_dir/tag-tree"
tar -xzf "$verify_dir/datarim-v2.67.2.tar.gz" -C "$verify_dir/release-tree" --strip-components=1
git -C /home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE archive v2.67.2 \
  | tar -xf - -C "$verify_dir/tag-tree"
(cd "$verify_dir/release-tree" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$verify_dir/release-files.sha256"
(cd "$verify_dir/tag-tree" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$verify_dir/tag-files.sha256"
diff -u "$verify_dir/tag-files.sha256" "$verify_dir/release-files.sha256"
```

Expected: `diff` emits nothing and exits `0`.

## Public site and fleet

### Task 16: Update Arcanada public surfaces in a clean worktree

**Files:** modify exactly the five Arcanada workspace paths in the map.

- [ ] **Step 1: Create isolation without touching the dirty shared root**

```bash
git -C /home/dev/arcanada fetch origin main
test ! -e /home/dev/.worktrees/arcanada-workspace/TUNE-0599-DATARIM-2.67.2
git -C /home/dev/arcanada worktree add \
  /home/dev/.worktrees/arcanada-workspace/TUNE-0599-DATARIM-2.67.2 \
  -b tune-0599-datarim-2.67.2-site origin/main
```

Expected: clean worktree at current Arcanada `origin/main`; shared-root changes, stashes, branches, and other worktrees untouched.

- [ ] **Step 2: Observe RED public-surface checks before editing**

From the new worktree:

```bash
grep -F '2.67.2' Projects/Datarim/README.md Projects/Datarim/CLAUDE.md \
  Projects/Websites/datarim.club/config.php Projects/Websites/datarim.club/pages/changelog.php
grep -F 'v2.67.2' spaces/arcanada/space.yml
```

Expected: at least one stale `2.67.1` surface makes this RED. If every check is already green, inspect for an independently landed release and remap instead of overwriting it.

- [ ] **Step 3: Update exactly five source surfaces**

Set both public project mirrors, site config, bilingual changelog, and fleet manifest to `2.67.2`/`v2.67.2`. Set fleet release SHA to `main_sha`. Ensure Mac, `arcana-devs`, `dev-ai`, and `arcana-agents` are represented; preserve the existing `aether-vm` entry and all unrelated node metadata. Describe security closure and label the three governance/fuzzing omissions plus two permission scopes accepted residual risks, never fixes.

- [ ] **Step 4: Run public/site/fleet source gates**

```bash
cd /home/dev/.worktrees/arcanada-workspace/TUNE-0599-DATARIM-2.67.2
grep -F '2.67.2' Projects/Datarim/README.md Projects/Datarim/CLAUDE.md \
  Projects/Websites/datarim.club/config.php Projects/Websites/datarim.club/pages/changelog.php
grep -F 'pin_version: "2.67.2"' spaces/arcanada/space.yml
grep -F "pin_ref: \"${main_sha}\"" spaces/arcanada/space.yml
php -l Projects/Websites/datarim.club/config.php
php -l Projects/Websites/datarim.club/pages/changelog.php
git diff --check
git diff --name-only
```

Expected: all four public files and both fleet values match; PHP gates pass; fleet may report runtime nodes stale until Task 17; changed paths are exactly five mapped external files.

- [ ] **Step 5: Commit, PR, exact-head checks, merge, resulting-main checks**

```bash
git add Projects/Datarim/CLAUDE.md Projects/Datarim/README.md \
  Projects/Websites/datarim.club/config.php Projects/Websites/datarim.club/pages/changelog.php \
  spaces/arcanada/space.yml
git commit -m "release: publish Datarim 2.67.2 surfaces"
git push -u origin tune-0599-datarim-2.67.2-site
site_pr_url=$(gh pr create --repo Arcanada-one/arcanada-workspace --base main \
  --head tune-0599-datarim-2.67.2-site \
  --title "release: publish Datarim 2.67.2 surfaces" \
  --body "Publishes verified Datarim v2.67.2 source, site changelog, and four-node fleet pin for TUNE-0599.")
site_pr=${site_pr_url##*/}
site_head=$(gh pr view "$site_pr" --repo Arcanada-one/arcanada-workspace --json headRefOid --jq .headRefOid)
test "$site_head" = "$(git rev-parse HEAD)"
gh pr checks "$site_pr" --repo Arcanada-one/arcanada-workspace --watch --interval 10
gh pr merge "$site_pr" --repo Arcanada-one/arcanada-workspace --squash --delete-branch=false
git fetch origin main
site_main_sha=$(git rev-parse origin/main)
test "$(gh pr view "$site_pr" --repo Arcanada-one/arcanada-workspace --json mergeCommit --jq .mergeCommit.oid)" = "$site_main_sha"
gh run list --repo Arcanada-one/arcanada-workspace --branch main --commit "$site_main_sha" \
  --json databaseId,name,status,conclusion,headSha
```

Expected: exact-head checks succeed at `site_head`; merge SHA is `site_main_sha`; all resulting-main checks at that SHA terminal/success.

- [ ] **Step 6: Deploy datarim.club and prove live content**

From an exact `site_main_sha` checkout on the authorized deploy host:

```bash
bash Projects/Websites/deploy.sh datarim.club --dry-run
bash Projects/Websites/deploy.sh datarim.club
curl -fsS https://datarim.club/en/changelog | grep -F '2.67.2'
curl -fsS https://datarim.club/ru/changelog | grep -F '2.67.2'
curl -fsS https://datarim.club/ | grep -F '2.67.2'
```

Expected: dry-run/deploy succeed from `site_main_sha`; English, Russian, and main live pages return success and visible `2.67.2`. Source grep is not live proof.

### Task 17: Install the verified release on four fleet nodes

**Files:** none.

- [ ] **Step 1: Bind one release identity**

```bash
release_sha=$(git rev-parse 'v2.67.2^{}')
test "$release_sha" = "$main_sha"
test "$(gh api repos/Arcanada-one/datarim/git/ref/tags/v2.67.2 --jq .object.type)" = tag
```

Expected: annotated signed tag peels to proven Datarim `main_sha`.

- [ ] **Step 2: Install on Mac**

Run on Mac from `~/arcanada/Projects/Datarim/code/datarim`:

```bash
git fetch --tags origin
git checkout --detach v2.67.2
test "$(git rev-parse HEAD)" = "$(git rev-parse 'v2.67.2^{}')"
./install.sh --with-claude --with-codex --with-cursor
test "$(cat VERSION)" = 2.67.2
bash validate.sh
rg -n 'semgrep-python-security-v1' .github/workflows/security.yml
```

Expected: exact checkout/install, version `2.67.2`, validation success, unique canary found.

- [ ] **Step 3: Install on arcana-devs**

```bash
sudo -n git -C /opt/datarim fetch --tags origin
sudo -n git -C /opt/datarim checkout --detach v2.67.2
test "$(sudo -n git -C /opt/datarim rev-parse HEAD)" = "$release_sha"
sudo -n /opt/datarim/install.sh --with-claude --with-codex
test "$(cat /opt/datarim/VERSION)" = 2.67.2
sudo -n bash /opt/datarim/validate.sh
rg -n 'semgrep-python-security-v1' /opt/datarim/.github/workflows/security.yml
```

Expected: all pass at exact `release_sha`.

- [ ] **Step 4: Install on dev-ai and arcana-agents with fail-closed path resolution**

Run:

```bash
for host in dev-ai arcana-agents; do
ssh "$host" 'set -euo pipefail
runtime_dir=""
for candidate in /opt/datarim /home/aether/Datarim /home/dev/arcanada/Projects/Datarim/code/datarim; do
  if git -C "$candidate" rev-parse --git-dir >/dev/null 2>&1; then
    test -z "$runtime_dir"
    runtime_dir="$candidate"
  fi
done
test -n "$runtime_dir"
git -C "$runtime_dir" fetch --tags origin
git -C "$runtime_dir" checkout --detach v2.67.2
test "$(git -C "$runtime_dir" rev-parse HEAD)" = "'"$release_sha"'"
"$runtime_dir/install.sh" --with-claude --with-codex
test "$(cat "$runtime_dir/VERSION")" = 2.67.2
bash "$runtime_dir/validate.sh"
rg -n "semgrep-python-security-v1" "$runtime_dir/.github/workflows/security.yml"'
done
```

Expected: exactly one candidate resolves per host; exact checkout/install/validation/canary pass. Zero or multiple paths fail; do not guess.

- [ ] **Step 5: Prove fleet convergence**

From Arcanada `site_main_sha`:

Run the checker once per required node so the preserved `aether-vm` pending state does not replace or contaminate this task's four-node result:

```bash
for node in mac arcana-devs dev-ai arcana-agents; do
  bash dev-tools/check-fleet-drift.sh --report --node "$node"
done
```

Expected: Mac, `arcana-devs`, `dev-ai`, and `arcana-agents` each report `2.67.2` and `release_sha`; unreachable/stale on any required node blocks closure. Preserve and report the unrelated `aether-vm` state separately.

## Evidence, archive, and final cleanup

### Task 18: Write exact release audit and TUNE-0599 archive

**Files:** create `documentation/release-audit/release-2.67.2.md`, `documentation/archive/framework/archive-TUNE-0599.md`.

- [ ] **Step 1: Observe RED evidence presence**

```bash
git fetch origin main
git switch -c archive/tune-0599-security-closure origin/main
test -s documentation/release-audit/release-2.67.2.md
test -s documentation/archive/framework/archive-TUNE-0599.md
```

Expected: both fail because files do not exist.

- [ ] **Step 2: Create release audit from captured values only**

Follow `documentation/release-audit/release-2.67.1.md`. Include baseline SHA; code PR/head/merge; exact-main run IDs; ruleset/workflow-permission JSON; Scorecard run/open zero; signed tag/release; checksum/signature/attestation; site PR/head/main/deploy/live; four fleet nodes/version/SHA. Every SHA is 40 hex, run/PR numeric, command `PASS` or `BLOCKED`, URL actual. Never use an unfinished-value marker or inferred status. Separate every evidence boundary.

- [ ] **Step 3: Create archive with all twelve dispositions**

Follow the archive template. Include rows `1,8,10,11,12,14,15,22,25,29,30,31`. Each is either remediated by a named control and closed by exact-main Scorecard, or an accepted residual dismissed `won't fix` and linked to exact `SECURITY.md` entry. State accepted risks were not fixed. Include PR 394/TALO/SHA prerequisites, no-bypass ruleset, workflow approvals false, release/site/fleet, and cleanup. Populate `verification_outcome` from actual `/dr-verify`; if not run, use integer zeroes and `n_a:true`, never fabricated findings.

- [ ] **Step 4: Verify no placeholders/contradictions**

```bash
unfinished_re='T''BD|TO''DO|FIX''ME|to be filled|pending evidence'
! rg -n "$unfinished_re" \
  documentation/release-audit/release-2.67.2.md \
  documentation/archive/framework/archive-TUNE-0599.md
bash dev-tools/check-body-english.sh --scope all
bash dev-tools/check-version-consistency.sh
git diff --check
```

Expected: placeholder grep no match; all gates pass. Canonical operator-facing Russian template sections remain governed by archive/human-summary rules.

- [ ] **Step 5: Commit and merge one evidence PR**

Start a fresh branch at then-current Datarim `origin/main`:

```bash
git add documentation/release-audit/release-2.67.2.md \
  documentation/archive/framework/archive-TUNE-0599.md
git commit -m "docs: archive TUNE-0599 security closure"
git push -u origin archive/tune-0599-security-closure
archive_pr_url=$(gh pr create --repo Arcanada-one/datarim --base main \
  --head archive/tune-0599-security-closure \
  --title "docs: archive TUNE-0599 security closure" \
  --body "Records exact-main, Scorecard, signed release, site, and four-node fleet evidence for TUNE-0599.")
archive_pr=${archive_pr_url##*/}
archive_head=$(gh pr view "$archive_pr" --repo Arcanada-one/datarim --json headRefOid --jq .headRefOid)
test "$archive_head" = "$(git rev-parse HEAD)"
gh pr checks "$archive_pr" --repo Arcanada-one/datarim --watch --interval 10
gh pr merge "$archive_pr" --repo Arcanada-one/datarim --squash --delete-branch=false
git fetch origin main
archive_main_sha=$(git rev-parse origin/main)
test "$(gh pr view "$archive_pr" --repo Arcanada-one/datarim --json mergeCommit --jq .mergeCommit.oid)" = "$archive_main_sha"
gh run list --repo Arcanada-one/datarim --branch main --commit "$archive_main_sha" \
  --json databaseId,name,status,conclusion,headSha
```

Expected: exact evidence-head checks pass; merge succeeds; resulting-main checks at `archive_main_sha` terminal/success. Label it separately from release `main_sha`.

### Task 19: Reach one-main/no-PR/no-task-branch state

**Files:** none.

- [ ] **Step 1: Prove no open TUNE-0599 PR**

```bash
gh pr list --repo Arcanada-one/datarim --state open --json number,headRefName \
  --jq '[.[]|select(.headRefName|test("tune-0599";"i"))]'
gh pr list --repo Arcanada-one/arcanada-workspace --state open --json number,headRefName \
  --jq '[.[]|select(.headRefName|test("tune-0599";"i"))]'
```

Expected: both `[]`.

- [ ] **Step 2: Delete only merged remote task branches**

First require each PR state `MERGED` and record its merge SHA. Then:

```bash
git push origin --delete fix/tune-0599-security-closure archive/tune-0599-security-closure
git -C /home/dev/.worktrees/arcanada-workspace/TUNE-0599-DATARIM-2.67.2 \
  push origin --delete tune-0599-datarim-2.67.2-site
```

Expected: only three named merged branches removed; no other owner's branch touched.

- [ ] **Step 3: Remove only clean task worktrees**

```bash
test -z "$(git status --porcelain)"
test -z "$(git -C /home/dev/.worktrees/arcanada-workspace/TUNE-0599-DATARIM-2.67.2 status --porcelain)"
git -C /home/dev/datarim worktree remove /home/dev/.worktrees/datarim/TUNE-0599-SECURITY-CLOSURE
git -C /home/dev/arcanada worktree remove /home/dev/.worktrees/arcanada-workspace/TUNE-0599-DATARIM-2.67.2
```

Expected: both clean, then absent. Dirty state stops removal; never force.

- [ ] **Step 4: Delete only merged local branches**

```bash
git -C /home/dev/datarim branch -d fix/tune-0599-security-closure archive/tune-0599-security-closure
git -C /home/dev/arcanada branch -d tune-0599-datarim-2.67.2-site
```

Expected: normal `-d` succeeds; failure blocks cleanup rather than prompting force deletion.

- [ ] **Step 5: Final one-main/readback proof**

```bash
git -C /home/dev/datarim fetch --prune origin main
git -C /home/dev/arcanada fetch --prune origin main
gh pr list --repo Arcanada-one/datarim --state open --json number,headRefName
gh pr list --repo Arcanada-one/arcanada-workspace --state open --json number,headRefName
git -C /home/dev/datarim branch --list '*tune-0599*'
git -C /home/dev/arcanada branch --list '*tune-0599*'
git -C /home/dev/datarim worktree list --porcelain
git -C /home/dev/arcanada worktree list --porcelain
gh api --paginate 'repos/Arcanada-one/datarim/code-scanning/alerts?state=open&tool_name=Scorecard&per_page=100' --jq 'length'
```

Expected: no open TUNE-0599 PR, task branch, or task worktree; canonical roots at current main; Scorecard count exactly `0`. List and preserve unrelated state.

## Plan self-review gate

- [ ] Every operator requirement maps to a task and executable verification.
- [ ] Every created/modified/deleted path is in the exact file map before tasks.
- [ ] Every production task has relevant observed RED, minimal change, GREEN, and a scoped commit.
- [ ] Every Python CI tool is fully transitive, interpreter-correct, hash-required, cold-installed, exact-version checked, and corrupt-hash tested.
- [ ] TALO/SHA deletion preserves research/archive evidence and follows current hard stops.
- [ ] Dependabot validates actor, sender, author, repository, base, head repo/ref/label/SHA, and URL without candidate checkout.
- [ ] Release trust rejects malformed/lightweight/unsigned/non-main/unchecked tags and empty/malformed classifier output.
- [ ] SAST runs on PR head and push main with immutable local rules, stable SARIF categories, and job-scoped `security-events: write`.
- [ ] Public policy has no bypass, strict/up-to-date checks, conversation resolution, honest zero approvals, and workflow approvals disabled.
- [ ] Accepted permission/governance residuals are named and never represented as fixed.
- [ ] v2.67.2 source, exact-main CI, signed/checksummed/attested release, consumer verification, four installs, site source/deploy/live, archive, and cleanup are separate gates.
- [ ] Placeholder scan is empty; dynamic evidence is captured by exact commands at execution.
