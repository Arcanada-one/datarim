#!/usr/bin/env bash
# preflight-check.sh — pre-deploy host health gate; INFRA-0122 / INFRA-0121.
#
# Validates target-host readiness before deploy. On FATAL exits 2 (block deploy);
# on WARN exits 0 with status=warn; emits Ops Bot canonical-DTO event when
# non-ok. Designed to run inside the composite action
# .github/actions/preflight-check@v1 — env-vars wire all inputs.
#
# Sourceable: when this file is sourced (e.g. from bats), the main entrypoint
# is skipped so check_* helpers can be exercised in isolation.

# Per-function safety: set -u/-o pipefail are global; -e is enabled only in
# main mode so sourcing tests can `run check_*` without inheriting strict-exit.
set -uo pipefail

# === ENV (inputs from composite action; defaults match action.yml) ===
PREFLIGHT_MIN_FREE_DISK_GB="${PREFLIGHT_MIN_FREE_DISK_GB:-2}"
PREFLIGHT_DISK_WARN_PERCENT="${PREFLIGHT_DISK_WARN_PERCENT:-80}"
PREFLIGHT_DISK_FAIL_PERCENT="${PREFLIGHT_DISK_FAIL_PERCENT:-90}"
PREFLIGHT_EXTRA_CHECKS="${PREFLIGHT_EXTRA_CHECKS:-}"
PREFLIGHT_OPS_BOT_EMIT="${PREFLIGHT_OPS_BOT_EMIT:-true}"
PREFLIGHT_OPS_BOT_URL="${PREFLIGHT_OPS_BOT_URL:-https://ops.arcanada.one/events}"
PREFLIGHT_RUN_URL="${PREFLIGHT_RUN_URL:-unknown}"
PREFLIGHT_DISK_PATHS="${PREFLIGHT_DISK_PATHS:-/ /var/lib/docker /srv/apps}"
PREFLIGHT_HEALTH_URL="${PREFLIGHT_HEALTH_URL:-}"
PREFLIGHT_VAULT_RETRIES="${PREFLIGHT_VAULT_RETRIES:-3}"
PREFLIGHT_VAULT_RETRY_DELAY="${PREFLIGHT_VAULT_RETRY_DELAY:-5}"
PREFLIGHT_DOCKER_RECLAIM_THRESHOLD_GB="${PREFLIGHT_DOCKER_RECLAIM_THRESHOLD_GB:-10}"
PREFLIGHT_RAM_MIN_FREE_MB="${PREFLIGHT_RAM_MIN_FREE_MB:-500}"
PREFLIGHT_TIME_SKEW_THRESHOLD_S="${PREFLIGHT_TIME_SKEW_THRESHOLD_S:-0.5}"

WARN_COUNT=0
FATAL_COUNT=0
REPORT_FILE="${REPORT_FILE:-}"

# === HELPERS ===

# append_finding NAME STATUS METRIC ACTUAL THRESHOLD
# Mutates $REPORT_FILE (JSON array) and increments WARN_COUNT/FATAL_COUNT.
append_finding() {
    local name="$1" status="$2" metric="$3" actual="$4" threshold="$5"
    local tmp
    tmp="$(mktemp)"
    jq --arg n "$name" --arg s "$status" --arg m "$metric" \
       --arg a "$actual" --arg t "$threshold" \
       '. + [{name:$n, status:$s, metric:$m, actual:$a, threshold:$t}]' \
       "$REPORT_FILE" > "$tmp" && mv "$tmp" "$REPORT_FILE"
    case "$status" in
        warning) WARN_COUNT=$((WARN_COUNT+1)) ;;
        fatal)   FATAL_COUNT=$((FATAL_COUNT+1)) ;;
    esac
}

# nproc shim — Linux nproc / macOS sysctl / POSIX getconf
preflight_nproc() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu 2>/dev/null || echo 1
    elif command -v getconf >/dev/null 2>&1; then
        getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1
    else
        echo 1
    fi
}

# === CHECK FUNCTIONS ===

