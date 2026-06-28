---
name: release-verify
description: Consumer-side recipe for Datarim release — sha256 → cosign verify-blob → gh attestation verify. Load on install/update from a GitHub Release.
current_aal: 1
target_aal: 2
---

# Release Verify — Consumer-Side Verification Recipe

Datarim releases are published from `Arcanada-one/datarim` via `release.yml` and signed with Sigstore cosign in keyless mode (GitHub OIDC). Each release ships a CycloneDX SBOM and a SLSA L2 build-provenance attestation. **Never install a tarball without verifying the signature.**

This skill is the entry point for AI agents and operators consuming a Datarim release. The canonical source of truth is [`documentation/how-to/release-verification.md`](../../documentation/how-to/release-verification.md). This skill mirrors the core recipe so an agent can answer the user without an extra fetch.

## When To Use

Load this skill when:

- The user says "install Datarim", "update to v*", or "download the latest release".
- The user asks "how do I verify the tarball?", "what is a cosign bundle?", or "why do I need sha256 if there is a signature?".
- Any instruction that includes `gh release download Arcanada-one/datarim` or its equivalent.
- Before running any install script that came out of a release tarball.

Do not load this skill for git-checkout / `git pull` working copies — verification there goes through git commit signing (a separate policy).

## What Ships per Release

| File | Purpose |
|---|---|
| `datarim-<TAG>-source.tar.gz` | Source archive (`git archive HEAD`, prefix `datarim-<TAG>/`). |
| `datarim-<TAG>-source.tar.gz.sha256` | SHA-256 checksum. |
| `datarim-<TAG>-source.tar.gz.cosign.bundle` | Cosign signature bundle (cert + signature + Rekor inclusion proof). |
| `datarim-<TAG>-sbom.cdx.json` | CycloneDX SBOM. |
| `datarim-<TAG>-sbom.cdx.json.cosign.bundle` | Cosign signature over the SBOM. |
| GitHub attestation (server-side) | SLSA L2 build provenance, verified via `gh attestation verify`. |

## Prerequisites

