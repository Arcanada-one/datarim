#!/usr/bin/env bash
set -euo pipefail
: "${GROUP_MEMBERS:?GROUP_MEMBERS required}"
: "${RUNNER_TEMP:?RUNNER_TEMP required}"
: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE required}"

install_root_sudo_shim() {
  mkdir -p "$RUNNER_TEMP/bin"
  cat >"$RUNNER_TEMP/bin/sudo" <<'SH'
#!/bin/bash
set -euo pipefail
# Already uid 0 inside the pid-host helper. Strip sudo flags and exec.
while [ "$#" -gt 0 ]; do
  case "$1" in
    -n|-E|-H|-A)
      shift
      ;;
    -u|--user|-g|--group)
      shift
      [ "$#" -gt 0 ] || exit 2
      shift
      ;;
    --preserve-env|--preserve-env=*)
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      shift
      ;;
    *)
      break
      ;;
  esac
done
exec "$@"
SH
  chmod 0755 "$RUNNER_TEMP/bin/sudo"
  export PATH="$RUNNER_TEMP/bin:$PATH"
}

run_shard() {
  local result_dir="$RUNNER_TEMP/customer-delivery-result"
  mkdir -p "$result_dir"
  # Each logical shard keeps its own timeout and result JSON. A partial
  # failure still records siblings; the aggregate fails on any missing
  # required logical result.
  /usr/bin/python3 tests/run-customer-delivery-shard.py \
    --group-members "$GROUP_MEMBERS" \
    --python-bin "$RUNNER_TEMP/customer-delivery-venv/bin/python" \
    --platform linux \
    --result-dir "$result_dir"
}

# Re-entered as root via the pid-host docker helper below.
if [[ "${CUSTOMER_DELIVERY_ROOT_HELPER:-}" == 1 ]]; then
  install_root_sudo_shim
  run_shard
  exit 0
fi

if sudo -n /usr/bin/true 2>/dev/null; then
  run_shard
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: passwordless sudo unavailable and docker is not on PATH" >&2
  echo "       customer-delivery root probes need one of the two on self-hosted." >&2
  exit 1
fi

# Re-exec as root with the host PID namespace. A GHA `container:` job breaks
# descendant-cleanup tests and exhausts docker networks at matrix width 20;
# a one-shot `docker run --pid=host --network=host` avoids both.
exec docker run --rm \
  --pid=host \
  --network=host \
  --user 0:0 \
  -v "$GITHUB_WORKSPACE:$GITHUB_WORKSPACE" \
  -v "$RUNNER_TEMP:$RUNNER_TEMP" \
  -v /usr:/usr:ro \
  -v /bin:/bin:ro \
  -v /lib:/lib:ro \
  -v /lib64:/lib64:ro \
  -v /sbin:/sbin:ro \
  -w "$GITHUB_WORKSPACE" \
  -e GROUP_MEMBERS \
  -e RUNNER_TEMP \
  -e GITHUB_WORKSPACE \
  -e PATH \
  -e HOME="$RUNNER_TEMP" \
  -e CUSTOMER_DELIVERY_ROOT_HELPER=1 \
  ubuntu:24.04 \
  /bin/bash "$GITHUB_WORKSPACE/.github/scripts/workflow/bats-customer-delivery-linux-03-run-bounded-exact-shard.sh"
