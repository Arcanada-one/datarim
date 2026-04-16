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

## Rollback Strategy

## Validation Checklist
- [ ] (Specific checks)

## Definition of Done
- [ ] (Criteria)
