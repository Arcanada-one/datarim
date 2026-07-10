#!/usr/bin/env bash
# INFRA-0202: weekly currency audit for the `preflight-check` SHA-bridge.
#
# During the transitional window before `Arcanada-one/datarim` PR #8 merged
# and tag `v1` was pushed, ecosystem consumer workflows pinned
# `preflight-check@<baked-SHA>` (PR #8 head) instead of the semantic `@v1`
# tag (INFRA-0122, preflight-mandate.md § clause 8). This script:
#
#   1. Resolves the current probe target — PR #8 head SHA while open,
#      `main` HEAD SHA once merged (state-machine, re-anchors on
#      open -> closed transition).
#   2. Greps the configured consumer files for the baked SHA and flags
#      drift against the probe target.
#   3. Runs the OP-3 decommission clock: first HTTP 200 from
#      `git/refs/tags/v1` starts a 7-day retirement window; once elapsed,
#      emits FATAL until the baked SHA is fully removed from the consumer
#      files, then writes a one-time "decommissioned" state and stops.
#
# Fail-soft: network/API errors emit a `::warning::` annotation and exit 0
# so the weekly cron does not page on its own pipeline outages. Requires
# GH_TOKEN (read:datarim) and, for live event emission, OPSBOT_API_KEY.
#
# State persistence: Vault KV path `arcanada/infra-0202/decommissioned`
# (falls back to a local file at $SHA_BRIDGE_STATE_FILE when no vault CLI /
# VAULT_ADDR is configured — e.g. local dry-runs) so the FATAL step does not
# repeat every week once the bridge is confirmed removed (anti-spam).

set -uo pipefail

BAKED_SHA="${BAKED_SHA:-4937a5ab622f125674871a87bcc88c9c7e1d4596}"
REPO="${REPO:-Arcanada-one/datarim}"
PR_NUMBER="${PR_NUMBER:-8}"
TAG_REF="${TAG_REF:-v1}"
RETIREMENT_WINDOW_DAYS="${RETIREMENT_WINDOW_DAYS:-7}"
OPS_BOT_ENDPOINT="${OPS_BOT_ENDPOINT:-https://ops.arcanada.one/events}"
OPS_BOT_API_KEY="${OPS_BOT_API_KEY:-}"
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
VAULT_STATE_PATH="${VAULT_STATE_PATH:-arcanada/infra-0202/decommissioned}"
SHA_BRIDGE_STATE_FILE="${SHA_BRIDGE_STATE_FILE:-}"
# space-separated "owner/repo:path" targets to grep for the baked SHA.
TARGET_FILES="${TARGET_FILES:-Arcanada-one/arcanada-workspace:CLAUDE.md Arcanada-one/arcanada-workspace:documentation/infrastructure/CI-Runners.md Arcanada-one/arcanada-workspace:documentation/mandates/preflight-mandate.md}"

gh_api() {
  local url="$1"
  local auth_header=()
  [ -n "$GH_TOKEN" ] && auth_header=(-H "Authorization: Bearer $GH_TOKEN")
  curl -sS -w '\n%{http_code}' "${auth_header[@]}" "$url"
}

# fetch_raw <raw.githubusercontent.com URL> <output file> — auth'd so
# private target repos (e.g. arcanada-workspace) resolve too.
fetch_raw() {
  local url="$1" out="$2"
  local auth_header=()
  [ -n "$GH_TOKEN" ] && auth_header=(-H "Authorization: Bearer $GH_TOKEN")
  curl -sS -o "$out" -w '%{http_code}' "${auth_header[@]}" "$url"
}

emit_event() {
  local category="$1" dedup_key="$2" body="$3"
  local payload
  payload=$(jq -nc \
    --arg category "$category" \
    --arg dedup "$dedup_key" \
    --arg body "$body" \
    '{category: $category, agent: "sha-bridge-audit", dedup_key: $dedup, body: $body}')
  if [ -z "$OPS_BOT_API_KEY" ]; then
    echo "DRY-RUN event: $payload"
    return 0
  fi
  local http
  http=$(curl -sS -o /dev/null -w '%{http_code}' \
    -X POST "$OPS_BOT_ENDPOINT" \
    -H "Authorization: Bearer $OPS_BOT_API_KEY" \
    -H 'Content-Type: application/json' \
    -d "$payload" || echo "000")
  if [ "$http" != "200" ] && [ "$http" != "201" ] && [ "$http" != "202" ]; then
    echo "::warning::Ops Bot POST failed for $dedup_key (HTTP $http)"
  fi
}

