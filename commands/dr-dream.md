---
name: dr-dream
description: Knowledge base maintenance — organize, deduplicate, cross-reference, and consolidate the datarim/ directory. Processes misplaced files, builds connections between documents, flags contradictions, and archives stale content. Run periodically or when the knowledge base feels messy.
argument-hint: [lint | index | full]
allowed-tools: Read Write Edit Grep Glob Bash Agent
effort: high
---

# /dr-dream — Knowledge Base Maintenance

**Role**: Librarian Agent
**Source**: `$HOME/.claude/agents/librarian.md`

> Like sleep consolidates memory in the brain, Dream consolidates knowledge in the project.

## When to Run

- **After many tasks** — when `datarim/` has grown and feels disorganized
- **After `/dr-archive`** — auto-suggested if >5 documents were created since last dream
- **Before a new project phase** — clean up before starting fresh work
- **When you can't find things** — if searching for a document takes too long
- **Periodically** — every 10-15 completed tasks as routine maintenance

## Modes

| Invocation | What it does | Duration |
|------------|-------------|----------|
| `/dr-dream` | Full maintenance: ingest + lint + consolidate | 2-5 min |
| `/dr-dream lint` | Health check only, no changes | 1 min |
| `/dr-dream index` | Rebuild `datarim/index.md` only | 30 sec |

## Instructions

1.  **LOAD**: Read `$HOME/.claude/agents/librarian.md` and adopt that persona.
2.  **LOAD SKILLS**:
    - `$HOME/.claude/skills/datarim-system.md` (Always — file locations and naming rules)
    - `$HOME/.claude/skills/dream.md` (Knowledge base maintenance rules)
3.  **RESOLVE PATH**: Find `datarim/` using standard path resolution. If not found, STOP.
4.  **DETERMINE MODE**: Parse `$ARGUMENTS`:
    - `lint` → Quick lint only (step 5)
    - `index` → Rebuild index only (step 8)
    - Empty or `full` → Full maintenance (steps 5-10)

### Step 5: Inventory
Scan `datarim/` recursively. For every `.md` file, record:
- Path, filename, size (lines)
- Frontmatter (if present): title, task_id, type, status, tags, related
- Directory it belongs to (prd/, tasks/, reflection/, etc.)
- Inbound and outbound links (references to/from other files)

Present summary:
```
=== KNOWLEDGE BASE INVENTORY ===
Total documents: NN
By type: PRDs: N, Tasks: N, Reflections: N, QA: N, Archives: N, Other: N
With frontmatter: N / NN (XX%)
Orphans (no inbound links): N
```

### Step 6: Ingest Check
Find structural problems:
- Files in wrong directories (PRD not in `prd/`, reflection not in `reflection/`)
- Files missing task ID in filename
- Files with no frontmatter
- Broken internal links (references to files that don't exist)
- Inconsistent naming (not matching `[type]-[task_id]-[name].md` pattern)

### Step 7: Lint
Run all health checks from the dream skill:
- Contradictions between documents
- Stale references (completed tasks still marked active)
- Orphan files (no inbound links)
- Duplicate content (>70% overlap between two files)
- Cross-reference symmetry (A→B but not B→A)
- Empty directories
- Oversized files (>500 lines)

### Step 8: Build/Update Index
Create or update `datarim/index.md`:
- Catalog all documents by type
- Group by tags (if frontmatter has tags)
- List recent activity (last 10 changes)
- Show knowledge graph metrics (total docs, connections, orphans)

### Step 9: Consolidate (full mode only)
Propose structural improvements:
- **Merge duplicates** — combine documents with >70% content overlap
- **Extract patterns** — recurring themes across reflections → create `docs/patterns.md`
- **Archive stale** — move completed/obsolete docs to `archive/`
- **Add cross-references** — bidirectional links between related documents
- **Add frontmatter** — fill in missing metadata where inferable
- **Fix naming** — rename files to match conventions

### Step 10: Report and Apply

Present the Dream Report:
```
=== DREAM REPORT ===

Health: HEALTHY / NEEDS ATTENTION / MESSY
Documents scanned: NN
Issues found: N (critical: X, warning: Y, info: Z)

=== INGEST ===
- N misplaced files
- N naming inconsistencies
- N missing frontmatter

=== LINT ===
- N contradictions
- N orphan files
- N broken links
- N stale references
- N duplicates

=== CONSOLIDATION PROPOSALS ===
1. [merge] Merge duplicate-a.md and duplicate-b.md → single-doc.md
2. [archive] Move 3 completed task docs to archive/
3. [cross-ref] Add 8 bidirectional links
4. [frontmatter] Add metadata to 5 documents
5. [rename] Fix naming for 2 files

Which proposals should I apply? (all / none / comma-separated numbers)
```

Wait for approval. Apply only approved changes.

### Step 11: Log
Append maintenance summary to `datarim/docs/activity-log.md`.

## Output
- Knowledge base inventory
- Lint report with all issues
- Updated `datarim/index.md`
- Consolidation proposals (if full mode)
- Activity log entry

## Next Steps
- Issues need human resolution? → Review contradictions and decide
- Knowledge base is clean? → Continue with `/dr-init` for next task
- Framework itself needs optimization? → `/dr-optimize`
