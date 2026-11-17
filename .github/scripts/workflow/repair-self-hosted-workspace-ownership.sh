#!/usr/bin/env bash
# Best-effort ownership repair for persistent self-hosted workspaces.
# A prior privileged helper can leave $GITHUB_WORKSPACE / $RUNNER_TEMP root-owned,
# which breaks actions/checkout and $RUNNER_TEMP installs for ci-runner.
# When docker is available, chown back to the job user; otherwise no-op.
set -euo pipefail
if ! command -v docker >/dev/null 2>&1; then
  exit 0
fi
uid="$(id -u)"
gid="$(id -g)"
ws="${GITHUB_WORKSPACE:-}"
rt="${RUNNER_TEMP:-}"
if [ -z "$ws" ] && [ -z "$rt" ]; then
  exit 0
fi
docker_args=(run --rm)
[ -n "$ws" ] && [ -d "$ws" ] && docker_args+=(-v "$ws:$ws")
[ -n "$rt" ] && [ -d "$rt" ] && docker_args+=(-v "$rt:$rt")
targets=()
[ -n "$ws" ] && [ -d "$ws" ] && targets+=("$ws")
[ -n "$rt" ] && [ -d "$rt" ] && targets+=("$rt")
[ "${#targets[@]}" -eq 0 ] && exit 0
# shellcheck disable=SC2086
docker "${docker_args[@]}" ubuntu:24.04 \
  chown -R "${uid}:${gid}" "${targets[@]}" >/dev/null 2>&1 || true
