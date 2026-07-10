# Version Consistency Fanout Checklist

Plan-phase template for any task that bumps `VERSION`. Copy this table into the
plan's § File matrix and tick each row that applies to the task's surface —
untouched rows stay unticked with a one-line reason (e.g. "no site-visible
change this release").

| # | Surface | Path | Applies? |
|---|---------|------|----------|
| 1 | Framework VERSION | `code/datarim/VERSION` | |
| 2 | Framework CLAUDE.md | `code/datarim/CLAUDE.md` | |
| 3 | Framework README.md | `code/datarim/README.md` | |
| 4 | Workspace CLAUDE.md | `Projects/Datarim/CLAUDE.md` | |
| 5 | Workspace README.md | `Projects/Datarim/README.md` | |
| 6 | Site config (version) | `Projects/Websites/datarim.club/config.php` | |
| 7 | Site changelog | `Projects/Websites/datarim.club/pages/changelog.php` | |
| 8 | Docs ledger | `code/datarim/docs/getting-started.md` | |

For each ticked row, add the corresponding entry to the plan's § File matrix
(affected-files list) so `/dr-do` picks it up. Rows left unticked MUST carry a
one-line reason inline in this table so a reviewer can tell "considered and
skipped" from "forgotten".
