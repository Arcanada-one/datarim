# Release Process (maintainer playbook)

This document describes how to cut a signed, attested release. The
consumer-facing verification recipe lives in
[`release-verification.md`](release-verification.md).

## Roles

- **Release engineer** — runs the release. By default this is a member
  of `@Arcanada-one/security-reviewers`.
- **Code-owner reviewer** — approves the release PR. Must be a
  different person from the release engineer.

## Cadence

- **Patch** (`vX.Y.Z+1`) — issued for security fixes (HIGH/CRITICAL
  within 90 days, MEDIUM within 180 days) and urgent bug fixes.
- **Minor** (`vX.Y+1.0`) — issued for each completed feature increment
  (typically one TUNE task or a coherent slice of work).
- **Major** (`vX+1.0.0`) — breaking changes to the framework contract
  (e.g. operating model, mandatory skill schema). Major bumps require
  a written migration note in `CHANGELOG.md`.

## Pre-flight (manual, fail-closed)

1. `main` is green on all required checks.
2. `pre-commit run --all-files` is clean locally.
3. `bats tests/` is fully green.
4. `gitleaks detect --redact` finds nothing new.
5. The release branch / commit has been reviewed and approved per
   `CODEOWNERS`.
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
$EDITOR CLAUDE.md      # update "Version:" line in the framework intro

git add VERSION CHANGELOG.md README.md CLAUDE.md
git commit -m "release: vX.Y.Z"
git push origin <branch>
gh pr create --base main --title "release: vX.Y.Z" --body "Release notes in CHANGELOG.md"
```

Wait for required checks and code-owner approval, then merge.

### 2. Tag

After merge, on a clean `main`:

```bash
git checkout main
git pull --ff-only
git tag -s "vX.Y.Z" -m "release vX.Y.Z"   # signed tag
git push origin "vX.Y.Z"
```

For a release candidate, use a suffix accepted by the tag-format gate:

```bash
git tag -s "vX.Y.Z-rc1" -m "release candidate vX.Y.Z-rc1"
```

Accepted suffixes: `-rc<N>`, `-alpha<N>`, `-beta<N>`, `-test<N>`.

### 3. Pipeline runs automatically

Pushing the tag triggers `.github/workflows/release.yml`, which:

1. Validates the tag format.
2. Checks out the repository at the tag (no persisted credentials).
3. Installs `cosign` and `syft` from upstream releases (SHA-pinned).
4. Builds a deterministic source tarball with `git archive HEAD`.
5. Computes a CycloneDX SBOM with `syft scan dir:.`.
6. Signs the tarball and the SBOM with `cosign sign-blob`
   (keyless OIDC).
7. Attests SLSA L2 build provenance for the tarball.
8. Publishes a GitHub Release with all artefacts attached. RC tags are
   marked as prerelease.

Watch the run:

```bash
gh run watch --repo Arcanada-one/datarim
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
