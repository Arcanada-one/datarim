# TALO-0001 frontend-design G1/G2 RED/GREEN evidence

- Recorded (UTC): 2026-08-24T13:17:17Z
- Research base: `479708495f7dcea8d839eb9361c161320d39e622`
- Scope: reusable Datarim roles, frontend-design skill, role projections,
  research provenance template, design brief, and their tests
- Product code: not started

## RED

Command:

```text
bats tests/frontend-design-artifacts.bats
```

Observed before G1/G2 artifacts existed:

```text
1..16
not ok 1 G1: designer and researcher execution projections are registered
not ok 2 G1: designer owns the pre-code packet but never customer acceptance
ok 3 G1: shipped agent frontmatter and role registry validate
not ok 4 G2: frontend-design is a progressively disclosed skill
...
not ok 16 G2: reusable brief carries ownership hierarchy variants and implementation gate
```

Result: 15 failed, 1 passed. Failures were attributable to the missing
designer, skill, references, registry projections, provenance fields, and
design-brief template.

Role projection RED command:

```text
bats -f 'accepts explicit agent and domain skill projections|rejects an explicit agent projection|rejects a domain skill projection' tests/test-role-registry.bats
```

Observed before schema/validator support:

```text
1..3
not ok 1 accepts explicit agent and domain skill projections when both resolve
not ok 2 rejects an explicit agent projection that does not resolve
not ok 3 rejects a domain skill projection that does not resolve
```

## Initial GREEN before Stage 1 review

Primary contract and registry command:

```text
bats tests/frontend-design-artifacts.bats tests/frontend-design-artifact-mutations.bats tests/test-role-registry.bats
```

Observed for commit `e32d592e73c7915d14bae61e5768677f5b06c5a5`:
`1..45`, 45 passed, 0 failed. Stage 1 subsequently proved that two behavior
assertions in this result were vacuous; this result is preserved as historical
evidence, not current acceptance evidence.

Supplementary frontmatter/layout/registry/count command:

```text
bats tests/tune-0520-agent-enforcement.bats tests/check-agent-frontmatter.bats tests/check-skill-frontmatter.bats tests/check-skill-layout.bats tests/check-skill-sibling-refs.bats tests/check-component-counts.bats
```

Observed after initial implementation and again after the Stage 1 correction:
`1..72`, 72 passed, 0 failed.

## Mutation attribution

`tests/frontend-design-artifact-mutations.bats` creates an isolated copy and
damaged one boundary per test in the initial commit. Observed result: `1..11`,
11 passed. This historical suite did not cover contradiction retention; the
corrected mutation suite below supersedes it.

1. explicit designer projection;
2. designer ownership and acceptance boundary;
3. backend non-trigger;
4. sparse-brief autonomous direction;
5. existing-system reuse-first rule;
6. accessible alternative;
7. real RU stress content;
8. complete twelve-cell evidence plan;
9. post-hoc rejection;
10. product-code Knowledge Contract gate;
11. canonical `CapabilityDescription` boundary.

## Deterministic validators

Fresh checks after implementation:

```text
quick_validate.py skills/frontend-design -> Skill is valid!
check-skill-frontmatter.sh -> RESULT: PASS (74)
check-skill-layout.sh -> RESULT: PASS (74)
check-skill-sibling-refs.sh -> RESULT: PASS (74)
check-agent-frontmatter.sh -> RESULT: PASS (20)
check-role-registry.sh -> OK: 9 roles valid
check-frontmatter-english.sh -> RESULT: PASS (122)
check-body-english.sh -> RESULT: PASS (186)
check-template-path-convention.sh -> exit 0
check-dev-tools-path-convention.sh -> exit 0
git diff --check -> exit 0
```

Independent blind forward evaluation and the required two-stage PR review are
not claimed by this record; they remain downstream review gates.

## Stage 1 correction: independent behavior evaluator

Stage 1 review of commit `e32d592e73c7915d14bae61e5768677f5b06c5a5`
demonstrated that the original prose-presence tests were vacuous: retaining the
safe rule while appending either `Invoke this skill for backend-only work.` or
`A ten-cell matrix is sufficient.` left the corresponding tests green.

Correction RED evidence:

```text
bats tests/frontend-design-artifacts.bats
1..16
12 failed, 4 passed
```

The failures were caused by the deliberately absent decision contract and
evaluator before their implementation. Separate focused RED controls also
proved the 190-character discovery description exceeded its 155-character
budget and that the designer role lacked its required framework-artifact path
projections.

The corrected evaluator has no LLM or network dependency. It consumes a
versioned decision contract plus eight structured scenarios and emits JSON
decisions for activation, design action, Knowledge Contract state,
implementation permission, ownership, binding, evidence cells, and the
no-product-code boundary. It also audits the shipped decision surfaces for
unsafe normative contradictions before evaluating scenarios.

