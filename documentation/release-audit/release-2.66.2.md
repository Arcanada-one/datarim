- release: 2.66.2
  registry: gh
  bump_level: patch
  gates_passed: G0,G1,G2,G3,G4,G5,G6
  rationale: |-
    bump_level=patch
    api_diff=unavailable
    zero_x=false
    escalate=false
    rationale=range v2.66.1..HEAD: highest Conventional-Commits bump=patch, api_diff=unavailable, zero_x=false
  merge_commit: eb54e9cf881ca14f7a689b831598285f38561e89
  tag_object: 610466796fc34e196645d7c91d9f9fcf317c29d5
  release_workflow_run: 31728507259
  artifact_verification: sha256,cosign_tarball,cosign_sbom,github_attestation
  timestamp: 2026-08-13T18:00:36Z