- [`cosign`](https://docs.sigstore.dev/cosign/installation/) ≥ 3.0
- [`gh`](https://cli.github.com/) ≥ 2.40 (for `gh attestation verify`)
- `sha256sum`, `jq` (POSIX)

## Verify Recipe (5 steps, all must exit 0)

```bash
TAG=v1.18.0   # replace with the release you are verifying

# 1. Download every release artefact.
gh release download "$TAG" --repo Arcanada-one/datarim

# 2. Verify tarball integrity via the checksum.
sha256sum -c "datarim-${TAG}-source.tar.gz.sha256"

# 3. Verify the cosign signature over the tarball.
cosign verify-blob \
  --bundle "datarim-${TAG}-source.tar.gz.cosign.bundle" \
  --certificate-identity "https://github.com/Arcanada-one/datarim/.github/workflows/release.yml@refs/tags/${TAG}" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "datarim-${TAG}-source.tar.gz"

# 4. Verify the cosign signature over the SBOM (same identity binding).
cosign verify-blob \
  --bundle "datarim-${TAG}-sbom.cdx.json.cosign.bundle" \
  --certificate-identity "https://github.com/Arcanada-one/datarim/.github/workflows/release.yml@refs/tags/${TAG}" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "datarim-${TAG}-sbom.cdx.json"

# 5. Verify the SLSA build provenance.
gh attestation verify "datarim-${TAG}-source.tar.gz" --repo Arcanada-one/datarim
```

Any non-zero exit → the artefact is **untrusted**; do not deploy it.

## What Each Step Proves

| Step | Property |
|---|---|
| `sha256sum -c` | Integrity. The tarball is not corrupt in transit. |
| `cosign verify-blob` (tarball) | Authenticity. The tarball was produced by `release.yml` on this exact tag in `Arcanada-one/datarim`. The signature is anchored in the [Sigstore Rekor](https://search.sigstore.dev/) public transparency log. |
| `cosign verify-blob` (SBOM) | The SBOM was produced by the same workflow run as the tarball. |
| `gh attestation verify` | SLSA L2 build provenance — the artefact was built by GitHub-hosted runners from source on this exact tag. |

`cosign verify-blob` is the step that binds the tarball to the build origin. A sha256 without cosign proves nothing on its own: an attacker who can replace the archive can also replace the `.sha256` file at the same time.

## Counter-Examples (do not do this)

<!-- security:counter-example -->
```bash
# DO NOT — skips the signature check entirely.
curl -sL "https://github.com/Arcanada-one/datarim/releases/download/v1.18.0/datarim-v1.18.0-source.tar.gz" \
  | tar -xz
```
<!-- /security:counter-example -->

<!-- security:counter-example -->
```bash
# DO NOT — verifies the checksum only; an attacker who replaces the tarball
# can replace the checksum file at the same time.
gh release download v1.18.0 --repo Arcanada-one/datarim
sha256sum -c "datarim-v1.18.0-source.tar.gz.sha256"   # proves nothing on its own when the .sha256 is also forged
tar -xzf "datarim-v1.18.0-source.tar.gz"
```
<!-- /security:counter-example -->

<!-- security:counter-example -->
```bash
# DO NOT — cosign without --certificate-identity accepts a signature from any signer
# (any OIDC subject from that issuer can mint a cert and sign an arbitrary tarball).
cosign verify-blob \
  --bundle "datarim-v1.18.0-source.tar.gz.cosign.bundle" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "datarim-v1.18.0-source.tar.gz"
```
<!-- /security:counter-example -->

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `cosign verify-blob` → `no matching signatures` | The `--certificate-identity` does not match `release.yml@refs/tags/<TAG>` from the signing workflow. Re-check the exact TAG and the capitalisation of org / repo. |
| `gh attestation verify` → `no attestations found` | The release was created by hand or before `release.yml` landed (2026-04-29). Only tags that passed through `release.yml` carry a SLSA L2 attestation. |
| `sha256sum: WARNING: 1 computed checksum did NOT match` | The tarball is corrupt or was tampered with in transit. Re-download; if the problem reproduces, open an issue. |
| `gh: command not found` | Install [GitHub CLI](https://cli.github.com/) ≥ 2.40 — it is required only for step 5 (attestation verify); steps 1-4 can be done with `curl` + `cosign`. |

## Reporting Verification Failures

If `cosign verify-blob` or `gh attestation verify` fails on an official release tag — **do not install it**. Open an issue at `https://github.com/Arcanada-one/datarim/issues` with the tag, the command, and the command's output. This is a potential supply-chain incident.

## Adapting release.yml to a Packaged Artifact

The reference `release.yml` signs a source tarball produced by `git archive`,
where the version string in the artefact name is whatever the tag carries. When
a consumer adapts this workflow to a **registry-packaged artifact** instead of a
source tarball, the build backend **normalizes the version** baked into the
artefact filename. Two traps follow:

1. **Tag-vs-built version assert MUST compare canonical forms, not raw strings.**
   The build backend rewrites the version in the artefact name to its canonical
   form, so a tag like `v1.2.0-rc1` yields an artefact whose embedded version
   differs from the raw tag by punctuation. A literal `tag != built` comparison
   then false-fails on every prerelease, blocking the release before it
   publishes. Canonicalize **both** sides with the ecosystem's own version
   library before comparing.
2. **Any prerelease tag-suffix set MUST be re-validated as buildable for the
   target ecosystem.** A suffix that is meaningless for a source tarball (any
   string works) may be an invalid version segment for the registry — the build
   step rejects it and no artefact is produced. Only advertise suffixes the
   target ecosystem's version spec accepts.

<!-- gate:example-only -->
Concrete: Python `setuptools`/`build` normalizes per PEP 440 (`0.7.0-rc1` →
`0.7.0rc1`; `test` is not a valid segment and fails to build); npm coerces per
semver; cargo canonicalizes per its own version grammar. Use the matching
canonicaliser (`packaging.utils.canonicalize_version`, `semver`, `cargo` metadata)
on both the tag-derived and the built version.
<!-- /gate:example-only -->

## Source of Truth

- Canonical recipe: [`documentation/how-to/release-verification.md`](../../documentation/how-to/release-verification.md) (the user-facing page).
- Workflow that produces the artefacts: [`.github/workflows/release.yml`](../../.github/workflows/release.yml).
- Security Mandate § S4 (Supply Chain): [`CLAUDE.md`](../../CLAUDE.md#security-mandate).
- Sigstore cosign docs: https://docs.sigstore.dev/cosign/
- SLSA spec: https://slsa.dev/

If this skill drifts from `documentation/how-to/release-verification.md`, `documentation/how-to/release-verification.md` wins — update the skill.
