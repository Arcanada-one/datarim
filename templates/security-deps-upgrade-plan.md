# Security / Deps Upgrade Plan — {TASK-ID}

> Use for maintenance tasks closing dependency CVEs, framework version bumps, transitive overrides. Stack-neutral — fill in the package-manager / language commands relevant to the project (see project CLAUDE.md for the canonical stack).

## Baseline Audit Snapshot

```
$ <package-manager-audit-command>
```

| Severity | Count | Notes |
|---|---|---|
| critical | | |
| high | | |
| moderate | | |
| low | | |
| **TOTAL** | | |

Capture full output to `datarim/qa/qa-{TASK-ID}-baseline.txt` (gitignored).

## CVE / Advisory Resolution Plan

| CVE / Advisory | Severity | Component | Resolution Path |
|---|---|---|---|
| GHSA-xxxx-yyyy-zzzz | high | `package@version-range` | upgrade `package` to `^X.Y.Z` |
| GHSA-... | moderate | transitive via `parent-pkg` | add `overrides`/`resolutions` for `child-pkg@^X.Y.Z` |
| GHSA-... | moderate | `package@version-range` | remove dependency (replace with native API / alternative) |

**Total CVEs to close:** N
**Target post-upgrade audit count:** 0 (or explicit residual list with rationale)

## Live Audit Checkpoint (mandatory before commit-ing plan)

Per `$HOME/.claude/skills/ai-quality.md` § Live Audit Checkpoint — verify the proposed lock against a disposable manifest BEFORE touching production.

```
1. mkdir -p /tmp/dr-plan-audit-{TASK-ID}
2. cp <project>/package.json /tmp/dr-plan-audit-{TASK-ID}/   # or pyproject.toml / Cargo.toml
3. apply proposed dep changes in /tmp manifest
4. <package-manager-install-command>     # e.g. pnpm install --lockfile-only
5. <package-manager-audit-command>       # e.g. pnpm audit
6. confirm count matches plan target
```

**Result recorded:**
- Stub path: `/tmp/dr-plan-audit-{TASK-ID}`
- Resolved versions of touched packages: ...
- Audit count: ... (target: ...)

## Compatibility Matrix

| Layer | Floor (this upgrade) | Production (current) | Status |
|---|---|---|---|
| Language runtime | (e.g. Node 20+ for NestJS 11) | (Dockerfile / server config) | ✅ / ⚠ |
| Major framework | (e.g. NestJS ≥ 11) | | |
| Adjacent libs | (e.g. Mongoose ≥ 8 for NestJS 11) | | |
| Test runner | | | |
| Build tool | | | |

## Implementation Steps (TDD-driven where relevant)

1. **Audit baseline capture** — run audit, save to `qa-{TASK-ID}-baseline.txt`
2. **Manifest edit + lockfile regen** — apply diff, regenerate lockfile
3. **Code migrations** (if any) — e.g. axios → fetch, removed APIs, breaking changes
4. **Test suite** — existing tests must remain green; add tests for new code paths
5. **Build verification** — clean compile / type check
6. **Smoke test** — bootstrap-level OR live HTTP / DB call where feasible
7. **Audit gate** — final audit must hit target count
8. **Commit + push** — commit body cites GHSA-IDs + before/after counts

## Test Plan

- **Unit:** ... (list tests that act as compatibility proxy)
- **Build:** ... (`<build-command>`)
- **Smoke:** ... (deferred-to-deploy items documented)
- **Audit gate:** ... (`<audit-command>` → target: 0 vulns)

## Rollback Strategy

**Trigger:** post-deploy error rate spike, smoke test failure pre-deploy.

**Procedure:**
1. **Pre-deploy:** `git checkout <manifest> <lockfile> <touched-source-files> && <package-manager-install>` — back to baseline.
2. **Post-deploy:** redeploy previous artifact (image / build) — `<rollback-command>`.
3. **Plan B:** if upgrade breaks something unforeseen at runtime after passing unit tests + build, save attempt branch, open follow-up for investigation.

**Verification commands:**
- `git log --oneline -5` — revert commit visible
- `<package-manager-list> <pinned-package>` — resolves back to baseline version
- Live health check post-rollback

## Validation Checklist

```
[ ] Requirements clearly documented (CVE list + AC)
[ ] Components and affected files identified
[ ] Live Audit Checkpoint executed (/tmp stub, 0 vulns confirmed pre-implementation)
[ ] Definition of Done is testable (audit count, test count, build clean)
[ ] Boundaries stated (what's in scope; what's NOT)
[ ] Technology stack validated (runtime floor ≤ production runtime)
[ ] Rollback strategy viable (git revert + reinstall — both repo and lock available)
[ ] TDD compatibility verified (existing tests survive the upgrade)
[ ] tasks.md updated with implementation plan
```

## Next Steps

→ `/dr-do {TASK-ID}` — implementation per the steps above.