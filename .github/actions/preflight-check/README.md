# preflight-check@v1

Composite GitHub Action that gates a deploy on **target-host** readiness.
Runs a parameterised set of bash checks before the deploy step writes any
state on the host; on FATAL exits 2 (block deploy); on WARN continues with
`status=warn`; emits a canonical-DTO event to the Ops Bot when non-OK.

Source: `INFRA-0121` (Pre-deploy preflight contract) Phase 1 / `INFRA-0122`.
Underlying script: [`dev-tools/preflight-check.sh`](../../../dev-tools/preflight-check.sh).

---

## Usage

```yaml
jobs:
  deploy:
    runs-on: [self-hosted, linux, arcana-prod, docker]
    steps:
      - uses: actions/checkout@v5

      - name: Pre-deploy preflight
        id: preflight
        uses: Arcanada-one/datarim/.github/actions/preflight-check@v1
        with:
          target-host: arcana-prod
          service-name: opsbot
          extra-checks: |
            vault
            tailscale
            time-skew
            docker-pressure
        env:
          OPSBOT_KEY: ${{ secrets.OPSBOT_KEY }}

      - name: Deploy
        if: steps.preflight.outputs.status != 'fail'
        run: ./deploy.sh
```

Pin to a specific minor for reproducibility (`@v1.0.0`) or to the floating
tag (`@v1`) for automatic non-breaking updates.

---

## Inputs

| Name                  | Default                              | Description |
|-----------------------|--------------------------------------|-------------|
| `target-host`         | *(required)*                         | Logical host (e.g. `arcana-prod`, `arcana-ai`). Used in metric keys + Ops Bot meta. Must match `[a-z0-9-]+`. |
| `service-name`        | *(required)*                         | Service being deployed (e.g. `opsbot`, `auth-arcana`). Must match `[a-z0-9-]+`. |
| `min-free-disk-gb`    | `2`                                  | Minimum free disk GB on each path in `PREFLIGHT_DISK_PATHS`. |
| `disk-warn-percent`   | `80`                                 | Disk used-% triggering WARN. |
| `disk-fail-percent`   | `90`                                 | Disk used-% triggering FATAL (block deploy). |
| `extra-checks`        | `vault\ntailscale\ntime-skew`        | Newline-separated optional checks. See list below. |
| `ops-bot-emit`        | `true`                               | Emit warning/fatal events to Ops Bot. |
| `ops-bot-url`         | `https://ops.arcanada.one/events`    | Ops Bot events endpoint. Validated against the canonical allowlist regex `^https://ops\.arcanada\.one/events$`; PROD trigger contexts (`push` on `main`/`master`/`release/*`) reject non-canonical with exit 1, non-PROD WARN-only. |
| `ops-bot-key`         | `""`                                 | Ops Bot Vault-issued API key. When non-empty, the action's composite step exports it as `OPSBOT_KEY` for the underlying script, eliminating the consumer-side job-vs-step env-scope footgun. Empty (default) ⇒ falls back to runner env `OPSBOT_KEY`. |
| `severity-overrides`  | `""`                                 | Optional JSON object of severity-threshold overrides, e.g. `{"min_free_disk_gb": 5}`. Schema-validated via `jq` before export (object type, allowlisted keys, integer values). Each entry exported as `PREFLIGHT_<UPPERCASE_KEY>=value` into `$GITHUB_ENV` for the downstream Run step. Empty ⇒ skip. Allowlist: `min_free_disk_gb`, `disk_warn_percent`, `disk_fail_percent`, `ram_warn_percent`, `ram_fail_percent`, `loadavg_fatal_multiplier`. |

### Extra checks

| Token              | Behaviour |
|--------------------|-----------|
| `vault`            | `vault status -format=json` with 3× retry; `sealed=true` or `initialized=false` → FATAL. |
| `tailscale`        | `tailscale status --json`; `BackendState!=Running` or `Self.Online!=true` → FATAL. |
| `time-skew`        | `chronyc tracking`; `abs(System time)` > 0.5 s → WARN (never FATAL). |
| `docker-pressure`  | `docker system df --format json`; total reclaimable > 10 GB → WARN. |
| `ram-swap`         | `free -m`; `Mem.free` < 500 MB → FATAL. |
| `loadavg`          | `uptime` 5-min loadavg vs `nproc`; > 1× → WARN, > 2× → FATAL. |
| `health-pre-probe` | `curl $PREFLIGHT_HEALTH_URL`; non-2xx or `status!=ok` → WARN; snapshots body. |

### Per-host overrides

`PREFLIGHT_<HOST_UPPER>_MIN_FREE_DISK_GB` env var (set as `repository variable`)
overrides `min-free-disk-gb` for a specific host. `arcana-prod` →
`PREFLIGHT_ARCANA_PROD_MIN_FREE_DISK_GB`.

