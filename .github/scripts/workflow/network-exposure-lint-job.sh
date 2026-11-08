#!/usr/bin/env bash
# network-exposure-lint reusable workflow body.
set -euo pipefail

DATARIM_REF="${DATARIM_REF:?datarim_ref required}"
COMPOSE_PATHS="${COMPOSE_PATHS:-docker-compose.yml}"
REDIS_PATHS="${REDIS_PATHS:-}"
POSTGRES_PATHS="${POSTGRES_PATHS:-}"
SYSTEMD_PATHS="${SYSTEMD_PATHS:-}"
STRICT="${STRICT:-true}"

[[ "$DATARIM_REF" =~ ^[0-9a-f]{40}$ ]] || {
  echo "datarim_ref must be an exact lowercase 40-hex commit" >&2
  exit 1
}

rm -rf .datarim
git clone https://github.com/Arcanada-one/datarim.git .datarim
git -C .datarim checkout --force "$DATARIM_REF"

yq_dir="${RUNNER_TEMP}/datarim-bin"
mkdir -p "$yq_dir"
wget -qO "${yq_dir}/yq" \
  https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64
printf '%s  %s\n' \
  'a2c097180dd884a8d50c956ee16a9cec070f30a7947cf4ebf87d5f36213e9ed7' \
  "${yq_dir}/yq" | sha256sum --check --strict
chmod 0755 "${yq_dir}/yq"
printf '%s\n' "$yq_dir" >>"$GITHUB_PATH"
export PATH="${yq_dir}:${PATH}"
yq --version

set -uo pipefail
args=()
# shellcheck disable=SC2086
for p in $COMPOSE_PATHS;  do [ -n "$p" ] && args+=(--compose "$p");        done
for p in $REDIS_PATHS;    do [ -n "$p" ] && args+=(--redis-conf "$p");     done
for p in $POSTGRES_PATHS; do [ -n "$p" ] && args+=(--postgres-conf "$p");  done
for p in $SYSTEMD_PATHS;  do [ -n "$p" ] && args+=(--systemd-socket "$p"); done
[ "$STRICT" = "false" ] && args+=(--no-strict)
./.datarim/dev-tools/network-exposure-check.sh "${args[@]}"
