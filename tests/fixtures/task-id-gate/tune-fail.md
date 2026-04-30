# TUNE-fail fixture

Source incident: TUNE-0042 — a previous reflection where the workflow files
carried foreign uncommitted hunks across sessions. The rule below should be
written without the inline reference.

## Rule (with provenance pollution)

When the workspace shows foreign hunks, do not stash. Per TUNE-0042, stashing
hides another session's work and risks loss.