# state_get <field>  — field is "decommissioned_at" or "window_opened_at"
state_get() {
  local field="$1"
  if command -v vault >/dev/null 2>&1 && [ -n "${VAULT_ADDR:-}" ]; then
    vault kv get -field="$field" "$VAULT_STATE_PATH" 2>/dev/null || true
    return 0
  fi
  if [ -n "$SHA_BRIDGE_STATE_FILE" ] && [ -f "${SHA_BRIDGE_STATE_FILE}.${field}" ]; then
    cat "${SHA_BRIDGE_STATE_FILE}.${field}"
    return 0
  fi
  echo ""
}

# state_set <field> <iso-date>
state_set() {
  local field="$1" iso_date="$2"
  if command -v vault >/dev/null 2>&1 && [ -n "${VAULT_ADDR:-}" ]; then
    if vault kv patch "$VAULT_STATE_PATH" "${field}=${iso_date}" >/dev/null 2>&1 \
      || vault kv put "$VAULT_STATE_PATH" "${field}=${iso_date}" >/dev/null 2>&1; then
      return 0
    fi
    echo "::warning::failed writing Vault state ${VAULT_STATE_PATH}#${field}"
  fi
  if [ -n "$SHA_BRIDGE_STATE_FILE" ]; then
    echo "$iso_date" > "${SHA_BRIDGE_STATE_FILE}.${field}"
    return 0
  fi
  echo "::warning::no Vault and no SHA_BRIDGE_STATE_FILE configured — ${field} NOT persisted, next run will re-evaluate from scratch"
}

