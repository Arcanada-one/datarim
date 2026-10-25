---
protects: "<observable behavior or invariant protected by the test>"
fails_when: "<specific causal fault and the test/assertion that fails>"
why_new: "<why existing coverage does not already catch this>"
seam: "none"
no_claim: "<what a green result does not prove>"
---

# Test value card

Write one card before adding or proposing a regression test. Keep each field at or below 160 UTF-8 bytes. `fails_when` must name a concrete causal trigger and the failing test, assertion, fixture, or command. Use `seam: none` unless an existing production seam is necessary; a named seam must include its production caller and why the test needs it. A seam introduced only to make a test possible is not allowed.

The card explains test value; it does not prove that a test was run or that its behavior is accepted in production. Record red-before-fix and recheck evidence separately under the applicable testing workflow.
