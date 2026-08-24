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

## GREEN

Primary contract and registry command:

```text
bats tests/frontend-design-artifacts.bats tests/frontend-design-artifact-mutations.bats tests/test-role-registry.bats
```

Observed after implementation: `1..45`, 45 passed, 0 failed.

Supplementary frontmatter/layout/registry/count command:

```text
bats tests/tune-0520-agent-enforcement.bats tests/check-agent-frontmatter.bats tests/check-skill-frontmatter.bats tests/check-skill-layout.bats tests/check-skill-sibling-refs.bats tests/check-component-counts.bats
```

Observed after implementation: `1..72`, 72 passed, 0 failed.

## Mutation attribution

`tests/frontend-design-artifact-mutations.bats` creates an isolated copy and
damages one boundary per test. Observed result: `1..11`, 11 passed, meaning all
11 mutants produced their required named RED:

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