main() {
# --- 1. resolve probe target (PR-open vs PR-merged state machine) --------
pr_response=$(gh_api "https://api.github.com/repos/${REPO}/pulls/${PR_NUMBER}")
pr_http=$(echo "$pr_response" | tail -1)
pr_body=$(echo "$pr_response" | sed '$d')

if [ "$pr_http" != "200" ]; then
  echo "::warning::could not fetch PR #${PR_NUMBER} state (HTTP $pr_http) — skipping this run"
  return 0
fi

pr_state=$(echo "$pr_body" | jq -r '.state')
pr_merged=$(echo "$pr_body" | jq -r '.merged')

if [ "$pr_state" = "open" ]; then
  probe_target=$(echo "$pr_body" | jq -r '.head.sha')
  probe_source="pr-open:pulls/${PR_NUMBER}"
else
  main_response=$(gh_api "https://api.github.com/repos/${REPO}/commits/main")
  main_http=$(echo "$main_response" | tail -1)
  if [ "$main_http" != "200" ]; then
    echo "::warning::could not fetch main HEAD (HTTP $main_http) — skipping this run"
    return 0
  fi
  probe_target=$(echo "$main_response" | sed '$d' | jq -r '.sha')
  probe_source="pr-merged:commits/main"
fi

echo "probe target: $probe_target (source: $probe_source, PR merged=$pr_merged)"

# --- 2. grep target files for the baked SHA, flag drift ------------------
drift_found=0
for entry in $TARGET_FILES; do
  target_repo="${entry%%:*}"
  target_path="${entry#*:}"
  raw_url="https://raw.githubusercontent.com/${target_repo}/main/${target_path}"
  http_code=$(fetch_raw "$raw_url" /tmp/sha-bridge-target.txt || echo "000")
  if [ "$http_code" != "200" ]; then
    echo "::warning::${target_repo}:${target_path} not reachable (HTTP $http_code) — skipping"
    continue
  fi
  if grep -q "$BAKED_SHA" /tmp/sha-bridge-target.txt; then
    if [ "$BAKED_SHA" != "$probe_target" ]; then
      drift_found=1
      emit_event "warning" "sha-bridge-drift-${BAKED_SHA}-${probe_target}" \
        "SHA-bridge drift: ${target_repo}:${target_path} still pins @${BAKED_SHA} but current probe target (${probe_source}) is @${probe_target}"
    fi
  fi
done
rm -f /tmp/sha-bridge-target.txt

if [ "$drift_found" -eq 0 ]; then
  echo "no drift: baked SHA matches probe target, or baked SHA already fully removed from target files"
fi

# --- 3. OP-3 decommission clock -------------------------------------------
already_decommissioned=$(state_get "decommissioned_at")
if [ -n "$already_decommissioned" ]; then
  echo "already decommissioned at $already_decommissioned — skipping FATAL re-emit"
  return 0
fi

tag_response=$(gh_api "https://api.github.com/repos/${REPO}/git/refs/tags/${TAG_REF}")
tag_http=$(echo "$tag_response" | tail -1)

if [ "$tag_http" != "200" ]; then
  echo "OP-3 clock not started: tag ${TAG_REF} not yet published (HTTP $tag_http)"
  return 0
fi

tag_sha=$(echo "$tag_response" | sed '$d' | jq -r '.object.sha')
echo "OP-3 clock active: tag ${TAG_REF} resolves to ${tag_sha}"

# Any baked-SHA occurrence still present in target files after the tag
# exists means the retirement window is running or has elapsed.
any_reference_remains=0
for entry in $TARGET_FILES; do
  target_repo="${entry%%:*}"
  target_path="${entry#*:}"
  raw_url="https://raw.githubusercontent.com/${target_repo}/main/${target_path}"
  http_code=$(fetch_raw "$raw_url" /tmp/sha-bridge-target2.txt || echo "000")
  [ "$http_code" != "200" ] && continue
  grep -q "$BAKED_SHA" /tmp/sha-bridge-target2.txt && any_reference_remains=1
done
rm -f /tmp/sha-bridge-target2.txt

iso_now="${SHA_BRIDGE_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

if [ "$any_reference_remains" -eq 0 ]; then
  state_set "decommissioned_at" "$iso_now"
  emit_event "info" "sha-bridge-decommissioned-${tag_sha}" \
    "SHA-bridge fully decommissioned: no remaining @${BAKED_SHA} references in target files, tag ${TAG_REF}=${tag_sha} is live"
  return 0
fi

window_opened_at=$(state_get "window_opened_at")
if [ -z "$window_opened_at" ]; then
  window_opened_at="$iso_now"
  state_set "window_opened_at" "$window_opened_at"
  emit_event "warning" "sha-bridge-decommission-window-open-${tag_sha}" \
    "SHA-bridge decommission window open: tag ${TAG_REF}=${tag_sha} published, @${BAKED_SHA} references still present in target files, ${RETIREMENT_WINDOW_DAYS}-day retirement window started"
  return 0
fi

opened_epoch=$(date -u -d "$window_opened_at" +%s 2>/dev/null || echo 0)
now_epoch=$(date -u -d "$iso_now" +%s 2>/dev/null || echo 0)
if [ "$opened_epoch" -eq 0 ] || [ "$now_epoch" -eq 0 ]; then
  echo "::warning::could not parse window_opened_at=$window_opened_at — skipping escalation check this run"
  return 0
fi
elapsed_days=$(( (now_epoch - opened_epoch) / 86400 ))

if [ "$elapsed_days" -ge "$RETIREMENT_WINDOW_DAYS" ]; then
  emit_event "fatal" "sha-bridge-decommission-overdue-${tag_sha}" \
    "bridge stale-by-design — @${BAKED_SHA} still referenced ${elapsed_days}d after decommission window opened (${window_opened_at}, limit ${RETIREMENT_WINDOW_DAYS}d); remove from mandate + CI-Runners.md § 3.5"
  echo "::error::bridge stale-by-design — @${BAKED_SHA} still referenced ${elapsed_days}d after window-open, over the ${RETIREMENT_WINDOW_DAYS}-day limit"
else
  echo "decommission window running: ${elapsed_days}/${RETIREMENT_WINDOW_DAYS} days elapsed since ${window_opened_at}"
fi

return 0
}

# Run main only when executed, not when sourced (bats sources this file to
# unit-test gh_api/emit_event/state_get/state_set in isolation).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
