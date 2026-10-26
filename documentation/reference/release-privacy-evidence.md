# Release privacy evidence

This reference defines the evidence needed for a release-specific comparison against the complete protected-identifier inventory. It complements the public `personal-id-lint` workflow and Gitleaks; it does not replace the release preflight in [Release Process](../how-to/release-process.md), authorize access to private data, or provide a privacy clearance by itself.

## Status and ownership

The repository owner is the protected-identifier inventory custodian and authorizes its use for the stated release purpose. The owner keeps the canonical inventory and issues an attributable receipt with an immutable, custodian-held revision ID, exact effective period or an attributable not-applicable assertion, declared scope, completeness basis, and known omissions. The owner may delegate a comparison through an authorized route while retaining custody. A path selector, repository secret, public denylist, or role label alone does not prove inventory completeness or authorization; a release without the owner-issued revision receipt remains `not_measured`/HOLD. Do not infer an empty inventory.

The workflow must not log private patterns, matches, or overlay line counts. It checks the selected overlay's complete bytes against the custodian-held revision commitment before running the personal-ID gate and prints only a short fingerprint derived from the opaque revision ID. The fingerprint is a log label, not the comparison proof. A release preflight separately verifies every host copy used for that release against the same protected commitment and records the exact revision ID in the protected receipt. Any missing or mismatched copy is `not_measured`/HOLD.

Keep raw inventory values and match material inside the custodian's authorized protected system. Give a reviewer only the least information needed to verify custody, scope, artifact binding, coverage, and result. Do not put raw values, raw matches, private pattern lists, or a guessable unkeyed digest of the private list in a repository, pull request, task comment, prompt, or ordinary log. Use an opaque inventory version or an attributable custodian-issued receipt. If a keyed commitment is necessary, the custodian retains the key and controls disclosure.

## Selector precedence and policy fit

The workflow may provide a temporary `DATARIM_PERSONAL_ID_OVERLAY` file from its byte-preserving `PERSONAL_ID_OVERLAY_B64` repository secret. Decode the protected value before checking its complete bytes against the custodian-held commitment; a text secret transport can otherwise change a terminal newline. The checker selects that explicit value only if it is nonempty and a regular file. Otherwise, it falls through to `personal-id-forbidden.regex` under `${DATARIM_LOCAL:-$HOME/.claude/local}`. If no usable overlay is selected, the checker uses its shipped/public patterns only. These four observable classes must remain distinct in a qualification record:

1. Workflow secret supplied the temporary explicit overlay selector.
2. Explicit overlay selector was absent, empty, or not a regular file, and the checker selected its fallback.
3. The selected fallback used an explicitly set `DATARIM_LOCAL` base.
4. No usable selector was selected, so only shipped/public patterns were active.

The HOME-relative fallback is a convenience for ordinary local checks, not the release inventory route. AGENTS S3.1's `${DATARIM_RUNTIME:?}/local` rule describes `personal.env` runtime configuration loaded by another component. A release comparison explicitly selects a protected overlay copy and verifies its bytes against the owner's custodian-held revision commitment; no fallback silently qualifies. In any task or review artifact, report only the redacted selector class and an opaque target reference; never reveal a resolved private path or selector contents.

A repository secret or selected regex overlay is not necessarily the canonical complete protected-identifier inventory. The owner-issued receipt must bind its allowed purpose, scope, revision, period, and completeness basis. Before a release check, run `scripts/verify-personal-id-overlay-revision.py` against each participating host copy with the same protected revision commitment. Keep that commitment outside public source and logs. A CI job without the private overlay runs shipped-pattern checks only and does not qualify a release.

## Bind the evidence to one release candidate

For every candidate, record and reconcile:

- The exact source commit and tree, tag name and immutable tag object, and the native archive recipe.
- The archive-container byte length and SHA-256 as separate fields, the aggregate uncompressed payload byte length as a separate field, and the produced asset digest. Do not assign the container digest to the aggregate payload or imply that the payload has that digest. A source tag or source commit alone does not identify every later asset.
- The custodian's authority, authorization for the stated release purpose, access method, immutable inventory revision identifier or equally precise custodian-held snapshot ID, plus its exact effective period; if no period applies, an attributable `not applicable` assertion with its reason and authority. Stage 1 must establish that exact period or attributable assertion; stage 2 must bind the identical value. A change to the period or `not applicable` assertion is drift and stops comparison pending stage-1 requalification. Also record declared identifier scope, completeness basis, and known omissions.
- The detector and semantic-review methods and versions, reviewer, capture time, and an attributable redacted receipt.
- Coverage for every archive member and relevant class: text; invalid or alternate encodings; binary; nested or other archives; generated and vendored content; symlinks; and unsupported or excluded members. A class with no supported verifier is not silently treated as clean.

