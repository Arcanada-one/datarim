# Bats runner routing and macOS coverage disposition

Root authorized this reversible change on 2026-10-07 after PR497 run
37663848888 reported Linux jobs 112939349315 and 112939349244 in
`Install pinned toolchain` for over three hours. The organization CI convention
records hosted billing unavailable. The exact provider cause of
those individual job states was not independently measured.

The registry, eight discovery shards, exact Linux customer-delivery shards and
result-inventory gate use ubuntu-latest for this public repository, following
Root's updated per-job policy to preserve working public hosted jobs. Historical
exact-head hosted successes establish that hosted execution is not universally
unavailable here; they do not prove current queue time or new-head acceptance.
The earlier self-hosted route exposed a required root wrapper control unavailable
on the persistent pool. That control remains required; no sudo grant or test
skip is added. The existing Jev contract job retains its original self-hosted
route. No runner, label, account or scheduler is changed.

Owned prefixes, isolated Python dependencies and --no-sudo setup still apply.
Linux source tests and exact result inventories remain mandatory. Missing or
failed Linux results fail the aggregate; an empty inventory is not accepted.
Current changed-head natural CI and independent review must qualify the route.

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

## Unprivileged toolchain setup

The self-hosted discovery and Linux customer-delivery jobs install the pinned
bats/yq toolchain under their own RUNNER_TEMP prefixes and export only the
corresponding bin directory through GITHUB_PATH. Python dependencies use the
existing isolated venv. The installer receives --no-sudo: it never tries sudo
or installs system packages in this mode, even when run as root. Missing
jq/shellcheck/socat prerequisites remain explicit failures; the workflow cannot
provision shared runner hosts or pretend the missing fixture passed. A current
customer-delivery failure on a different carrier reported missing socat; that
runner prerequisite is separate from the demonstrated /usr/local write defect.

Missing socat now has one qualified source-only bootstrap: on Ubuntu 24.04
amd64, download the exact 1.8.0.0-4ubuntu0.1 archive package, verify SHA256
46e854289b6b1c97e28be5d9293bea61e8633d00d6a65d9513f019c7232696fe,
extract its data in an owned temporary directory, validate the binary loads,
and copy only socat into the private tool prefix. No maintainer scripts or
system package install run. Unsupported distro/architecture, unavailable
metadata tooling, bad digest or missing runtime libraries remain failures.
The receiving CI must still prove the actual runner UID/runtime behavior.
Tool prefixes are unique kernel-created directories within RUNNER_TEMP.
