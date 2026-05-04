# Escape-hatch fixture

Some templates legitimately need task-ID slots as illustrative parameters or
example placeholders. The block below uses the gate's escape hatch.

<!-- gate:history-allowed -->
Example backlog entry shape:

- INFRA-0099 · pending · P2 · L2 · Vault MFA Rollout → tasks/INFRA-0099-task-description.md
- TUNE-0042 · in_progress · P2 · L1 · Example follow-up → tasks/TUNE-0042-task-description.md
<!-- /gate:history-allowed -->

The remainder of the file is process-only prose with no inline IDs. Templates
should wrap *only* the example block, never load-bearing rule prose.
