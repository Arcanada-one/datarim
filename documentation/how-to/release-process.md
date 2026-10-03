# Release Process (maintainer playbook)

This document describes how to cut a signed, attested release. The
consumer-facing verification recipe lives in
[`release-verification.md`](release-verification.md).

The maintainer release gate needs Python 3 with PyYAML to inspect actual pinned
attestation steps. Missing YAML support fails closed; comments or shell text do
not establish an executable attestation pipeline.

## Explicit history bootstrap

For the 4.2.2 parentless-root transition, follow
[history transition](history-transition.md). The declared bootstrap verifies
signed baseline provenance, exact preparation/root tree equivalence and the
original change range before classifying the release. Normal releases retain
the ordinary path. Do not prepare the successor tag on the old ancestry or
relax exact-source checks to make version parity green.

## Roles

- **Release engineer** — runs the release. By default this is a member
  of `@Arcanada-one/security-reviewers`.
- **Independent reviewer** — records findings on the release PR or evidence
  artifact. Repositories with more than one eligible principal should also
  require a distinct GitHub approval; single-principal repositories retain
  auditable review evidence without inventing an impossible approval.

## Cadence

- **Patch** (`vX.Y.Z+1`) — issued for security fixes (HIGH/CRITICAL
  within 90 days, MEDIUM within 180 days) and urgent bug fixes.
- **Minor** (`vX.Y+1.0`) — issued for each completed feature increment
  (typically one TUNE task or a coherent slice of work).
- **Major** (`vX+1.0.0`) — breaking changes to the framework contract
  (e.g. operating model, mandatory skill schema). Major bumps require
  a written migration note in `CHANGELOG.md`.

> **Autonomous patch/minor (v2.27.0+).** For packages the maintaining organisation owns, the agent
> MAY drive a `patch`/`minor` release end-to-end without an operator prompt when
> every fail-closed gate is green — `dev-tools/release-classify.sh` (verdict
> `escalate=false`) then `dev-tools/release-gate.sh` (manifest version ==
> target / CI green / `/dr-qa` ALL_PASS / signed pipeline / branch == main /
> version not published). The bump (`pyproject.toml` / `VERSION` + CHANGELOG)
> MUST land before the gate runs — `release-gate.sh` fails closed (no tag) if the
> manifest version does not already equal the target, so an unbumped manifest is
> caught locally instead of after the tag fires in CI. The
> annotated tag carries the bump level; the `release.yml` `classify` job
> re-verifies in CI and routes a `major` bump to the `release-manual` environment
> (operator approval). `major` and any `0.x` breaking change always escalate. See
> `documentation/how-to/version-0x-policy.md` and the consumer mandate
> `documentation/mandates/autonomous-agents.md` § Carve-out. When a new VERSION is waiting for main tag parity, the measured tag-admission
> sequence below may also run autonomously for patch/minor releases. Do not claim
> native release-gate CI admission or fabricate an evidence hook while main CI is
> pending. Major releases and any escalation retain their existing authority gates.

### Measured autonomous gate evidence

`release-gate.sh` binds every observation to the exact clean source commit,
manifest version, and registry. The remote release branch must point at that
commit. Naked `GATE_*_STATUS` / verdict environment values are rejected.
Configure executable `GATE_CI_PROBE`, `GATE_QA_PROBE`, `GATE_REGISTRY_PROBE`, and
`GATE_SMOKE_PROBE` hooks. Each receives `gate repository source_sha version
registry` and must perform the real check, returning `ReleaseGateEvidence/v1`
JSON with `gate`, `source_commit`, `version`, `registry`, `verdict`, and a
nonempty `evidence` description. Expected verdicts are `success` for CI/smoke,
`ALL_PASS` for QA, and `not_published` for the registry. A static success value
is not a measurement. Registry/QA/smoke have no portable guessed fallback.

Without a CI hook, set `GATE_CI_WORKFLOWS` to the comma-separated required
GitHub workflow names. The native probe requires the latest completed,
successful run for every named workflow at the exact SHA; missing, failed,
pending, or truncated observations refuse admission. The smoke hook must
already exist before tagging and must wait for the exact published version
before testing a clean installation. A dry run states that signing, push,
and smoke have not executed.

