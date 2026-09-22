# Disposition of the preserved developer-policy patch

**Date:** 2026-09-22
**Subject:** an operator working-tree patch to `agents/developer.md`, found uncommitted in the
canonical checkout at the start of the project-scope migration.

## What was found

The canonical checkout (`Projects/Datarim/code/datarim`) carried an uncommitted change to
`agents/developer.md` authored outside this migration. It replaces the agent's mandatory TDD
discipline with graph-verified change: the developer computes an impact set from a relationship
graph, re-verifies each affected entity with the verifier for its edge type, and records a
`ChangeAdmissionReceipt` with tri-valued verdicts. Test-first becomes opt-in, conditional on a
space declaring `verification_policy: tdd-required`.

## Preservation

The patch is preserved twice and neither copy is to be dropped:

- Git stash `822db43e56aefe3388bcd068b1e88ea93eed1f6f`, message
  `datarim-migration-20260922-preserve-operator-developer-policy`, on branch
  `feat/deepseek-tiers-and-provenance`.
- Protected file copy, mode 0600, SHA256
  `92f5686ce4423b5513f8d17f8bd104bdb1e9a53b73e2f39f16c90dc0962a8af4`.

## Disposition: NOT applied to the product. Preserved for separate decision.

This is a deliberate hold, not an oversight, and not a judgement that the policy is wrong. The
patch is a coherent expression of a real Arcanada directive. It simply cannot be carried into this
public product as written, for three reasons measured in the candidate tree on 2026-09-22 rather
than assumed:

1. **It cites documents the product does not contain.** The patch points the developer agent at
   `documentation/mandates/graph-verified-change-mandate.md`. The product has no
   `documentation/mandates/` directory at all. Shipping the patch would hand every downstream
   consumer an instruction to read a file that does not exist in their checkout.
2. **It cites a decision record that is private to Arcanada.** `DEC-AUP-0008` appears zero times
   anywhere in the product. It lives in the Arcanada Universal Program, a separate and private
   governance repository. A public OSS framework must not instruct its users to obey a decision
   they cannot read.
3. **The opt-in it depends on does not exist here.** `verification_policy` and `tdd-required`
   appear zero times in the product. The patch makes TDD conditional on a switch the framework
   has never implemented, so in practice it would not make test-first opt-in for consumers — it
   would simply remove the testing discipline, with the escape hatch inert.

Points 1-3 are properties of the *product*, not objections to the *policy*. Arcanada is entitled
to run graph-verified change in its own spaces; it already does, under its own mandate, and that
is unaffected by this disposition.

## What a future integration would require

Should the product adopt this policy, it needs to be built rather than pasted:

- A product-local statement of graph-verified change, written for consumers who have no access to
  Arcanada's governance, replacing the private citations with public ones.
- A real `verification_policy` mechanism in the space/project contract, with a defined default,
  so that `tdd-required` is a switch that exists.
- A decision on the default for consumers. Silently flipping every downstream project from
  mandatory TDD to opt-in is a breaking change to the framework's quality contract and, under the
  product's own versioning rules, a major-version concern.

Until those exist, the patch stays preserved and unapplied. Recorded here because a held decision
that leaves no trace is indistinguishable from one nobody made.
