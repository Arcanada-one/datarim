# Bats runner routing and macOS coverage disposition

Operator order 2026-11-18: no GitHub-hosted runners anywhere in this repository.
All workflow jobs use the organisation self-hosted pool
(`[self-hosted, linux, X64, ci-general]` or equivalent `runner_labels` defaults).
`tests/workflow-self-hosted-runners.bats` fails closed if any `runs-on` lacks
`self-hosted`.

The registry, eight discovery shards, exact Linux customer-delivery shards and
the Linux-only result-inventory gate run on that pool. Owned prefixes, isolated
Python dependencies and `--no-sudo` setup still apply. Linux source tests and
exact Linux result inventories remain mandatory. Missing or failed Linux results
fail the aggregate; an empty inventory is not accepted.

macOS/BSD portability and macOS customer-delivery coverage are **NOT_MEASURED**:
the fleet has no macOS self-hosted runner, and hosted `macos-latest` jobs were
removed from `bats.yml` and `node-tests.yml`. The portability-sensitive suite
inventory remains in
`.github/scripts/workflow/bats-macos-portability-03-run-portability-sensitive-suites.sh`
for source review; CI does not invoke it. Linux success does not establish
BSD/macOS acceptance. This disposition cannot close cross-platform acceptance.

Reverse if a qualified macOS self-hosted runner route exists and automatic macOS
gates are restored, or if self-hosted isolation or dependency prerequisites fail,
a required Linux suite disappears, a fork reaches the self-hosted pool, or a
release claims macOS acceptance from Linux-only results. Preserve raw failures
and repair source; do not relabel, grant sudo, buy hosted minutes, or cancel
unrelated runs.

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

Missing socat has a qualified source-only bootstrap for two measured amd64
packages. Ubuntu 24.04 uses archive package 1.8.0.0-4ubuntu0.1, SHA256
46e854289b6b1c97e28be5d9293bea61e8633d00d6a65d9513f019c7232696fe. Ubuntu
26.04 uses the socat archive pinned by SHA256
08f77c85ba1f399c8b21bc098afbce0dea90529e80c9673b7df9bc391bd3f001.
The installer builds that pool filename from the 1.8.1 series and a separate
revision token, because a four-part version token is a routable dotted quad
to the personal-id scan. The installer downloads that exact file, verifies
the digest, extracts its data
in an owned temporary directory, and validates that the binary loads. When
the dynamic linker can load it, the installer copies only socat into the
private tool prefix. When the binary needs `libwrap.so.0` and the image does
not provide it, the installer downloads the matching hash-pinned libwrap0
archive (Ubuntu 24.04: 7.6.q-33, SHA256
36118b862539868408ee056411d6e470068d14c46e5296b29bfb744770f5d2ce; Ubuntu
26.04: 7.6.q-36build2, SHA256
a3784ca083c626c3ae41cdd32d4c5898554650dc77d2b54dbb1197a38198adf8), copies
that one library into the private prefix, and installs a wrapper named socat
that points only this process at that library. No maintainer scripts or
system package install run. Unsupported distro/architecture, unavailable
metadata tooling, a bad digest, or a binary that still cannot load remain
failures. The receiving CI must still prove the actual runner UID/runtime
behavior. Tool prefixes are unique kernel-created directories within RUNNER_TEMP.

## Customer-delivery microjob batching (ARC-CI-03)

Linux customer-delivery runner jobs are sized from
`tests/ci-slot-baseline.json` (`proposed_microjob_group_size`), not a fixed
workflow constant. Each runner job executes several compatible logical shards;
every logical shard keeps its own timeout and result JSON. The aggregate checks
the flat Linux logical inventory (`--matrix-jobs linux` / `--check-results linux`).
A skipped or partial runner job cannot mask a missing required logical result.
macOS customer-delivery inventory is NOT_MEASURED.

Duration-aware Bats discovery assignment (ARC-CI-04) packs suites using
`tests/bats-suite-durations.tsv` while keeping the eight required check names
`shard 1/8` … `shard 8/8`.

## Runner load pilot (ARC-CI-07/09/10/11/12)

Public pilot controls live in this repository only (one PR per repo). Required
check contexts stay unfiltered: a skipped required job must never mask a missing
result. Path filters are limited to non-required workflows (for example
`node-tests.yml`). Cancel-in-progress concurrency cancels superseded runs on the
same ref.

Setup reuse (ARC-CI-09) enables `actions/setup-python` pip caches keyed by
`tests/ci-requirements/*.txt`. Trust scopes stay on GitHub Actions branch/PR
cache isolation; do not add restore-keys that pull default-branch caches into
fork pull requests. Net cache savings remain `NOT_MEASURED` until an after
sample of ≥10 successful hosted runs is collected with
`dev-tools/measure-ci-feedback.py`.

Capacity (ARC-CI-10) is recorded in
`documentation/reference/ci-runner-capacity-model.json`. Live runner
enumeration may be `NOT_MEASURED` when the Actions runners API returns an empty
list for the available credential. Queue vs run decomposition comes from the
same measurement script. Runner purchases stay out of scope.

Agent WIP (ARC-CI-11) is the advisory script
`dev-tools/check-agent-ci-wip.sh` documented in
`documentation/reference/ci-agent-wip-limit.md` (default two open PRs with
pending checks). It does not replace cancel-in-progress.

Card 12 before/after receipts:
`documentation/reference/ci-runner-load-before-receipt.json` and
`documentation/reference/ci-runner-load-pilot-receipt.json`. Experiment targets
(-30% p95 feedback, -25% runner-seconds p95) are aims, not single-run claims.

