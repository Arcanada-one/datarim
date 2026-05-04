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

## Pre-Flight Artifact Discovery

Plans drift. Between `/dr-plan` and `/dr-do`, the surrounding state of the project may have moved — earlier tasks landed, services got deployed, schemas changed, infrastructure resources got renamed. Running implementation against a stale plan wastes effort and may discard work that already shipped.

### Trigger

Run at the start of `/dr-do` (Step 0, before the TDD loop), for any task that references named artifacts assumed to exist or not exist:

- File paths in another repo or service ("source file will be created" / "extend an existing module")
- Deployed services or endpoints ("a service already exposes a route")
- Infrastructure resources ("policy not yet defined", "key not yet provisioned")
- Database schemas / migrations
- Build outputs, deployed binaries, on-disk caches

### Procedure

1. **Enumerate the named artifacts** in the plan and PRD.
2. **For each one, verify the current state** against the live source — read the file, query the API, list the resource, inspect the deployed service. Use the same observation tools the plan would have used at write time.
3. **Compare against the plan's assumptions.** Three outcomes:
   - **Match** — proceed with implementation as planned.
   - **Already done** — the deliverable is already shipped (a prior task extended scope, a parallel session merged earlier). Mark the step vacuous in `tasks/{TASK-ID}-task-description.md` § Progress and skip.
   - **Drift** — artifact exists but in a different shape than assumed. Pause, document the gap in `insights/INSIGHTS-{TASK-ID}.md` § Gap Discoveries with the diff, and pivot the plan if needed before writing code.
4. **If pivot crosses approach boundaries** (a different alternative from PRD § Solution Exploration becomes the right choice), escalate — re-read the rejected alternatives in PRD, capture the rationale for the pivot in INSIGHTS § GD-NN, and proceed with the new approach.

### Why this matters

A plan written 2-3 days ago against a snapshot of the project state can be wrong about: which modules are already wired, which infra resources already exist, which secrets are already migrated. Acting on those assumptions wastes hours of implementation and sometimes deletes shipped work. A short pre-flight scan replaces those losses.

### When to skip

The plan was written within the last 24 hours, no parallel sessions touched the same area, and no prior tasks in the same project have shipped between plan and implementation. Otherwise: run pre-flight.

### Source

INFRA-0015 Phase 1 (2026-05-04): plan called for one integration approach; pre-flight discovery showed that an earlier task in the same project had already shipped the alternative approach (a substantial body of working code). Following the plan would have discarded shipped work. Pivot to the rejected-but-now-correct alternative was captured in `INSIGHTS-INFRA-0015.md` § GD-01. Phase 1 effort dropped from a planned 1-2 days to ~2 hours by following the plan's already-rejected alternative — with a concrete reason for the pivot rather than blind execution.

---

## Empirical Provider Verification

When a plan locks in a third-party endpoint (LLM, STT/TTS, OAuth, payment, webhook target, queue, storage API, anything not under our control), **the contract MUST be confirmed by a real request before any code depends on the assumed shape**. Documentation drifts; SDKs paper over differences; existing integrations may have been written against a different paradigm.

### Trigger

Run this gate during `/dr-plan` Step 6 (Technology Validation) or `/dr-do` pre-flight when the task introduces or replaces a third-party endpoint.

### Procedure

1. **Endpoint shape probe.** Send the smallest valid request (curl / `httpx` / `fetch`) that exercises the *real* input format the implementation will use — including `Content-Type`, auth header, multipart shape, query params, and any vendor-specific flags (`response_format`, `stream`, `modalities`, etc.).
2. **Capture the response into a fixture file** (`datarim/tasks/{TASK-ID}-fixtures.md`) per the existing `dr-plan` Step 10 fixture rule. Tag with timestamp + endpoint URL + auth method + tool/SDK version.
3. **Capture an error case too** (bad auth, malformed payload, oversized input) — most third-party APIs encode errors inside JSON with HTTP 200/201, not via status codes.
4. **Compare the captured response shape against the plan's assumptions.** If a field name, content-type, modality, or required flag differs, revise the plan before writing code.

### Why this matters

Mock providers, stale README files, and "this worked in another project" memories are not evidence. A 3-minute probe against the real endpoint replaces an unknown number of mid-implementation rewrites and one or more push-rebuild-redeploy cycles when the assumption was wrong.

### When to skip

The endpoint is already covered by a green integration test in this codebase, run within the past 14 days against the same provider/model/version. Otherwise: run the probe.

### Source

Real incident: ~30 minutes of Groq integration test scaffolding had to be redone after empirically discovering that OpenRouter's audio models require `output modality=audio + stream:true` and have no Whisper in their catalog — the existing `transcriber-openrouter.service.ts` was conceptually broken from day one, hidden by a mock provider. A 3-minute curl test against the three audio model IDs would have surfaced the gap before any spec was written.

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