The gate creates a signed annotated tag, verifies its signature (using the
repository SSH allowlist when present), pushes only the exact tag ref, and
checks the remote tag object. Failed pushes return nonzero and preserve the
local signed tag and audit; smoke failure after push returns exit 4. Audit JSON
records source binding and the last observed phase under
`documentation/release-audit/`. It never calls a local-only tag a published
release or pushes unrelated local tags.

> **One-time environment provisioning.** Datarim dispatches the trusted release
> workflow from protected `main` and authenticates one signed tag. Both
> `release-auto` and `release-manual` MUST therefore allow the `main` branch;
> the declared policy also retains `v*` for compatible tag-triggered consumers.
> Provision once per repo and after recreation: see
> [How to provision a release deployment environment](provision-release-environment.md).

## Pre-flight (manual, fail-closed)

1. The release PR is green on all required checks at its exact head. After merge,
   the clean resulting `main` tree must exactly match that tested tree. A new
   signed source tag can then be prepared; package publication separately requires
   all latest resulting-main checks, including VERSION/tag parity, to be green.
2. `pre-commit run --all-files` is clean locally.
3. `bats tests/` is fully green.
4. `gitleaks detect --redact` finds nothing new. Independently check current source,
   fixtures, prepared archives and website content against the complete protected
   identifier inventory, plus a semantic review of unrelated names. A narrow pattern
   scan does not replace this review; never commit or publish the private match list.
   Current-source privacy does not establish clean historical Git objects or uploads.
5. The release branch / commit has independent review evidence; any configured
   `CODEOWNERS` approval requirement is satisfied.
6. The `VERSION` file matches the intended tag (without the leading
   `v`).

If any pre-flight check fails, abort and fix on a feature branch first.

## Steps

### 1. Bump VERSION and CHANGELOG

```bash
# nosec-extract
# On a feature branch off main:
echo "X.Y.Z" > VERSION
$EDITOR CHANGELOG.md   # add a section for the new tag
$EDITOR README.md      # update version badge or string if applicable
$EDITOR AGENTS.md      # update "Version:" line in the framework intro

git add VERSION CHANGELOG.md README.md AGENTS.md
git commit -m "release: vX.Y.Z"
git push origin <branch>
gh pr create --base main --title "release: vX.Y.Z" --body "Release notes in CHANGELOG.md"
```

Wait for required checks and code-owner approval, then merge.

### 2. Tag

After merge, verify the exact tested-PR/resulting-main tree match and use a clean
`main`. Pushing the signed tag publishes a source ref and generated archives; it
does not publish the signed package release. Record pending main CI truthfully.
The parity check needs this tag within its documented wait window. If subsequent
main checks fail, do not dispatch release publication or move the prepared tag.

On that admitted source:

```bash
git checkout main
git pull --ff-only

# Preflight: `git tag -s` must be able to sign in the configured format.
# SSH signing is valid when gpg.format=ssh and user.signingkey points at an
# available private SSH key; GPG signing is valid when a matching GPG secret key
# exists locally. Do not downgrade to an annotated-only tag silently.
git config --get gpg.format
git config --get user.signingkey
git tag -s "vX.Y.Z-signing-probe" -m "release signing probe" -m "bump_level=patch"
git -c gpg.ssh.allowedSignersFile=.github/ssh-signing-allowed-signers \
  verify-tag "vX.Y.Z-signing-probe"
git tag -d "vX.Y.Z-signing-probe"

git tag -s "vX.Y.Z" -m "release vX.Y.Z" -m "bump_level=patch"
git -c gpg.ssh.allowedSignersFile=.github/ssh-signing-allowed-signers \
  verify-tag "vX.Y.Z"
git push origin "vX.Y.Z"
```

If the signing probe fails, fix the maintainer machine first or have a
maintainer with a working signing setup cut the tag. For SSH signing, the local
minimum is:

```bash
git config gpg.format ssh
git config user.signingkey /path/to/signing-key.ed25519
git config gpg.ssh.allowedSignersFile /path/to/allowed_signers
```

The `allowed_signers` file must contain the public key identity Git should trust
when `git tag -v` verifies the probe tag.

For a release candidate, use a suffix accepted by the tag-format gate:

```bash
git tag -s "vX.Y.Z-rc1" -m "release candidate vX.Y.Z-rc1"
```

