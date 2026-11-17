#!/usr/bin/env bash
# Bootstrap an ubuntu container job so customer-delivery root probes work:
# passwordless sudo (required by assert_wrapper_sigchld_normalization) plus the
# system Python/OpenSSL fixtures the trusted launcher pins.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  ca-certificates \
  curl \
  file \
  binutils \
  git \
  jq \
  openssl \
  python3 \
  python3-venv \
  python3-pip \
  shellcheck \
  sudo
# Root in the container must be able to `sudo -n` for the wrapper root probe.
if ! sudo -n /usr/bin/true 2>/dev/null; then
  printf 'ci-runner ALL=(ALL) NOPASSWD:ALL\n' >/etc/sudoers.d/ci-nopasswd
  printf 'root ALL=(ALL) NOPASSWD:ALL\n' >>/etc/sudoers.d/ci-nopasswd
  chmod 440 /etc/sudoers.d/ci-nopasswd
fi
sudo -n /usr/bin/true
/usr/bin/python3 --version
openssl version
