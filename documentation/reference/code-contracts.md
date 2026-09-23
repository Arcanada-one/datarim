# Persistent Code Contracts in Datarim

Datarim uses the open Code Contracts format for **persistent implementation invariants** that must
survive beyond the task that introduced them. They complement, and never replace, D-REQs, V-ACs,
plans, deterministic tests, QA, or compliance.

## Scope

A `CONTRACTS` file applies to its directory and descendants. Agents editing a subtree read the
nearest `CONTRACTS` file and every ancestor `CONTRACTS` up to the repository root. IDs in a child
scope may not collide with IDs inherited from an ancestor scope. A contract should describe a
stable behavioral, architectural, security, or verification obligation whose accidental regression
would matter after the originating task is archived.

Do not create contracts for style preferences, temporary task instructions, implementation detail
that is already enforced by a type/system boundary, or vague goals such as "keep code clean".
Mechanically testable contracts should also have deterministic regression tests.

## Lifecycle

1. `/dr-do` loads applicable contracts before changing code.
2. A task/contract conflict uses Datarim's Return-to-Plan or Return-to-Source transition. The agent
   must not weaken a contract merely to make its patch pass.
3. `dev-tools/check-code-contracts.sh` validates directory-contract syntax and scope identity with no
   Node dependency.
4. `dr-verify-floor.sh` runs that validator as a deterministic Layer-1 check and reports malformed
   contract state as a high-severity finding.
5. `/dr-verify` reviews semantic compliance. A changed or deleted contract is review-relevant even
   when implementation code itself is unchanged.

## Upstream compatibility

The local validator intentionally implements only the directory-scoped `CONTRACTS` subset needed
by Datarim. It does not claim to prove contract prose or parse declaration-attached comments.
When a compatible Node runtime and upstream `cc-check` are available, `cc-check format` and
`cc-check list` may be used additionally for TypeScript, Python, Go, and Rust declaration contracts.
Datarim does not require Node 24 merely to preserve its verification floor.

## Verification semantics

A verifier's output is untrusted input. Malformed JSON, a normalization failure, an unavailable
mandatory verifier, and a clean verifier result are different states. Aggregators must preserve
that distinction. Likewise, "no evidence supplied" (`absent`) differs from deterministically
verified absence (`verified_absence`). The latter is evidence and must not be discarded.
