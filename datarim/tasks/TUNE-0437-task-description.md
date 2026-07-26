---
id: TUNE-0437
title: "Publish spec-traceability auto-layer on datarim.club"
status: pending
priority: P2
complexity: L3
type: content
project: Datarim
started: 2026-07-26
parent: null
related: []
---

## Overview
Spec-traceability is now an automatic layer in dr-prd/plan/do/qa/compliance (via spec-graph-gate.sh).
The standalone /dr-spec command was removed in TUNE-0435. Update datarim.club to reflect this.

## Acceptance Criteria
- [ ] Remove /dr-spec from site: changelog entry, data/commands/dr-spec.php, all references
- [ ] New changelog-entry: auto-layer, not standalone command
- [ ] Blog release post about traceability auto-layer
- [ ] Update command counters (27 real commands after dr-spec removal)
- [ ] Update feature pages and relationship graphs
