---
name: evolution/disaster-recovery
description: Recovery checklist for lost runtime files. Load when files in $HOME/.claude/ are lost or corrupted.
---

# Disaster Recovery for Lost Runtime Files

When runtime files in `$HOME/.claude/` are lost or corrupted (overwrite, accidental `install.sh --force`, deletion), do NOT declare them "unrecoverable" until the following checklist has been run. TUNE-0011 recovered 4 files that TUNE-0003 archive had declared impossible to reconstruct — the difference was exhaustive source discovery.

## Recovery Checklist (apply in order, ~5 minutes per channel)

1. **Grep all reflection docs by filename** — not just reflections of the "obvious parent" task. Search every `datarim/reflection/*.md` across all projects in the incident window for any mention of the lost filename. A reflection from an unrelated task may have proposed changes to the file (as WEB-0002 P4 did for `tester.md`).
2. **Check compacted session contexts** — if the incident happened in a session where the lost skill/command was previously invoked via the Skill tool, its content is preserved in the session's system-reminder blocks and survives `/compact`. See `skills/utilities/recovery.md` for extraction recipe.
3. **Follow cross-references** — when file A documents that file B has section §X (e.g. `dr-qa.md` Layer 4d references `testing.md § Live Smoke-Test Gate`), the cross-reference is an implicit spec for B.§X even if B is lost. Reconstruct by synthesizing B.§X from A's description of it.
4. **Git history of consumer projects** — if the lost file is framework code used by multiple projects, commits in those projects during the incident window may reveal how the file was being used, implying its pre-incident structure.
5. **External backups — last resort only** — Time Machine, APFS snapshots, cloud sync, backup daemons. Check existence *before* relying on it; none may be present.

## Rule

**No "Known Loss" claim may be recorded without first running the 5-channel checklist.** If a channel yields content — recover, curate, move on. If all 5 are exhausted — only then declare loss, and record which channels were checked in the archive document (not just "not possible").

## Why this exists

TUNE-0003 archive claimed 4 files "text reconstruction not possible" after 0 minutes of discovery. TUNE-0011 recovered 100% of them in 20 minutes using channels 1-3. The cost of this checklist is ~25 minutes; the cost of a false "loss" claim is permanent content gap plus eroded trust in archive accuracy.