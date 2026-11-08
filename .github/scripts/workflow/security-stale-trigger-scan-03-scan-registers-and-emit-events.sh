#!/usr/bin/env bash
set -euo pipefail
set -uo pipefail
if [ -z "${REPOS:-}" ]; then
  echo "::warning::no target repos configured (set SECURITY_POLICY_REPOS org var or pass target_repos input)"
  exit 0
fi
if [ -z "${OPS_BOT_API_KEY:-}" ]; then
  echo "::warning::OPS_BOT_API_KEY not set — running in dry-run mode"
fi
today_epoch=$(date -u +%s)
day=$((24 * 3600))
for repo in $REPOS; do
  yml_url="https://raw.githubusercontent.com/${repo}/main/accepted-risk.yml"
  tmp="$(mktemp)"
  http_code=$(curl -sS -o "$tmp" -w '%{http_code}' "$yml_url" || echo "000")
  if [ "$http_code" != "200" ]; then
    echo "::warning::${repo}: accepted-risk.yml not reachable (HTTP $http_code) — skipping"
    rm -f "$tmp"
    continue
  fi
  count=$(yq '.entries | length' "$tmp" 2>/dev/null || echo 0)
  for i in $(seq 0 $((count - 1))); do
    re_review=$(yq -r ".entries[$i].re_review" "$tmp")
    id=$(yq -r ".entries[$i].id" "$tmp")
    pkg=$(yq -r ".entries[$i].pkg" "$tmp")
    re_epoch=$(date -u -d "$re_review" +%s 2>/dev/null || echo 0)
    if [ "$re_epoch" -eq 0 ]; then
      continue
    fi
    if [ "$re_epoch" -gt "$today_epoch" ]; then
      continue
    fi
    overdue_days=$(( (today_epoch - re_epoch) / day ))
    category="warning"
    if [ "$overdue_days" -ge 30 ]; then
      category="fatal"
    fi
    dedup_key="security-stale:${repo}:${id}"
    payload=$(jq -nc \
      --arg repo "$repo" \
      --arg id "$id" \
      --arg pkg "$pkg" \
      --arg re_review "$re_review" \
      --argjson overdue "$overdue_days" \
      --arg category "$category" \
      --arg dedup "$dedup_key" \
      '{category: $category, agent: "security-stale-trigger", dedup_key: $dedup, body: ("accepted-risk entry overdue: " + $repo + " " + $id + " (" + $pkg + "), re_review=" + $re_review + ", overdue=" + ($overdue|tostring) + "d")}')
    if [ -z "${OPS_BOT_API_KEY:-}" ]; then
      echo "DRY-RUN: $payload"
      continue
    fi
    http=$(curl -sS -o /dev/null -w '%{http_code}' \
      -X POST "$OPS_BOT_ENDPOINT" \
      -H "Authorization: Bearer $OPS_BOT_API_KEY" \
      -H 'Content-Type: application/json' \
      -d "$payload" || echo "000")
    if [ "$http" != "200" ] && [ "$http" != "201" ] && [ "$http" != "202" ]; then
      echo "::warning::Ops Bot POST failed for $dedup_key (HTTP $http)"
    fi
  done
  rm -f "$tmp"
done
exit 0
