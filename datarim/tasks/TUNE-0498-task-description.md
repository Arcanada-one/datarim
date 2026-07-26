---
id: TUNE-0498
title: "Fix datarim-doctor.sh macOS bash-3.2 --scope=all crash"
status: pending
priority: P2
complexity: L2
type: fix
project: Datarim
started: 2026-07-26
parent: null
related: []
---

## Overview
Two crashes in scripts/datarim-doctor.sh --scope=all on macOS bash-3.2:
1. head -c 300 on a non-ASCII file splits mid-multibyte → tr aborts with "Illegal byte sequence"
2. set -u on an empty tok_array throws "unbound variable"

## Acceptance Criteria
- [x] LC_ALL=C on both tr pipelines in the wiki-orphan pass
- [x] ${tok_array[@]:-} guard on array deref
- [x] bats test: --scope=all over fixtures with non-ASCII + wiki/_raw_ files
- [x] Existing regression tests still pass

## Implementation Notes
### Fix 1: LC_ALL=C on tr pipelines (line 637-638)
`LC_ALL=C` prepended to all three `tr` invocations in `scan_wiki_raw_orphans()`:
- `tokens=` pipeline: `LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -c '[:alnum:]' ' '`
- `content_lower=` pipeline: `LC_ALL=C tr '[:upper:]' '[:lower:]'`

Without this, `head -c 300` can split a multibyte UTF-8 character mid-sequence on
a non-ASCII file. BSD `tr` (macOS bash-3.2) then aborts with "Illegal byte sequence".
`LC_ALL=C` forces byte-level processing, which is safe for the [:upper:]/[:lower:] and
-c [:alnum:] character classes used here.

### Fix 2: Empty-array guard (line 644)
`"${tok_array[@]}"` → `"${tok_array[@]:-}"` in the for-loop. When a filename
stem produces zero tokens after `tr -c '[:alnum:]' ' '` (e.g. `---.md` strips to
empty string), `read -ra tok_array <<< ""` creates an empty array. Under `set -u`,
`${tok_array[@]}` throws "unbound variable" on bash-3.2. The `:-` default-expansion
substitutes an empty list safely.

### Tests added (tune-0121-wiki-raw-orphan-check.bats)
- **T7**: `--scope=all` with non-ASCII (Cyrillic) content + mismatched ASCII basename → exit 1, no "Illegal byte sequence"
- **T8**: `--scope=all` with non-alnum-only filename (`---.md`) → exit 0, no crash (empty token array guard)
- **T9**: `--scope=all` with em-dash in first 300 bytes + matching basename → exit 0, no crash

### Regression verification
All existing tests pass (99/99 across 4 test files): datarim-doctor.bats (54),
datarim-doctor-execution-drift.bats (24), datarim-doctor-history-migration.bats (13),
doctor-root-contract.bats (8).

Evidence: V-AC-1 — `bats tests/tune-0121-wiki-raw-orphan-check.bats` (9/9 pass)
Evidence: V-AC-2 — `bats tests/datarim-doctor.bats` (54/54 pass)
Evidence: V-AC-3 — `shellcheck -x scripts/datarim-doctor.sh` (no new findings)
Evidence: V-AC-4 — `bats tests/datarim-doctor-execution-drift.bats tests/datarim-doctor-history-migration.bats tests/doctor-root-contract.bats` (45/45 pass)