Corrected GREEN evidence:

```text
bats tests/frontend-design-artifacts.bats tests/frontend-design-artifact-mutations.bats
1..48
48 passed, 0 failed
```

The corrected contract contains 19 behavioral/structural tests and 29 mutation
cases. Every prose block on the four normative decision surfaces carries a
declared rule ID, polarity, and semantic binding from the closed decision-rule
grammar. The contract stores only canonical clause IDs, rule IDs, and closed
typed parameters. A code-owned clause registry, exact canonical sequence, and
deterministic renderer produce the complete frontmatter and prose surfaces;
free-form contract strings are not normative authority. Content digests remain
provenance pins, but they are not the semantic gate. Unknown structured
contract keys also fail closed.

The mutation suite retains safe text while appending the original unsafe
backend-only and ten-cell rules, then separately appends the synonymous unsafe
rules `Backend-only changes activate this capability.` and `Ten captures meet
the complete proof threshold.` inside valid known blocks. It also inserts
`Skip external research whenever delivery speed matters.` inside the valid
scope rule. The last mutant also mirrors the sentence into the contract AST and
reseals every digest. It is rejected because `override_text` is not a typed
parameter of the canonical scope clause, without a digest-mismatch finding. A structured
`documentation_override` mutant is also rejected. Invalid scenario vocabulary
(`brief_detail: ultraviolet`) and invalid scalar types are rejected before
evaluation. Expected-output objects have exact per-scenario key sets plus
type/enum validation. Evidence is a twelve-object RU/EN x
desktop/tablet/mobile x light/dark Cartesian set; duplicate, missing, and
misattributed cell mutants all produce RED. The remaining mutants cover
closed corpus roots, strict integer schema versions, structured rejection of an
array scenario ID,
ownership/acceptance, taste approval, design-system replacement,
accessibility, RU overflow, post-hoc binding, Unbound delivery, the
MET-before-code gate, the canonical seven-kind boundary, and omission of a
claimed scenario output.

Current primary plus role-registry command:

```text
bats tests/frontend-design-artifacts.bats tests/frontend-design-artifact-mutations.bats tests/test-role-registry.bats
1..66
66 passed, 0 failed
```

Additional customer-contract compatibility command:

```text
bats tests/test-v-ac-axis-split.bats tests/customer-requirement-expectations-binding.bats
1..88
88 passed, 0 failed
```

## Stage 2 quality correction: strict YAML and role identity

Stage 2 review of `0b11877ab6adfcf4ddb5981bc8c1ca04b347dd24`
identified four independent quality gaps: duplicate YAML keys used PyYAML's
last-key-wins interpretation, malformed or resource-hostile YAML was not
bounded to structured JSON failures, role IDs were not unique, and M1 accepted
an unattributed nested Bats failure.

The correction was test-first. Before implementation, the seven YAML loader
tests and two role-identity tests produced `7/7` and `2/2` attributable
failures. M1 was separately rewritten to require an unmutated passing fixture
and the exact diagnostic:
`projected designer agent mismatch: expected agents/designer.md, got agents/not-present.md`.

The strict safe loader now rejects duplicate or non-string mapping keys,
invalid UTF-8, files over 1 MiB, nesting over 64 collections, more than 20,000
nodes, and all YAML aliases before object construction. Parser, Unicode,
recursion, memory, and I/O failures return bounded JSON without a traceback.
The exact-CI B506 follow-up removes the generic `yaml.load` call and uses an
explicit `StrictSafeLoader.get_single_data()` lifecycle with unconditional
`dispose()`. M37 supplies a Python object tag and proves that its sentinel is
never created. Bandit is not installed on the local host, so its result is
left to exact-head CI rather than claimed locally.
The role schema rejects duplicate objects, while the registry checker rejects
duplicate `role.id` values even when their agent projections differ.

Fresh local evidence:

```text
bats tests/frontend-design-artifacts.bats tests/frontend-design-artifact-mutations.bats tests/test-role-registry.bats
1..77
77 passed, 0 failed

bats tests/tune-0520-agent-enforcement.bats tests/check-agent-frontmatter.bats tests/check-skill-frontmatter.bats tests/check-skill-layout.bats tests/check-skill-sibling-refs.bats tests/check-component-counts.bats
1..72
72 passed, 0 failed

bats tests/test-v-ac-axis-split.bats tests/customer-requirement-expectations-binding.bats
1..88
88 passed, 0 failed
```

The skill validator, Python compile, shell syntax, English-only shipped-surface
gate (219 files), component counts, in-repo fanout lint, and whitespace checks
also pass. Cross-root fanout reports only the 52 expected missing-consumer
warnings and zero errors. Product code remains untouched.
