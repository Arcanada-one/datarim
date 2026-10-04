---
id: FIX-0002
title: "Fixture — escaped during verify"
status: completed
completed_date: 2026-06-02
complexity: L3
type: bugfix
project: Fixture
verification_outcome:
  caught_by_verify: 0
  missed_by_verify: 2
  false_positive: 0
  n_a: false
  dogfood_window: "24h"
---

## Initial task

Fix the off-by-one in the fixture paginator.

## Outcome

Shipped, but two regressions slipped past verification and surfaced in dogfood.
