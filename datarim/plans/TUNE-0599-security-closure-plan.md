# TUNE-0599 Security and Finalization Plan

> This plan is the corrected execution contract for the final Datarim closure.
> The earlier over-expanded draft remains recoverable in Git history.

## Goal

Close the measured OpenSSF Scorecard gaps on Datarim, publish and independently
verify v2.67.2, synchronize the canonical site and four-node fleet, finish the
canonical knowledge-runtime backlog, archive every related workspace task, and
leave no Datarim/Coworker/RTK feature branch, open pull request, or task worktree.

The plan does not treat accepted residual risk as a fix and does not infer a
defect from a tracker statement. Every runtime claim needs a negative control,
a positive control, or an exact source/live readback.

## Boundaries

- Implementation runs in the isolated Datarim worktree on `arcana-devs`.
- GitHub work is authored by `Arcanada`; no identity switch or fabricated
  approval is permitted.
- Datarim product changes land through a pull request and are verified again at
  the resulting `main` SHA.
- The canonical `datarim.club` source is
  `Arcanada-one/datarim-club-site`. The Arcanada workspace copy is a mirror
  and is never a deployment source.
- Release publication runs by `workflow_dispatch` from protected `main`.
  The supplied annotated SemVer tag is data that must be SSH-authenticated and
  must peel to the exact workflow SHA.
- Server runtime state is changed only after source merge and exact readback.
- Temporary evidence contains no tokens, private keys, or credential payloads.
- Unrelated workspace state is enumerated and preserved.

## Measured starting state

- Datarim baseline: `6da8163963b778cce201d42abc745e804129401e`,
  release v2.67.1.
- Coworker baseline: `41bf6835c56774119af0c2ed03055ff890125603`,
  release v0.9.1.
- DEV-1912 is not a defect: empty and whitespace-only provider bodies return
  rc 3 before file creation; a normal body returns rc 0 and creates the file.
- TASK-9016 does not exist. “3K” in the operator brief resolves to RTK, not a
  separate task.
- Twelve Scorecard alerts were open. Their exact rule/path tuple, not alert
  number alone, determines disposition.
- The canonical KB reconcile had a finite backlog; the final gate is a fresh
  report with zero remaining items, valid scan attestation, and no errors.

## Phase 1 — Retire obsolete privileged seams

1. Re-prove that PR 394 is closed/unmerged and that the old trusted TALO runner
   has no unit, process, or runner registration.
2. Delete the obsolete trusted-replay workflow, helper scripts, tests, unit,
   fixture, and its actionlint exception.
3. Preserve the TALO research projection checker and immutable historical
   evidence.
4. Delete the mutable SHA-bridge workflow, state, helper, and regression test.
5. Remove only dead path triggers from `dev-tools-lint.yml`.
6. Run the security contract tests before and after deletion.

## Phase 2 — Harden CI and automation

1. Pin every direct Python workflow tool to an exact version:
   Bandit 1.9.4, Semgrep 1.176.0, zizmor 1.30.0, pip-audit 2.10.1, and
   Schemathesis 4.25.2.
2. Add immutable local Semgrep rules for dynamic evaluation and
   `subprocess(..., shell=True)`.
3. Prove two unsafe fixture findings, zero safe-fixture findings, and run the
   same local rules over tracked production Python.
4. Add exact-event-head Semgrep SARIF and Python CodeQL jobs. Pin CodeQL action
   SHAs and separate SARIF categories.
5. Bind Dependabot write authority to actor, sender, PR author, source repo,
   base `main`, branch prefix, and canonical PR URL. Do not check out code in
   `pull_request_target`.
6. Keep a static regression suite for every control above.

## Phase 3 — Authenticate release authority

1. Replace tag-triggered workflow authority with required
   `workflow_dispatch.release_tag` on protected `main`.
2. Track one public SSH allowed-signers entry. Never track private key material.
3. Require the supplied tag to be:
   - valid SemVer;
   - an annotated tag object;
   - SSH-signed by the tracked principal;
   - peeled to the exact checked-out `main` SHA.
4. Derive the previous SemVer tag dynamically from ancestors; do not hard-code
   v2.67.1 into future releases.
5. Reclassify the bump in CI and route only a major bump to
   `release-manual`.
6. Check out and publish only the authenticated peeled SHA.
7. Correct consumer verification identity to
   `release.yml@refs/heads/main`.

## Phase 4 — Release-environment and repository controls

1. Declare and validate both exact deployment policy tuples for
   `release-auto` and `release-manual`:
   - `v*` / `tag`;
   - `main` / `branch`.
2. Make the provisioner dry-run by default, idempotent, exact-tuple aware, and
   protective of existing reviewers, wait timer, and self-review settings.
3. Read back both live environments and both tuples after mutation.
4. Protect release tags against update, deletion, and non-fast-forward with no
   bypass actor.
5. Protect `main` with pull-request-only integration, strict required checks,
   resolved conversations, no force-push, no deletion, and no bypass actor.
