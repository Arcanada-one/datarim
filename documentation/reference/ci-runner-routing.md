# Bats runner routing and macOS coverage disposition

Root authorized this reversible change on 2026-10-07 after PR497 run
37663848888 reported Linux jobs 112939349315 and 112939349244 in
`Install pinned toolchain` for over three hours. The organization CI convention
records hosted billing unavailable (VERD-0058). The exact provider cause of
those individual job states was not independently measured.

The registry, eight discovery shards, exact Linux customer-delivery shards and
result-inventory gate use the existing `[self-hosted, linux, X64, ci-general]`
pool. Inventory found nine online matching carriers and no macOS carrier.
No runner, label, grant, account or scheduler is changed. Fork PRs are excluded
from these self-hosted jobs by the registry and aggregate guards; a skipped fork
run is not admitted coverage. Existing tests and shard policies are preserved.
Missing Linux results, failed tests and invalid inventories still fail the
Linux aggregate; an empty inventory is not accepted.

The two real macOS jobs remain in source, but automatic PR/main runs omit them.
The aggregate reports macOS `NOT_MEASURED`; Linux success does not establish
BSD/macOS portability or full customer delivery. This is an operator-authorized
coverage disposition, not a successful macOS check or a gate exemption receipt.
Source review, graph qualification, current-head CI and ordinary stock gate
remain separate. This disposition cannot close cross-platform acceptance.

After an existing owner qualifies hosted macOS availability without buying
capacity or changing authority, run this workflow on the exact admitted source
using `workflow_dispatch` with `run_hosted_macos: true`. Both macOS jobs and
both exact result inventories then run; failed/skipped/missing macOS results
cannot become a successful aggregate. No hosted availability is claimed now.

Reverse if self-hosted isolation or dependency prerequisites fail, a required
Linux suite disappears, a fork reaches the self-hosted pool, or a release
claims macOS acceptance from Linux-only results. Preserve raw failures and
repair source; do not relabel, grant sudo or cancel unrelated runs. Restore
automatic macOS gates after a qualified runner route exists.