check_disk() {
    local paths host_upper override_var min_gb
    host_upper="$(echo "${PREFLIGHT_TARGET_HOST:-}" | tr 'a-z-' 'A-Z_')"
    override_var="PREFLIGHT_${host_upper}_MIN_FREE_DISK_GB"
    min_gb="$PREFLIGHT_MIN_FREE_DISK_GB"
    if [[ -n "${!override_var:-}" ]]; then
        min_gb="${!override_var}"
    fi

    # df -P -k may be mocked (tests) — emits all rows regardless of args.
    paths=$PREFLIGHT_DISK_PATHS
    local df_out
    # shellcheck disable=SC2086 # paths intentionally word-split (multi-path arg)
    df_out="$(df -P -k $paths 2>/dev/null || true)"
    if [[ -z "$df_out" ]]; then
        append_finding "disk" "warning" "df_unavailable" "no_output" "stable"
        return 0
    fi

    local path
    for path in $paths; do
        local row used_pct avail_kb avail_gb pct_num
        row="$(echo "$df_out" | awk -v p="$path" '$NF == p {print}' | head -1)"
        if [[ -z "$row" ]]; then
            continue  # mountpoint absent on host (e.g. /var/lib/docker on dev)
        fi
        avail_kb="$(echo "$row" | awk '{print $4}')"
        used_pct="$(echo "$row" | awk '{print $5}')"
        pct_num="${used_pct%%%}"
        avail_gb="$(awk -v k="$avail_kb" 'BEGIN {printf "%.2f", k/1024/1024}')"

        if (( pct_num >= PREFLIGHT_DISK_FAIL_PERCENT )); then
            append_finding "disk" "fatal" "used_pct" "$pct_num" "$PREFLIGHT_DISK_FAIL_PERCENT"
        elif (( pct_num >= PREFLIGHT_DISK_WARN_PERCENT )); then
            append_finding "disk" "warning" "used_pct" "$pct_num" "$PREFLIGHT_DISK_WARN_PERCENT"
        else
            append_finding "disk" "ok" "used_pct" "$pct_num" "$PREFLIGHT_DISK_WARN_PERCENT"
        fi

        if awk -v g="$avail_gb" -v t="$min_gb" 'BEGIN {exit !(g < t)}'; then
            append_finding "disk" "fatal" "free_gb" "$avail_gb" "$min_gb"
        fi
    done
}

check_tailscale() {
    local out
    out="$(tailscale status --json 2>/dev/null || true)"
    if [[ -z "$out" ]]; then
        append_finding "tailscale" "fatal" "cli_unavailable" "no_output" "running"
        return 0
    fi
    local backend online
    backend="$(echo "$out" | jq -r '.BackendState // "unknown"')"
    online="$(echo "$out"  | jq -r '.Self.Online | if type=="boolean" then tostring else "false" end')"
    if [[ "$backend" == "Running" && "$online" == "true" ]]; then
        append_finding "tailscale" "ok" "backend_state" "$backend" "Running"
    else
        append_finding "tailscale" "fatal" "backend_state" "$backend/$online" "Running/true"
    fi
}

check_vault() {
    local attempt out initialized sealed
    for ((attempt=1; attempt<=PREFLIGHT_VAULT_RETRIES; attempt++)); do
        out="$(vault status -format=json 2>/dev/null || true)"
        if [[ -n "$out" ]]; then
            # NB: `// false` collapses {sealed:false} to default — must guard on type.
            initialized="$(echo "$out" | jq -r '.initialized | if type=="boolean" then tostring else "false" end')"
            sealed="$(echo "$out"      | jq -r '.sealed      | if type=="boolean" then tostring else "true"  end')"
            if [[ "$initialized" == "true" && "$sealed" == "false" ]]; then
                append_finding "vault" "ok" "sealed" "false" "false"
                return 0
            fi
        fi
        if (( attempt < PREFLIGHT_VAULT_RETRIES )); then
            sleep "$PREFLIGHT_VAULT_RETRY_DELAY" 2>/dev/null || true
        fi
    done
    append_finding "vault" "fatal" "sealed" "${sealed:-unknown}" "false"
}