If no immutable inventory revision or equally precise custodian-held snapshot ID can be established, stop with `not_measured`/HOLD and do not perform stage-2 comparison. Stage 1 must also establish the exact effective period for that identity, or an attributable `not applicable` assertion with its reason and authority; otherwise stop. The exact stage-2 receipt must bind the identical stage-1 identity and period/assertion. Any change to the source, tag object, archive, inventory revision/snapshot ID, effective period or `not applicable` assertion, scope, or coverage invalidates the prior comparison for the changed tuple and requires stage-1 requalification and a new independent review. Preserve earlier evidence with its original tuple; never rewrite history or retroactively clear an older immutable tag.

## Tri-valued results

Use one verdict for each applicable evidence entity and preserve the per-entity basis:

- `verified`: the required check ran against the exact pinned input and its complete declared scope, with supported coverage and attributable evidence.
- `failed`: the check confirmed prohibited content or a material mismatch.
- `not_measured`: required authority, input, completeness, exact binding, supported method, or member coverage is missing, stale, incomplete, or unreadable.

For the release privacy result, any `failed` entity means `failed`; otherwise any `not_measured` entity means `not_measured`/HOLD. Only an all-`verified` set with independent review can satisfy the privacy evidence condition. A zero-match detector is evidence only for the bytes and patterns it actually examined.

A human-readable receipt should name its stage (for example, source scan, archive scan, custodian comparison, semantic review), exact source and archive pins, separate archive-container byte length/SHA-256 and aggregate payload byte length, inventory receipt/revision reference, the exact effective period or attributable `not applicable` assertion with reason and authority, method/version, covered classes, per-entity verdicts, reviewer, and time. It must state exclusions and unsupported classes explicitly without exposing private content. This document is a contract reference, not an executable schema; do not create placeholder fields with implicit `PASS` values.

## Synthetic examples

The following examples are synthetic illustrations only. They use no real custodian, path, inventory, identifier, or release receipt.

### Missing authority or input

```json
{
  "stage": "custodian_comparison",
  "source_commit": "0000000000000000000000000000000000000000",
  "source_tree": "1111111111111111111111111111111111111111",
  "archive_container_bytes": 123456,
  "archive_container_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
  "aggregate_payload_bytes": 120000,
  "custodian": "UNESTABLISHED",
  "inventory_receipt": null,
  "scope_and_completeness": "not_measured",
  "coverage": "not_measured",
  "verdict": "not_measured",
  "reason": "Synthetic example: no attributable authority or qualified input."
}
```

### Fully supported synthetic comparison

```json
{
  "stage": "custodian_comparison",
  "source_commit": "3333333333333333333333333333333333333333",
  "source_tree": "4444444444444444444444444444444444444444",
  "archive_container_bytes": 654321,
  "archive_container_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
  "aggregate_payload_bytes": 650000,
  "custodian": "synthetic-custodian-reference",
  "inventory_receipt": "synthetic-opaque-receipt-v1",
  "inventory_revision_id": "synthetic-inventory-revision-v1",
  "effective_period": "2030-01-01/2030-12-31",
  "effective_period_asserted_by": "synthetic-custodian-reference",
  "scope_and_completeness": "verified",
  "coverage": {
    "text": "verified",
    "alternate_encodings": "verified",
    "binary": "verified",
    "archives_and_nested_archives": "verified",
    "generated_and_vendored": "verified",
    "symlinks": "verified",
    "unsupported_members": "none"
  },
  "semantic_review": "verified",
  "independent_review": "verified",
  "verdict": "verified",
  "captured_at": "2030-01-01T00:00:00Z"
}
```

A synthetic all-`verified` object demonstrates shape only. It is not a real receipt, evidence of an actual custodian, or release approval. Never copy these placeholder values into a live review.

## Stop conditions and recovery

Stop with `not_measured`/HOLD when the custodian or source cannot be qualified; the purpose is unauthorized; the inventory's scope, immutable revision/snapshot identity, exact effective period or attributable not-applicable assertion, or completeness basis is missing; an artifact pin or period assertion differs; any member or encoding is unreadable or unsupported; or independent review is absent. A confirmed prohibited item or material mismatch is `failed` and blocks the candidate.

Do not broaden access or collect a second raw inventory to work around a missing route. Resolve authority and source through the legitimate custodian and the normal reviewed process. Do not mutate or replace an immutable tag. A corrected candidate needs a new exact source/archive comparison and review. Release eligibility, signing, package publication, site publication, installation, and live behavior remain separate evidence stages.
