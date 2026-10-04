# Release Verification

Datarim releases are signed with [Sigstore cosign](https://docs.sigstore.dev/cosign/) (keyless, GitHub OIDC) and ship with a [CycloneDX](https://cyclonedx.org/) SBOM and a [SLSA build provenance](https://slsa.dev/) attestation. Verify before extracting or installing — never `curl | bash` on a release tarball.

## Prerequisites

- [`cosign`](https://docs.sigstore.dev/cosign/installation/) ≥ 3.0
- [`gh`](https://cli.github.com/) with `gh attestation verify` support
- GNU `sha256sum`, or macOS `shasum -a 256` as its replacement, and `jq`

## What ships per release

| File | Purpose |
|---|---|
| `datarim-<TAG>-source.tar.gz` | Source archive (`git archive HEAD`, prefixed `datarim-<TAG>/`). |
| `datarim-<TAG>-source.tar.gz.sha256` | SHA-256 checksum of the tarball. |
| `datarim-<TAG>-source.tar.gz.cosign.bundle` | Cosign signature bundle (certificate + signature + Rekor inclusion proof). |
| `datarim-<TAG>-sbom.cdx.json` | CycloneDX SBOM (file inventory). |
| `datarim-<TAG>-sbom.cdx.json.cosign.bundle` | Cosign signature for the SBOM. |
| `human-outcome-reporting.zip` | Standalone skill, native-client installer and installation guide. |
| `datarim-human-reporting-integration.zip` | Reporting integration overlay; the full framework remains the source archive. |
| Each reporting ZIP `.sha256` and `.cosign.bundle` | Checksum and independently verifiable workflow signature. |
| GitHub attestation (server-side) | SLSA L2 build provenance, queryable via `gh attestation verify`. |

## Verify recipe

```bash
set -euo pipefail
TAG=v4.3.2   # replace with the release you are verifying

# 1. Download all artefacts.
gh release download "$TAG" --repo Arcanada-one/datarim

# 2. Verify checksum integrity.
sha256sum -c "datarim-${TAG}-source.tar.gz.sha256"

# 3. Verify cosign signature on the tarball.
cosign verify-blob \
  --bundle "datarim-${TAG}-source.tar.gz.cosign.bundle" \
  --certificate-identity "https://github.com/Arcanada-one/datarim/.github/workflows/release.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "datarim-${TAG}-source.tar.gz"

# 4. Verify cosign signature on the SBOM (same identity binding).
cosign verify-blob \
  --bundle "datarim-${TAG}-sbom.cdx.json.cosign.bundle" \
  --certificate-identity "https://github.com/Arcanada-one/datarim/.github/workflows/release.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  "datarim-${TAG}-sbom.cdx.json"

# 5. Verify SLSA build provenance.
gh attestation verify "datarim-${TAG}-source.tar.gz" --repo Arcanada-one/datarim
```

On macOS, replace `sha256sum -c` with `shasum -a 256 -c` if GNU coreutils are not installed.

All five commands must exit `0`. Any non-zero exit means the artefact is untrusted — do not install.

## What each step proves

| Step | Property |
|---|---|
| `sha256sum -c` | Integrity. The tarball was not corrupted in transit. |
| `cosign verify-blob` (tarball) | Authenticity. The tarball was produced by `release.yml` dispatched from protected `main` after authenticating this exact signed tag in `Arcanada-one/datarim`. Signature is anchored in [Sigstore Rekor](https://search.sigstore.dev/) public transparency log. |
| `cosign verify-blob` (SBOM) | The SBOM was signed by the trusted release workflow; compare its source/run metadata with the source archive provenance. |
| `gh attestation verify` | SLSA L2 build provenance. The artefact was built by GitHub-hosted runners from the source at this tag. |

## Counter-examples (do not do this)

<!-- security:counter-example -->
```bash
# DO NOT — skips signature verification entirely.
curl -sL "https://github.com/Arcanada-one/datarim/releases/download/v1.18.0/datarim-v1.18.0-source.tar.gz" \
  | tar -xz
```
<!-- /security:counter-example -->

<!-- security:counter-example -->
```bash
# DO NOT — verifies only the checksum, which the attacker can replace alongside the tarball.
gh release download v1.18.0 --repo Arcanada-one/datarim
sha256sum -c "datarim-v1.18.0-source.tar.gz.sha256"   # alone, this proves nothing if the .sha256 is also tampered
tar -xzf "datarim-v1.18.0-source.tar.gz"
```
<!-- /security:counter-example -->

The signature step is what binds the tarball to its build origin. Skipping it is equivalent to trusting whoever uploaded the file to GitHub Releases.

## Reporting verification failures

If `cosign verify-blob` or `gh attestation verify` fails on an official release tag, do not install. Open an issue at https://github.com/Arcanada-one/datarim/issues with the tag, the failing command, and its output. Treat it as a potential supply-chain incident.

## Portable reporting assets

The same trusted-main workflow signs and attests both reporting ZIPs. After
downloading the release, verify each ZIP before extracting or installing it:

```bash
set -euo pipefail
for ASSET in human-outcome-reporting.zip datarim-human-reporting-integration.zip; do
  sha256sum -c "$ASSET.sha256"
  cosign verify-blob \
    --bundle "$ASSET.cosign.bundle" \
    --certificate-identity "https://github.com/Arcanada-one/datarim/.github/workflows/release.yml@refs/heads/main" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    "$ASSET"
  gh attestation verify "$ASSET" --repo Arcanada-one/datarim
done
```

All checks must exit zero. A checksum alone proves integrity, not the producer.
The standalone ZIP does not enable Datarim in other projects. The integration
ZIP is an overlay, not a replacement for a full project framework installation.
