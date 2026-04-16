# {TASK-ID} -- Implementation Plan

## Overview
(Brief description, complexity, estimated scope)

## Strategist Assessment (L3-4)
- Value:
- Risk:
- Cost:
- Recommendation: go / pivot / cheaper alternative

## Security Summary
### Attack Surface
### Risks
| Risk | Severity | Mitigation |
|------|----------|------------|

## Architecture Impact
(Components affected, new files, modified files)

### DB Migration Convention (if plan touches a database)
- State explicitly which DB(s) the plan touches and whether migrations are tracked in-repo.
- For DBs managed outside the code repo (e.g. `bi_aggregate` — no `migrations/` folder; manual ALTER on local + prod), note this inline so reviewers (human or AI) do not flag a missing migration file as a blocker.
- Format: "DB `<name>`: migrations <in-repo at `<path>` | managed outside repo — manual ALTER applied to <envs>>; verified via `DESCRIBE`."

## Detailed Design
(Component breakdown, interface design, data flow)

## Implementation Steps
### Phase N: {name}
- [ ] Step description

## Test Plan
### Unit Tests
### Integration Tests
### Security Tests

### Acceptance via Dogfooding (framework-tooling tasks only)
For TUNE-* tasks that modify the Datarim pipeline itself, dogfooding — using the modified pipeline to complete and archive the very task that modified it — is a structurally stronger validation than a throwaway smoke test. If dogfooding is chosen over a separate smoke test, document:
- Which pipeline step is exercised (e.g. `/dr-archive` Step 0.5 for TUNE-0013)
- What constitutes success (e.g. reflection doc created, evolution proposals generated, archive doc embeds reflection reference)
- Why dogfooding is preferred (exercises exact runtime configuration, not a synthetic setup)
Rationale: TUNE-0013 AC-12 looked like a gap because the plan specified a separate throwaway-L1 smoke test, while the actual archive dogfooded the new Step 0.5 — structurally stronger but formally unplanned.

## Rollback Strategy

## Validation Checklist
- [ ] (Specific checks)

## Definition of Done
- [ ] (Criteria)
