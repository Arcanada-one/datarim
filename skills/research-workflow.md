---
name: research-workflow
description: Structured external research — checklist, tool selection, insights document. Used by researcher agent in /dr-prd and /dr-do.
model: sonnet
---

# Research Workflow

Structured methodology for investigating external context before planning or during implementation. Produces a `datarim/insights/INSIGHTS-{task-id}.md` document.

## Research Modes

### Full Mode (L3-L4) — 10 checkpoints

For features, new systems, or tasks involving unfamiliar technology. Runs all 10 checklist items.

### Lite Mode (L2) — 5 checkpoints

For enhancements where most context is known. Runs items 1, 3, 4, 6, 9 only.

### Skip (L1)

Quick fixes do not need research. Skip entirely.

---

## Research Checklist

| # | Checkpoint | Description | Tools | Mode |
|---|-----------|-------------|-------|------|
| 1 | **Versions & Dependencies** | Current stable versions of libraries/frameworks in the task's stack. Check for recent major releases. | context7 `resolve-library-id` + `query-docs`, WebSearch | Full, Lite |
| 2 | **Breaking Changes** | Migration guides, deprecated APIs, removed features between current and target versions. | context7 `query-docs`, WebFetch (changelog URLs) | Full |
| 3 | **Best Practices** | Recommended approaches for key task elements. Official guides, community consensus. | WebSearch, context7 | Full, Lite |
| 4 | **Stack Documentation** | Load relevant documentation sections for technologies being used. | context7 `resolve-library-id` + `query-docs` | Full, Lite |
| 5 | **Architectural Patterns** | Examples of similar implementations. Reference architectures, open-source projects. | WebSearch | Full |
| 6 | **Compatibility** | Verify chosen components work together. Check peer dependency requirements, runtime compatibility. | context7, WebSearch | Full, Lite |
| 7 | **Security Advisories** | Known CVEs, npm/pip advisories, GitHub security alerts for dependencies. | WebSearch (`"CVE" + library name`) | Full |
| 8 | **RAG/LTM Context** | Query Scrutator LTM API for relevant experience from past tasks. | `POST /v1/ltm/recall` (if MCP/API available) | Full |
| 9 | **Existing Codebase** | Search project for reusable components, established patterns, similar implementations. | Grep, Glob, Read | Full, Lite |
| 10 | **Infrastructure Constraints** | Check server resources, port allocation, disk/memory limits, network topology. | Read (`Areas/Infrastructure/Servers.md`, port allocation memory) | Full |

---

## Tool Selection — Adaptive

The researcher works with whatever tools are available. No hard dependency on any specific MCP.

### Priority order per checkpoint

1. **context7 MCP available?** Use `resolve-library-id` to find the library, then `query-docs` for specific topics. Most token-efficient path for library documentation.
2. **WebSearch available?** Use for version checks, CVE lookups, best practices, architectural patterns.
3. **WebFetch available?** Use for loading specific URLs (changelogs, migration guides, release notes).
4. **LTM API available?** Use `POST /v1/ltm/recall` with task-relevant query for past experience.
5. **Always available:** Grep, Glob, Read for codebase analysis. These require no external tools.

### When nothing external is available

If no web tools or MCP servers are configured, research falls back to:
- Codebase analysis (Grep, Glob, Read) — existing patterns, dependencies from package.json/requirements.txt
- Git history — past decisions, migration commits
- Local documentation — README, CLAUDE.md, datarim/ docs
- Agent's training knowledge (with caveat: may be outdated, flag uncertainty)

Mark affected checkpoints as `[OFFLINE — based on local context only]` in the insights document.

---

## Gap Discovery Protocol

For use from `/dr-do` when implementation hits an unknown.

### Triggers

A gap is detected when any of these occur during implementation:
- Import or dependency fails unexpectedly
- API returns unexpected response format or error
- Documentation does not match observed behavior
- Required feature is missing from a library
- Compatibility issue between components
- Performance is orders of magnitude worse than expected

### Process

1. Developer agent recognizes the gap and pauses implementation.
2. Load this skill (`research-workflow.md`).
3. Spawn researcher subagent with a **focused query** — not the full checklist, just the specific unknown:
   ```
   Agent(subagent_type="researcher", prompt="Investigate: {specific gap description}. 
   Task: {task-id}. Context: {what was attempted, what failed, what we need to know}.
   Append findings to datarim/insights/INSIGHTS-{task-id}.md § Gap Discoveries.")
   ```
4. Researcher investigates and appends to `## Gap Discoveries` section with:
   - **Date**
   - **Gap description** — what was unknown
   - **Finding** — what was discovered
   - **Resolution** — how to proceed
5. Developer agent reads updated insights and continues implementation.

### Escalation

If the gap is **fundamental** — wrong technology choice, impossible requirement, architectural incompatibility:
- STOP implementation.
- Record the gap in insights.
- Recommend operator run `/dr-prd` to revise requirements.
- Do NOT attempt workarounds for fundamental gaps.

---

## Output Format

Use the insights template at `$HOME/.claude/templates/insights-template.md`.

Create the document at: `datarim/insights/INSIGHTS-{task-id}.md`

### Rules

- Fill only sections where research found relevant information. Do not write placeholder text.
- Each finding should include the source (URL, docs section, file path, or "agent knowledge").
- Flag any finding based on agent training data (not verified externally) with `[unverified]`.
- Keep each section concise — summary + key details, not full documentation dumps.
- Link to external docs rather than copying large blocks.