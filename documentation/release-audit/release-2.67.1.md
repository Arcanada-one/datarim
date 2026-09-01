- release: 2.67.1
  registry: gh
  bump_level: patch
  gates_passed: G0,G1,G2,G3,G4,G5,G6
  rationale: "range v2.67.0..HEAD: highest Conventional-Commits bump=patch, api_diff=unavailable, zero_x=false"
  timestamp: 2026-09-01T22:09:05Z

# Release evidence

- resulting-main commit: `1a4835f74af845352b6034ee720328eb23f707ef`
- pull-request validation: run `33560895617`, 185/185 jobs successful; the
  measured macOS functional 27/37 and 28/37 shards completed in 83s and 62s
  respectively, below the 105s authoritative ceiling.
- resulting-main validation: bats run `33563015903`, 185/185 jobs successful;
  framework-gates rerun `33563015832` successful after the remote tag existed.
- annotated tag: `v2.67.1`, tag object
  `4f6625e144761d6d3b68ab5912ea1bd029dbaf5f`, points to the resulting-main
  commit and carries `bump_level=patch` / `escalate=false`.
- published release: workflow `33564825333` successful; non-draft stable
  GitHub Release contains the source tarball, checksum, SBOM, both cosign
  bundles, and the build-provenance attestation.
- consumer verification: SHA-256, both cosign `verify-blob` checks, and
  `gh attestation verify` all returned success.