check_docker_pressure() {
    local out reclaim_bytes reclaim_gb
    out="$(docker system df --format json 2>/dev/null || true)"
    if [[ -z "$out" ]]; then
        append_finding "docker_pressure" "warning" "cli_unavailable" "no_output" "stable"
        return 0
    fi
    reclaim_bytes="$(echo "$out" | jq -r '
        [.Images.ReclaimableBytes, .Containers.ReclaimableBytes,
         .Volumes.ReclaimableBytes, .BuildCache.ReclaimableBytes]
        | map(. // 0) | add')"
    reclaim_gb="$(awk -v b="$reclaim_bytes" 'BEGIN {printf "%.2f", b/1024/1024/1024}')"
    if awk -v g="$reclaim_gb" -v t="$PREFLIGHT_DOCKER_RECLAIM_THRESHOLD_GB" \
        'BEGIN {exit !(g > t)}'; then
        append_finding "docker_pressure" "warning" "reclaimable_gb" "$reclaim_gb" "$PREFLIGHT_DOCKER_RECLAIM_THRESHOLD_GB"
    else
        append_finding "docker_pressure" "ok" "reclaimable_gb" "$reclaim_gb" "$PREFLIGHT_DOCKER_RECLAIM_THRESHOLD_GB"
    fi
}

check_ram_swap() {
    local out free_mb
    out="$(free -m 2>/dev/null || true)"
    if [[ -z "$out" ]]; then
        append_finding "ram_swap" "warning" "cli_unavailable" "no_output" "stable"
        return 0
    fi
    free_mb="$(echo "$out" | awk '/^Mem:/ {print $4}')"
    if [[ -z "$free_mb" ]]; then
        append_finding "ram_swap" "warning" "parse_failed" "no_match" "Mem: line"
        return 0
    fi
    if (( free_mb < PREFLIGHT_RAM_MIN_FREE_MB )); then
        append_finding "ram_swap" "fatal" "free_mb" "$free_mb" "$PREFLIGHT_RAM_MIN_FREE_MB"
    else
        append_finding "ram_swap" "ok" "free_mb" "$free_mb" "$PREFLIGHT_RAM_MIN_FREE_MB"
    fi
}

check_loadavg() {
    local out load5 cores
    out="$(uptime 2>/dev/null || true)"
    if [[ -z "$out" ]]; then
        append_finding "loadavg" "warning" "uptime_unavailable" "no_output" "stable"
        return 0
    fi
    load5="$(echo "$out" | sed -E 's/.*load averages?: *([0-9.]+),? +([0-9.]+),? +([0-9.]+).*/\2/')"
    if [[ -z "$load5" || "$load5" == "$out" ]]; then
        append_finding "loadavg" "warning" "parse_failed" "no_match" "load average"
        return 0
    fi
    cores="$(preflight_nproc)"
    local warn_th fail_th
    warn_th="$(awk -v c="$cores" 'BEGIN {printf "%.2f", c*1.0}')"
    fail_th="$(awk -v c="$cores" 'BEGIN {printf "%.2f", c*2.0}')"
    if awk -v l="$load5" -v t="$fail_th" 'BEGIN {exit !(l > t)}'; then
        append_finding "loadavg" "fatal" "load5" "$load5" "$fail_th"
    elif awk -v l="$load5" -v t="$warn_th" 'BEGIN {exit !(l > t)}'; then
        append_finding "loadavg" "warning" "load5" "$load5" "$warn_th"
    else
        append_finding "loadavg" "ok" "load5" "$load5" "$warn_th"
    fi
}

check_time_skew() {
    local out offset abs_offset
    out="$(chronyc tracking 2>/dev/null || true)"
    if [[ -z "$out" ]]; then
        append_finding "time_skew" "warning" "chrony_unavailable" "no_output" "stable"
        return 0
    fi
    offset="$(echo "$out" | awk '/^System time/ {print $4}')"
    if [[ -z "$offset" ]]; then
        append_finding "time_skew" "warning" "parse_failed" "no_match" "System time line"
        return 0
    fi
    abs_offset="$(awk -v o="$offset" 'BEGIN {if (o<0) o=-o; printf "%.6f", o}')"
    if awk -v a="$abs_offset" -v t="$PREFLIGHT_TIME_SKEW_THRESHOLD_S" \
        'BEGIN {exit !(a > t)}'; then
        append_finding "time_skew" "warning" "offset_seconds" "$abs_offset" "$PREFLIGHT_TIME_SKEW_THRESHOLD_S"
    else
        append_finding "time_skew" "ok" "offset_seconds" "$abs_offset" "$PREFLIGHT_TIME_SKEW_THRESHOLD_S"
    fi
}

check_health_pre_probe() {
    local url="${PREFLIGHT_HEALTH_URL:-}"
    if [[ -z "$url" ]]; then
        append_finding "health_pre_probe" "ok" "url" "unset" "skipped"
        return 0
    fi
    local body status_field snapshot
    snapshot="$(mktemp -t preflight-health-XXXXXX.json)"
    if ! body="$(curl -fsS --max-time 5 "$url" 2>/dev/null)"; then
        append_finding "health_pre_probe" "warning" "curl_status" "non_zero" "ok"
        return 0
    fi
    echo "$body" > "$snapshot"
    status_field="$(echo "$body" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")"
    if [[ "$status_field" == "ok" ]]; then
        append_finding "health_pre_probe" "ok" "status" "$status_field" "ok"
    else
        append_finding "health_pre_probe" "warning" "status" "$status_field" "ok"
    fi
}

