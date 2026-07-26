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
- [ ] LC_ALL=C on both tr pipelines in the wiki-orphan pass
- [ ] ${tok_array[@]:-} guard on array deref
- [ ] bats test: --scope=all over fixtures with non-ASCII + wiki/_raw_ files
- [ ] Existing regression tests still pass
