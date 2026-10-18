---
name: testing/test-value-card
description: Record the causal value and limits of a regression test before adding it.
---

# Test value card fragment

Use `${DATARIM_RUNTIME:-$HOME/.claude}/templates/test-value-card.md` before adding or proposing a regression test.

## Establish value before writing

- State the observable behavior the test protects and the specific fault that makes its assertion fail.
- Explain why existing coverage misses the behavior. Prefer extending a nearby table-driven test or shared fixture.
- If reproduction shows no defect, or existing coverage already catches it, record that no new card is warranted; extend the existing test only when it adds a distinct case.
- Do not add a production export, flag, wrapper, injection hook, or other seam solely for a test. Test at the real boundary. A necessary existing seam must be named with its production caller and the reason it is needed.
- Keep every card field within 160 UTF-8 bytes. A card is a value statement, not evidence that the test ran.

## Attribute red before repair

Run the native regression against the unrepaired source first. Record the command and the expected assertion failure. Confirm it fails because the target behavior is missing, not because fixture setup, imports, or services failed. A clear red result is the causal control; a test that passes before the repair does not establish the defect.

## Recheck after a repair

Re-run three things: the regression, the original failing probe, and a nearby happy path. Keep their results separate. Do not infer a live or production result from synthetic fixtures.

Classify the outcome:

- **verified** — the regression, original failing probe, and adjacent happy path pass at the named source revision; disclose any missing coverage.
- **best-effort** — a repair was applied but one required recheck was unavailable; state which result is unmeasured.
- **reverted** — the regression still fails or the finding remains unresolved; revert only the attempted repair and keep the valid regression evidence.

Test removal is separate work: use a separate reviewed PR, include a rollback path, and never remove tests automatically based on a card or validator result.
