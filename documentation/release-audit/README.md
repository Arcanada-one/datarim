# Release audit log

Append-only record of autonomous releases. `dev-tools/release-gate.sh` writes one
file per release (`release-<X.Y.Z>.md`) on the all-green tag path, BEFORE the tag
is created, so the operator can review every autonomous publish after the fact.

Each record carries:

```yaml
- release: <X.Y.Z>
  registry: pypi | npm | gh
  bump_level: patch | minor | major
  gates_passed: G1,G2,G3,G4,G5,G6
  rationale: <classifier verdict line>
  timestamp: <ISO-8601 UTC>
```

This is the human-readable audit surface (the immutable cryptographic record is
the cosign/Rekor transparency-log entry written by the signed release pipeline).
A `major` bump never reaches this log autonomously — it escalates to the operator
(`release-gate.sh` exits 10 before tagging).