6. Set workflow default permission to read and disable workflow-authored PR
   approvals.
7. Record the five proportionate Scorecard limitations in `SECURITY.md`:
   release permissions, Dependabot permissions, single-principal review,
   fuzzing, and CII registration.
8. After a fresh exact-main Scorecard run, allow dismissal only for those exact
   documented residual tuples. Every other alert must close naturally.

## Phase 5 — Product verification and merge

Run, at minimum:

```bash
bash tests/security/run-all.sh
bats tests/check-release-env-policy.bats tests/provision-release-env.bats
bash tests/run-bats-discovery.sh --check-registry
bash tests/run-bats-discovery.sh
bash validate.sh
shellcheck dev-tools/check-release-env-policy.sh dev-tools/provision-release-env.sh
actionlint
git diff --check
```

Also parse every workflow with `yq`, run Semgrep 1.176.0 over fixtures and
tracked Python, validate version surfaces, and verify no `.orig`/`.rej`
artifact exists.

Open one Datarim pull request, require exact-head checks, merge by squash, then
require all scoped checks again at the resulting `main` SHA. Configure final
branch controls only from observed check names, then rerun resulting-main CI.

## Phase 6 — Signed v2.67.2 release

1. Prove VERSION, README, CLAUDE.md, and CHANGELOG all name 2.67.2.
2. On the exact resulting-main SHA, create an SSH-signed annotated
   `v2.67.2` tag whose message contains `bump_level=patch`.
3. Verify it with
   `git -c gpg.ssh.allowedSignersFile=.github/ssh-signing-allowed-signers verify-tag v2.67.2`.
4. Push only that tag and dispatch:

```bash
gh workflow run release.yml --repo Arcanada-one/datarim \
  --ref main -f release_tag=v2.67.2
```

5. Require exact-main release success and these assets:
   - `datarim-v2.67.2-source.tar.gz`;
   - checksum;
   - cosign bundle;
   - CycloneDX SBOM;
   - SBOM cosign bundle.
6. Verify checksum, both cosign bundles with the protected-main certificate
   identity, GitHub build attestation, and archive content against the tag tree.

## Phase 7 — Site, workspace mirror, and fleet

1. In an isolated checkout of `Arcanada-one/datarim-club-site`, publish the
   bilingual v2.67.2 changelog and current version.
2. Merge and prove exact resulting-main site CI, deploy only that canonical
   repository, then verify homepage, RU/EN changelog, sitemap, internal links,
   and contract routes live over HTTPS.
3. In a separate Arcanada workspace change, update only Datarim public mirrors,
   site mirrors, fleet pins, and final task archives/ledgers.
4. Install the verified Datarim release on:
   - Mac;
   - `arcana-devs`;
   - `dev-ai`;
   - `arcana-agents`.
5. On every node prove exact SHA/version, clean checkout, `validate.sh`,
   Coworker v0.9.1, RTK 0.47.0, Claude/Codex/Cursor hook fanout, and both
   Coworker controls: normal non-empty output succeeds; empty output returns
   rc 3 and creates no file.
6. Remove `/srv/talo-0001-trusted` only after a root read proves no secrets,
   no unique content, and Git recoverability.

## Phase 8 — KB closure, archive, and zero-tail cleanup

1. Repeat bounded canonical KB and self-improvement reconciliation until fresh
   reports show `remaining_to_ingest=0`, `errors=[]`, and
   `scan_attestation=valid`.
2. Run observer and reflection one-shots, then prove every relevant timer is
   enabled and the last natural-cycle result is successful.
3. Reconcile the exact related workspace IDs into one final epic disposition:
   `INFRA-0476`, `SRCH-0037`, `SRCH-0044`, `LTM-0026`,
   `INFRA-0264`, `LTM-0009`, `SRCH-0052`, `SRCH-0053`,
   `ARCA-0192`, `LTM-0027`, `SRCH-0060`, `INFRA-0493`,
   `INFRA-0494`, `SRCH-0057`, `LTM-0025`, `LTM-0014`,
   `LTM-0021`, `ARCA-0191`, `SRCH-0054`, and `TUNE-0599`.
4. Existing archives are amended; duplicate archives are forbidden. Each item
   is marked completed, cancelled, or superseded from direct evidence.
5. Remove the exact task rows from backlog/tasks/active context.
6. Merge workspace archive evidence and prove its resulting-main CI.
7. Delete every merged Datarim/site/workspace task branch and clean task
   worktree. Do not delete unrelated project state.
8. Final readback requires:
   - Datarim, Coworker, and site repositories: only `main`, zero open PRs;
   - workspace: zero related PRs, branches, worktrees, or active rows;
   - Datarim Scorecard: zero open alerts;
   - exact release/site/fleet/KB evidence recorded in the final archive.

## Completion rule

TUNE-0599 is complete only when every phase above has direct current evidence.
A local pass, PR-head pass, queued workflow, published tag without verified
assets, source-only site check, or stale runtime report is not completion.