### Required env

| Name         | Required | Purpose |
|--------------|----------|---------|
| `OPSBOT_KEY` | when `ops-bot-emit=true` | Bearer token for Ops Bot. Missing key → fail-soft (skip + warn, do not block). |

---

## Outputs

| Name          | Description |
|---------------|-------------|
| `status`      | `ok` \| `warn` \| `fail`. |
| `report-path` | Path to the JSON findings report (also uploaded as artifact). |
| `warnings`    | Number of `warning` findings. |
| `failures`    | Number of `fatal` findings. |

The findings report is uploaded as `preflight-report-<service>-<host>` with
7-day retention.

---

## Exit codes (script-level)

| Code | Meaning |
|------|---------|
| `0`  | All checks ok or warn-only. |
| `2`  | At least one FATAL. Deploy MUST be blocked. |
| `3`  | Input validation failure (bad `target-host` / `service-name`). |
| non-zero | Missing required env (`PREFLIGHT_TARGET_HOST` / `PREFLIGHT_SERVICE_NAME`). |

---

## Ops Bot canonical DTO

When `status != ok` and `OPSBOT_KEY` is set, the action POSTs to
`${ops-bot-url}` with this shape (per `Areas/Infrastructure/CI-Runners.md` §3.1):

```json
{
  "agent": "preflight-check",
  "title": "Pre-deploy preflight: opsbot on arcana-prod [FAIL]",
  "body": "disk: fatal (95 vs 90)|vault: ok (false vs false)|...",
  "category": "fatal",
  "dedup_key": "preflight-arcana-prod-opsbot-20260510-17",
  "meta": {
    "host": "arcana-prod",
    "service": "opsbot",
    "audit_ref": "https://github.com/.../actions/runs/123",
    "checks": [
      {"name": "disk", "status": "fatal", "metric": "used_pct", "actual": "95", "threshold": "90"}
    ]
  }
}
```

`dedup_key` buckets per hour to suppress storms.

---

## Versioning

- Mutable `@v1` floats to the latest `v1.x.y`.
- Immutable `@v1.0.0` for reproducibility.
- Breaking changes bump major (`v2.0.0`). Floating `@v1` is never moved across
  major boundaries.
- A signed `git tag` is published for every release. Consumers SHOULD pin to a
  specific minor unless they explicitly opt into mutable updates.

---

## Security

The action hardens its input surface against several classes of CI supply-chain
abuse. Each guard runs as a composite step **before** the underlying check
script touches the host:

| Guard | Trigger | Effect |
|-------|---------|--------|
| Fork-PR rejection | `github.event_name == 'pull_request' && github.event.pull_request.head.repo.fork == true` | Fails fast (exit 1) before any host metric or secret is read. Prevents fork PR code from exfiltrating runner state or `OPSBOT_KEY`. |
| `ops-bot-url` allowlist | Always (when `ops-bot-emit=true`) | Validates against `^https://ops\.arcanada\.one/events$`. PROD trigger contexts (`push` on `main`/`master`/`release/*`) reject non-canonical URLs with exit 1; non-PROD contexts WARN-only. Blocks event hijack via consumer-supplied URL. |
| `severity-overrides` jq gate | When input non-empty | Top-level type must be `object`; keys must be in a hardcoded allowlist; values must be integers. `jq` parses the payload structurally — keys/values never reach the shell as unquoted tokens. Schema violation ⇒ exit 1 (invocation error). |
| `OPSBOT_KEY` env propagation | Always | Composite-step `env:` resolves `inputs.ops-bot-key` first, then falls back to runner `env.OPSBOT_KEY`. Eliminates the job-vs-step env-scope footgun where a consumer sets `OPSBOT_KEY` at job level but the action's composite step does not inherit it. Key value never echoed to logs. |

The validation helpers are extracted into testable scripts and are exercised by
the bats suite alongside the rest of the action contract:

- `dev-tools/preflight-validate-url.sh` — env-driven (no positional args).
- `dev-tools/preflight-validate-overrides.sh` — env-driven, appends
  `PREFLIGHT_<KEY>=value` lines to `$GITHUB_ENV`.

Mandate cross-reference: ecosystem `CLAUDE.md` § *CI Pre-deploy Health Checks
Mandate* § 4 (severity-overrides), § 7 (SHA-pinning), § 9 (operational trigger
context + `ops-bot-url` PROD canonical).

---

## Local testing

```sh
bats tests/preflight-check.bats          # unit + e2e (mock PATH)
shellcheck dev-tools/preflight-check.sh  # static analysis (severity=warning)
```

The bats suite uses fixture files under `tests/fixtures/preflight/` and
shimmed PATH binaries (one per check). No live system access required.
