---
id: TUNE-0499
title: "Sync activeContext.md with tasks.md § Active"
status: pending
priority: P3
complexity: L2
type: docs
project: Datarim
started: 2026-07-26
parent: null
related: []
---

## Overview

activeContext.md § Active Tasks must be an exact mirror of tasks.md § Active.
This task ensures they match, updates the Last Updated timestamp, and adds
a guard to prevent future drift.

## Steps
1. Read datarim/tasks.md § Active section
2. Read datarim/activeContext.md § Active Tasks section
3. If they differ, mirror tasks.md into activeContext.md
4. Update Last Updated timestamp in activeContext.md

## Constraints
- Only mirror, never invent or reorder
- ≤30-line bound per datarim-doctor schema
