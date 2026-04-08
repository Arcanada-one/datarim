---
name: discovery
description: Structured requirements discovery through focused one-question-at-a-time interviews with proposed answers. Use in /prd stage or before /init.
---

# Discovery — Requirements Discovery Interview

## What is Discovery

Discovery is a systematic interview process that clarifies requirements before building. Instead of asking open-ended questions and hoping for complete answers, Discovery proposes answers based on available context and asks the user to confirm or correct.

**Core mechanic:** One question at a time with a **proposed answer**. The user confirms, corrects, or expands. This is faster and more precise than open-ended questions.

Example:
```
Q: What is the primary deployment target?
Proposed: Docker containers on a Linux VPS (based on your existing Hetzner infrastructure).
→ User: "Correct" or "No, this runs on Vercel"
```

---

## Interview Modes

Select mode based on task complexity.

### Quick Mode (5-10 questions) — L1-2

For small fixes and enhancements where scope is mostly clear.

**Covers:**
1. Goal — What are we building/fixing?
2. Constraints — Time, tech, compatibility limits
3. Done criteria — How do we know it is finished?

### Standard Mode (15-25 questions) — L2-3

For features that affect multiple files or introduce new behavior.

**Covers everything in Quick, plus:**
4. Users & stakeholders — Who uses this? Who cares about it?
5. Edge cases — What happens when inputs are unexpected?
6. Dependencies — What existing code/services does this touch?
7. Alternatives — What other approaches were considered?

### Deep Mode (25-50 questions) — L3-4

For major features, new systems, or anything with business impact.

**Covers everything in Standard, plus:**
8. Business model — How does this affect revenue or costs?
9. Scale — Expected load, growth trajectory
10. Security & privacy — Data sensitivity, compliance requirements
11. Integration — External APIs, third-party services
12. Migration — How to transition from current state

---

## Codebase-First Rule

**Before asking any question, check if the answer already exists in code or docs.**

Sources to check (in order):
1. `datarim/projectbrief.md` — project overview
2. `datarim/productContext.md` — existing product requirements
3. `datarim/techContext.md` — technology decisions
4. `datarim/systemPatterns.md` — architecture patterns
5. `package.json`, `Cargo.toml`, `go.mod`, etc. — tech stack
6. `README.md`, `CLAUDE.md` — project conventions
7. Existing code structure and tests

**If you can look it up, don't ask.** State what you found and ask the user to confirm:

```
Q: What testing framework does this project use?
Found: Jest (from package.json devDependencies and existing test files in __tests__/)
→ Proceeding with Jest unless you say otherwise.
```

---

## Dependency Tracking

Answers can invalidate earlier answers. Track dependencies and revisit when needed.

**Rule:** If the answer to question N changes the validity of a previous answer, revisit the previous question before continuing.

Example:
```
Q3: What database are you using?
A3: PostgreSQL

Q7: Do you need real-time updates?
A7: Yes, via WebSocket

→ Revisit Q3: PostgreSQL with LISTEN/NOTIFY for real-time, or do you want a separate pub/sub layer (Redis, NATS)?
```

Maintain a mental dependency graph. Flag revisits explicitly:

```
REVISIT Q3: Your answer to Q7 (real-time updates) affects the database choice.
Updated proposal: PostgreSQL + Redis pub/sub for real-time event distribution.
→ Confirm or correct.
```

---

## Question Categories

### Goal & Scope
- What problem does this solve?
- What is the single most important outcome?
- What is explicitly out of scope?
- Is there a deadline or time constraint?

### Users & Stakeholders
- Who is the primary user?
- Are there secondary users or admin roles?
- Who approves the final result?
- What existing workflows does this change?

### Constraints & Dependencies
- What technology constraints exist (language, framework, platform)?
- What existing systems does this integrate with?
- Are there backward compatibility requirements?
- What is the budget (time, compute, money)?

### Edge Cases & Error Handling
- What happens with empty input?
- What happens with very large input?
- What if an external dependency is unavailable?
- What is the expected behavior on partial failure?

### Security & Privacy
- Does this handle PII or sensitive data?
- What authentication/authorization is needed?
- Are there compliance requirements (GDPR, SOC2, HIPAA)?
- What is the threat model?

### Performance & Scale
- Expected request volume (per second, per day)?
- Expected data volume (now and in 12 months)?
- Latency requirements (P50, P99)?
- What is the acceptable degradation under load?

### Integration & Migration
- What APIs does this consume or expose?
- What data format (JSON, protobuf, CSV)?
- Is there existing data that needs migration?
- What is the rollback strategy?

### Done Criteria
- What tests must pass?
- What does "shipped" mean (merged to main? deployed to prod?)?
- What documentation is required?
- Who needs to sign off?

---

## Output Format

After the interview, produce a structured requirements summary.

```markdown
## Requirements Summary — {Task Title}

**Mode:** Quick / Standard / Deep
**Questions asked:** N
**Revisits:** N

### Goal
{One paragraph describing the objective}

### Scope
**In scope:**
- {item}

**Out of scope:**
- {item}

### Requirements
| # | Requirement | Priority | Source |
|---|------------|----------|--------|
| R1 | {requirement} | Must / Should / Could | Q{n} |

### Constraints
- {constraint with rationale}

### Edge Cases
- {edge case} → {expected behavior}

### Done Criteria
- [ ] {criterion}

### Open Questions
- {anything unresolved, to be decided during implementation}
```

---

## When to Stop

The interview is complete when:
1. All branches are resolved (no open dependency loops)
2. Done criteria are defined
3. No questions remain where the answer would change the implementation approach
4. The user explicitly signals readiness ("let's build", "looks good", "proceed")

**Do not over-interview.** If the user is giving one-word confirmations to every proposal, the scope is clear enough. Wrap up and produce the summary.
