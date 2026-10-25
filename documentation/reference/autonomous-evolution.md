# Autonomous Evolution Reference

| Item | Contract |
|------|----------|
| Entry point | Passing `/dr-compliance` Step 8.5 during `/dr-auto` or `/dr-orchestrate` |
| Decision | `apply`, `decline`, or `defer` per proposal |
| Class B | PRD or equivalent contract draft plus independent blind reviewer concurrence |
| Pre-write checks | Stack-agnostic, history-agnostic, English-only instruction body |
| Post-write checks | Bats tests reading every touched file, then full `bats tests/` sequentially |
| Failure | Restore proposal-owned bytes; record `declined: gate <name> failed` |
| Decision ledger | Current KB's `datarim/history/evolution-log.md` |
| Consumer target | Project-owned `datarim/local/` for executable overrides; `AGENTS.md` for project rules; promotion candidate logged separately |
| Opt-out | `datarim/config/evolution.yaml` with exactly `auto_apply: false` |

`dev-tools/evolution-route.py --root <workspace>` returns JSON containing
`scope` (`framework` or `consumer`) and `auto_apply` (boolean). It requires a
workspace with `datarim/`; malformed configuration exits 2. The framework
scope requires the exact source repository root, canonical origin remote, and
source markers. All other workspaces are consumer scope.
