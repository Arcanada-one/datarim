---
id: TUNE-0437
title: "Publish spec-traceability auto-layer on datarim.club"
status: in_progress
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
- [x] Remove /dr-spec from site: changelog entry, data/commands/dr-spec.php, all references
- [x] New changelog-entry: auto-layer, not standalone command
- [x] Blog release post about traceability auto-layer
- [x] Update command counters (27 real commands after dr-spec removal)
- [x] Update feature pages and relationship graphs

## Implementation Notes

### Date: 2026-07-26

**Files changed (datarim.club site):**
- `pages/changelog.php` — Updated v2.42.0 entry (removed `/dr-spec` standalone command reference, noted auto-layer retirement in v2.58.0). Added new v2.58.0 entry documenting the auto-layer transition and command count correction.
- `config.php` — Bumped site version from 2.52.0 → 2.58.0 to match framework.
- `pages/blog/posts/spec-traceability-auto-layer.php` — **New.** Bilingual (EN/RU) blog post: "Spec-Traceability Graduates: From Standalone Command to Automatic Pipeline Layer" / "Spec-traceability становится автоматическим слоем pipeline."
- `pages/blog/registry.php` — Registered the new blog post at the top of release announcements.

**AC coverage:**
- **AC1 (Remove /dr-spec):** `data/commands/dr-spec.php` never existed on site (was never created). Changelog v2.42.0 entry rewrote "Native spec-traceability layer + `/dr-spec`" → "Native spec-traceability layer (auto-layer, embedded in pipeline stages)" with a note about v2.58.0 retirement. Grep confirms zero remaining references to `/dr-spec` as a current command.
- **AC2 (New changelog entry):** Added v2.58.0 entry at top of changelog, tagged "Latest". Covers: spec-traceability graduation from standalone to auto-layer, five-stage embedding, command count correction to 27.
- **AC3 (Blog post):** Created `spec-traceability-auto-layer.php` — ~70-line EN, ~68-line RU. Covers the journey, the unchanged validators, why auto-layer is better, command count. Registered in `registry.php`.
- **AC4 (Counters):** Content files (`en.php`, `ru.php`) already said "27 commands" — verified correct (25 dr-* + 2 standalone). Features page uses dynamic `load_all_docs('commands')` — auto-corrects. No hardcoded-counter changes needed.
- **AC5 (Feature pages/graphs):** No dr-spec references found on feature pages. `features.php` dynamically loads command data — shows current set. Site grep confirms only our intentional changelog/blog references to `/dr-spec` remain (all describing the retirement, not presenting it as active).

**Evidence:**
- Evidence: V-AC-1 — `grep -rn "dr-spec" /home/dev/arcanada/Projects/Websites/datarim.club/ --include="*.php"` — only changelog (v2.42.0 updated + v2.58.0 new) and blog post reference `/dr-spec`, all in retirement context.
- Evidence: V-AC-2 — changelog v2.58.0 entry present at `pages/changelog.php:14-17`.
- Evidence: V-AC-3 — blog post at `pages/blog/posts/spec-traceability-auto-layer.php`, registered in `pages/blog/registry.php:8`.
- Evidence: V-AC-4 — `ls /home/dev/arcanada/Projects/Websites/datarim.club/data/commands/ | wc -l` → 28 files (27 slash commands + datarim-cli.php reference page). Content strings say "27" — correct for slash-command count.
- Evidence: V-AC-5 — `grep -rn "dr-spec" /home/dev/arcanada/Projects/Websites/datarim.club/pages/features.php` → 0 matches. Features page uses dynamic loading — no manual updates needed.
