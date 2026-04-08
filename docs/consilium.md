# Consilium — Multi-Agent Panel Discussions

Consilium (Latin: "council") assembles a panel of Datarim agents to debate a decision from multiple perspectives.

## When to Use

- Architecture decisions with significant trade-offs
- Design choices affecting multiple system components
- Production readiness assessments
- Any decision where multiple expert views reduce blind spots

**Don't over-consilium:** Simple questions (L1-2) get simple answers, not a full panel.

## How It Works

### 1. SCOPE
Define the question and classify its blast radius:
- **Contained** — affects one component
- **Host-level** — affects one service
- **Cross-system** — affects multiple services
- **Business-critical** — affects revenue, users, or data integrity

### 2. ASSEMBLE
Select agents based on the question domain:

| Panel | Agents | Use When |
|-------|--------|----------|
| Architecture | architect, strategist, security, sre, devops | System design decisions |
| Code | developer, reviewer, code-simplifier | Implementation approach |
| Production | sre, devops, security | Deployment and operations |
| Feature | strategist, architect, developer, writer | New feature evaluation |
| Custom | Any 3-7 agents | Domain-specific questions |

### 3. ANALYZE
Each agent evaluates the question through their professional lens, loading their specific skills and context.

### 4. DEBATE
Surface conflicts between perspectives. Build a conflict table:

| Agent A | Agent B | Conflict | Resolution |
|---------|---------|----------|------------|
| architect | sre | "Use event sourcing" vs "Keep it simple with CRUD" | Priority Ladder: Simplicity wins unless reliability requires event sourcing |

### 5. CONVERGE
Resolve conflicts using the Priority Ladder:

**Safety > Correctness > Security > Reliability > Simplicity > Cost > Elegance**

Higher-priority concerns always win over lower-priority ones.

### 6. DELIVER
Output:
- **Recommendation** — the resolved decision
- **Dissenting opinions** — any unresolved disagreements
- **Failure Mode Table:**

| What can fail | Probability | Impact | Detection | Mitigation |
|---------------|-------------|--------|-----------|------------|

## Guard Rules

1. Max 7 agents per consilium
2. Each agent speaks once per round, max 2 rounds
3. If all agents agree immediately → skip DEBATE, go to DELIVER
4. L1-2 tasks do not need consilium