# === OPS BOT EMIT (canonical DTO per CI-Runners.md §3.1) ===

emit_ops_bot() {
    local status="$1" report="$2"
    local key="${OPSBOT_KEY:-}"
    if [[ -z "$key" ]]; then
        echo "WARN: OPSBOT_KEY unset; skipping Ops Bot emit (fail-soft)" >&2
        return 0
    fi
    local category dedup_bucket payload status_upper body_text
    case "$status" in
        warn) category="warning" ;;
        fail) category="fatal"   ;;
        *)    category="info"    ;;
    esac
    status_upper="$(echo "$status" | tr '[:lower:]' '[:upper:]')"
    dedup_bucket="$(date -u +%Y%m%d-%H 2>/dev/null || echo "0")"
    body_text="$(jq -r '.[] | "\(.name): \(.status) (\(.actual) vs \(.threshold))"' \
                 "$report" | head -10 | tr '\n' '|' )"
    payload="$(jq -cn \
        --arg agent     "preflight-check" \
        --arg title     "Pre-deploy preflight: ${PREFLIGHT_SERVICE_NAME} on ${PREFLIGHT_TARGET_HOST} [${status_upper}]" \
        --arg body      "$body_text" \
        --arg category  "$category" \
        --arg dedup     "preflight-${PREFLIGHT_TARGET_HOST}-${PREFLIGHT_SERVICE_NAME}-${dedup_bucket}" \
        --arg host      "${PREFLIGHT_TARGET_HOST}" \
        --arg service   "${PREFLIGHT_SERVICE_NAME}" \
        --arg audit     "${PREFLIGHT_RUN_URL}" \
        --slurpfile checks "$report" \
        '{agent:$agent, title:$title, body:$body, category:$category,
          dedup_key:$dedup,
          meta:{host:$host, service:$service, audit_ref:$audit, checks:$checks[0]}}')"
    # NB: never `set -x` around this curl; OPSBOT_KEY would leak.
    if ! curl -fsS -X POST "$PREFLIGHT_OPS_BOT_URL" \
        -H "Authorization: Bearer ${key}" \
        -H "Content-Type: application/json" \
        --max-time 10 \
        -d "$payload" >/dev/null 2>&1; then
        echo "WARN: Ops Bot emit failed (network/auth); not blocking deploy" >&2
    fi
}

# === MAIN ===

preflight_main() {
    set -e

    : "${PREFLIGHT_TARGET_HOST:?required}"
    : "${PREFLIGHT_SERVICE_NAME:?required}"

    if [[ ! "$PREFLIGHT_TARGET_HOST" =~ ^[a-z0-9-]+$ ]]; then
        echo "ERR: invalid target-host (must match [a-z0-9-]+): $PREFLIGHT_TARGET_HOST" >&2
        exit 3
    fi
    if [[ ! "$PREFLIGHT_SERVICE_NAME" =~ ^[a-z0-9-]+$ ]]; then
        echo "ERR: invalid service-name (must match [a-z0-9-]+): $PREFLIGHT_SERVICE_NAME" >&2
        exit 3
    fi

    REPORT_FILE="$(mktemp -t preflight-XXXXXX.json)"
    echo "[]" > "$REPORT_FILE"

    check_disk

    local c
    while IFS= read -r c; do
        c="${c// /}"
        [[ -z "$c" ]] && continue
        case "$c" in
            docker-pressure)  check_docker_pressure ;;
            ram-swap)         check_ram_swap ;;
            loadavg)          check_loadavg ;;
            vault)            check_vault ;;
            tailscale)        check_tailscale ;;
            time-skew)        check_time_skew ;;
            health-pre-probe) check_health_pre_probe ;;
            *) echo "WARN: unknown extra-check: $c" >&2 ;;
        esac
    done <<< "$PREFLIGHT_EXTRA_CHECKS"

    local status="ok"
    [[ $WARN_COUNT  -gt 0 ]] && status="warn"
    [[ $FATAL_COUNT -gt 0 ]] && status="fail"

    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        {
            echo "status=$status"
            echo "report-path=$REPORT_FILE"
            echo "warnings=$WARN_COUNT"
            echo "failures=$FATAL_COUNT"
        } >> "$GITHUB_OUTPUT"
    fi

    if [[ "$PREFLIGHT_OPS_BOT_EMIT" == "true" && "$status" != "ok" ]]; then
        emit_ops_bot "$status" "$REPORT_FILE"
    fi

    [[ "$status" == "fail" ]] && exit 2
    exit 0
}

if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    preflight_main "$@"
fi
