# Claim Quality

Use these rules for source-evidence-ledger entries and claims in product artifacts. They preserve provenance and uncertainty; they do not establish semantic adequacy or authorize a business decision.

## Source identity and duplicates

- Give each source record a stable `origin_family` identifying its originating publisher, dataset, or actor. Records from the same family are grouped so repeated copies are not counted as independent evidence.
- When more than one record belongs to a family, assign the same non-empty `duplicate_group` to every such record. A duplicate group may contain records from only one origin family and must contain at least two records.
- A duplicate group records repeated provenance. It does not discard a copy or establish that the copies agree.

## Conflicts and counterevidence

- Keep each conflicting source as its own ledger entry and assign the entries a shared non-empty `conflict_group`. A conflict group must contain at least two distinct raw references.
- Link evidence against a claim through `contradicting_refs`; do not replace it with a summary that hides the disagreement. For every conflict group represented in a claim’s `supporting_refs`, exactly one member may be listed as supporting and every other member must be listed in `contradicting_refs`. The checker enforces this coverage even when `contradicting_refs` would otherwise be empty. One raw reference cannot appear on both sides.
- Preserve the provenance and disclosure limits for every source. A structural check can verify references and group membership, but cannot decide whether source content actually contradicts a claim.

## Availability and search results

- `availability: unavailable` means the source could not be retrieved or inspected. Record an `unavailable_reason`, the attempted `locator` and `search_method`, set `search_status: incomplete`, and leave `raw_ref` null.
- `search_status: no_match` means a scoped search completed and found no matching source. It is not an unavailable source. Record the search scope, completion time and method; do not use this status when access failed or the search was incomplete.
- Never convert unavailable, incomplete, or unsearched sources into “nothing found.”

## Publication time

- Set `published_at: null` whenever publication time is unknown. Observation and retrieval timestamps are separate facts and cannot supply it.
- A non-null `published_at` requires `published_at_basis_ref` to identify the exact raw reference for that source. When the date is unknown, `published_at_basis_ref` is null.
- The structural checker verifies the presence and identity of that reference. It does not inspect source content to prove the date; an unsupported or guessed date remains a semantic review concern.
