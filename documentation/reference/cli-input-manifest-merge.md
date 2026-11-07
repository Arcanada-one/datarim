# Merge saved CLI input manifests

`dev-tools/merge-cli-input-manifests.py` combines saved `DatarimCliInputManifest/v1` declarations from standard input. It accepts a JSON array containing 1–16 complete manifests and writes one compatible manifest to standard output. It does not run a producer or validate that the declared files still exist.

## Merge rules

- Each input must be a complete manifest with 1–64 file declarations, valid lowercase SHA-256 digests, and byte counts from 0 through 1 MiB per declaration. The declared total in each manifest cannot exceed 16 MiB.
- The union can contain at most 64 distinct relative paths and at most 16 MiB of declared bytes. Output rows are sorted by relative path.
- Repeated paths coalesce only when both the digest and byte count match. A different digest or byte count for the same path refuses the entire merge. No partial result is emitted.
- JSON integer tokens are retained as exact decimal values until their field bounds and integrality are checked; conversion to an integer happens only after those checks. Producer core counters still require JSON integer tokens. File byte counts accept bounded integer tokens and mathematically integral decimal tokens, without float approximation.
- Input is limited to 2 MiB, with one additional byte read only to detect an oversized input. The serialized output is also limited to 2 MiB.
- Invalid JSON, duplicate object keys, non-finite numbers, invalid UTF-8, an invalid manifest, or any limit violation produces a fixed `INPUT_REFUSED` manifest with exit code 2 and the fixed stderr code `INPUT_MANIFEST_MERGE_REFUSED`.

The merger validates declarations only. It never opens a listed path, computes file hashes, confirms file contents, or establishes provenance, producer approval, delivery readiness, or semantic truth. Paths are treated as untrusted data and are not passed to a shell or used for file access. This operation does not invoke a model or create a model trust boundary.

## Invocation

Pass the saved manifests through standard input; the utility accepts no path or root option:

```bash
set -euo pipefail
# Keep shell word splitting limited to newline and tab; quote each command argument.
IFS=$'\n\t'
python3 dev-tools/merge-cli-input-manifests.py < saved-manifests.json > merged-manifest.json
```

The shell redirections name the caller's input and output files. The merger itself reads only standard input and writes only standard output and its fixed refusal code on standard error.

## Change and rollback

Make follow-up changes through the repository's normal branch and pull-request process. Before a rollback, initialize and validate the intended full commit SHA against the reviewed change and current repository state; quote it when using Git so it remains one argument:

```bash
set -euo pipefail
IFS=$'\n\t'
rollback_sha='0123456789abcdef0123456789abcdef01234567'
[[ "$rollback_sha" =~ ^[0-9a-f]{40}$ ]] || { printf '%s\n' 'Set rollback_sha to the reviewed full commit SHA.' >&2; exit 2; }
git rev-parse --verify "${rollback_sha}^{commit}"
```

The example SHA is a placeholder, not a rollback target. Replace it with the intended reviewed full SHA and confirm it identifies the change being rolled back. Then use `git revert "$rollback_sha"` and submit that revert through the normal follow-up pull-request process; do not rewrite shared history.