Accepted suffixes: `-rc<N>`, `-alpha<N>`, `-beta<N>`, `-test<N>`.

### 3. Dispatch the trusted-main pipeline

Pushing the tag alone does not publish signed release packages. Before dispatch,
require every latest required workflow at the exact resulting-main SHA to finish
successfully, including VERSION/tag parity. Reconfirm the remote main identity,
tag signature and peeled SHA. Then dispatch `.github/workflows/release.yml`
from protected `main` and pass the signed tag as data:

```bash
gh workflow run release.yml --repo Arcanada-one/datarim \
  --ref main -f release_tag=vX.Y.Z
```

The workflow authenticates the annotated tag, proves it peels to the exact
checked-out `main` SHA, then:

1. Validates the tag format and SSH signature.
2. Resolves the previous SemVer tag and independently classifies the bump.
3. Checks out the exact peeled tag SHA (no persisted credentials).
4. Installs `cosign` and `syft` from upstream releases (SHA-pinned).
5. Builds a deterministic source tarball with `git archive HEAD`.
6. Computes a CycloneDX SBOM with `syft scan dir:.`.
7. Signs the tarball and the SBOM with `cosign sign-blob`
   (keyless OIDC).
8. Attests SLSA L2 build provenance for the tarball.
9. Publishes a GitHub Release with all artefacts attached. RC tags are
   marked as prerelease.

Watch the run:

```bash
gh run list --repo Arcanada-one/datarim --workflow release.yml --limit 1
gh run watch --repo Arcanada-one/datarim <RUN-ID>
```

### 4. Verify the release end-to-end

Even after the pipeline reports success, run the consumer recipe
yourself before announcing the release. Follow
[`release-verification.md`](release-verification.md).

If `cosign verify-blob` or `gh attestation verify` fails, **do not**
delete the release; investigate first. Common causes:

| Symptom | Likely cause | Recovery |
|---|---|---|
| `cosign verify-blob` rejects certificate identity | Tag was created from a fork PR | Re-cut the release from a maintainer branch. |
| `gh attestation verify` returns no attestations | `attestations: write` permission missing | Add the permission and re-run the workflow. |
| SBOM `components` array empty | `syft` ran against an empty checkout | Check `actions/checkout` `fetch-depth: 0`. |

### 5. Announce

Once verified, post the release notes to the announcement channels
(`datarim.club` changelog page, project social media). Include a
single sentence reminding consumers to verify before installing.

## Security incident → emergency release

If a vulnerability disclosure forces an out-of-cycle patch:

1. Branch privately from `main`, fix the issue, and add a regression
   test under `tests/security/`.
2. Bump `VERSION` to the next patch.
3. Open a draft Security Advisory and request a CVE if the impact is
   user-facing.
4. Open the PR with a private reviewer; do not announce the fix yet.
5. Merge, tag, let the pipeline produce the signed release.
6. Publish the advisory simultaneously with the release.
7. Within 14 days, write a public post-mortem in the changelog
   describing what happened, what was fixed, and what was changed in
   the process to prevent recurrence.

## Rollback

To withdraw a release:

```bash
gh release delete "vX.Y.Z" --repo Arcanada-one/datarim --yes
git push --delete origin "vX.Y.Z"
```

Caveats:

- Cosign signatures on Rekor remain queryable forever; deleting the
  GitHub release does not revoke the signature. Document why the
  release was withdrawn in the next release's CHANGELOG.
- If the release introduced a regression, prefer cutting `vX.Y.(Z+1)`
  with the fix over deletion. Yanking is reserved for cases where the
  release exposes a critical vulnerability or contains leaked
  credentials.

## Suppression policy reminder

The release pipeline runs the full security gate. Suppressions in
shipped artefacts must include a reason of at least 10 characters
explaining *why*. The pre-commit hook and CI both enforce this.
Suppression sprawl triggers a quarterly review by the security team.

## Portable reporting distribution

The signed pipeline also builds `human-outcome-reporting.zip` and `datarim-human-reporting-integration.zip` from the allowlist in `dev-tools/package-human-reporting.py`. Each ZIP has its own SHA-256 file, keyless cosign bundle and native build attestation. The standalone package includes `install.py` and `INSTALL.md`; use it without installing the framework. The integration overlay is for inspection and reuse, not a substitute for the native project installer.
