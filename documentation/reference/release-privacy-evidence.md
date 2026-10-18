# Release privacy evidence

This reference defines the evidence needed for a release-specific comparison against the complete protected-identifier inventory. It complements the public `personal-id-lint` workflow and Gitleaks; it does not replace the release preflight in [Release Process](../how-to/release-process.md), authorize access to private data, or provide a privacy clearance by itself.

## Status and ownership

The release maintainers own the source contract. The legitimate personal-data custodian and canonical inventory route must be established by attributable evidence before any private comparison. A path selector, repository secret, public denylist, or role label does not prove that the inventory exists, is complete, or is authorized for this purpose. The checker has an explicit overlay selector followed by a `DATARIM_LOCAL`/`HOME` fallback; when `DATARIM_LOCAL` is unset, that HOME default does not match the default base stated in AGENTS S3.1. AGENTS S3.1 describes `personal.env` runtime configuration loaded by another component, not this regex overlay. Neither path selection nor that policy clause establishes overlay authority or inventory completeness. Until the policy owner resolves the selector divergence and a qualified custodian and source are established, record `not_measured` and HOLD. Do not infer an empty inventory.

The current workflow has a pre-existing behavior that logs the number of nonempty, noncomment lines in the private overlay when it is present. This derived count may reveal private configuration size to Actions log readers. Do not authorize or rely on that output as evidence. Its acceptability and any remediation are unresolved; release privacy remains HOLD until an independent disposition. This documentation-only contract does not change the workflow.

Keep raw inventory values and match material inside the custodian's authorized protected system. Give a reviewer only the least information needed to verify custody, scope, artifact binding, coverage, and result. Do not put raw values, raw matches, private pattern lists, or a guessable unkeyed digest of the private list in a repository, pull request, task comment, prompt, or ordinary log. Use an opaque inventory version or an attributable custodian-issued receipt. If a keyed commitment is necessary, the custodian retains the key and controls disclosure.

## Selector precedence and policy fit

The workflow may provide a temporary `DATARIM_PERSONAL_ID_OVERLAY` file from its `PERSONAL_ID_OVERLAY` repository secret. The checker selects that explicit value only if it is nonempty and a regular file. Otherwise, it falls through to `personal-id-forbidden.regex` under `${DATARIM_LOCAL:-$HOME/.claude/local}`. If no usable overlay is selected, the checker uses its shipped/public patterns only. These four observable classes must remain distinct in a qualification record:

1. Workflow secret supplied the temporary explicit overlay selector.
2. Explicit overlay selector was absent, empty, or not a regular file, and the checker selected its fallback.
3. The selected fallback used an explicitly set `DATARIM_LOCAL` base.
4. No usable selector was selected, so only shipped/public patterns were active.

The default checker fallback is HOME-relative when `DATARIM_LOCAL` is unset; AGENTS S3.1 instead documents `${DATARIM_RUNTIME:?}/local` for operator-specific runtime configuration and describes `personal.env` loaded by a different component. This mismatch is unresolved. Do not assume the HOME fallback is authoritative, or that AGENTS S3.1 authorizes the checker overlay. If selector authority or policy fit is not established, record `not_measured`/HOLD. In any task or review artifact, report only the redacted selector class and an opaque target reference; never reveal a resolved private path or selector contents.

A repository secret or selected regex overlay is not necessarily the canonical complete protected-identifier inventory. Its legitimate owner, allowed purpose, scope, version, and completeness basis must be established separately. The current workflow's pattern-count log is also a derived disclosure, not permission or evidence; its acceptability and remediation remain unresolved.

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
  "archive_sha256": "2222222222222222222222222222222222222222222222222222222222222222",
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
  "archive_sha256": "5555555555555555555555555555555555555555555555555555555555555555",
  "custodian": "synthetic-custodian-reference",
  "inventory_receipt": "synthetic-opaque-receipt-v1",
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
