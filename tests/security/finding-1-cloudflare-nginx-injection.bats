#!/usr/bin/env bats
# Origin: corporate audit 2026-04-28, Finding 1
# Severity: HIGH (remote command injection as root via DOMAIN/WEBROOT in SSH cmd)
# Source: templates/cloudflare-nginx-setup.sh (pre-fix: ${DOMAIN}/${WEBROOT}
#         interpolated into ssh "<remote-cmd>" without input validation).

setup() {
  REPO_ROOT="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  TEMPLATE="$REPO_ROOT/templates/cloudflare-nginx-setup.sh"
  TMPDIR_TEST="$(mktemp -d)"
  export PATH="$TMPDIR_TEST/bin:$PATH"
  mkdir -p "$TMPDIR_TEST/bin"

  # Mock ssh / scp / curl / openssl — capture invocations, never reach network.
  for cmd in ssh scp curl openssl; do
    upper="$(printf '%s' "$cmd" | tr 'a-z' 'A-Z')"
    {
      printf '#!/usr/bin/env bash\n'
      printf 'echo "MOCK_%s_INVOKED" >> "%s/calls.log"\n' "$upper" "$TMPDIR_TEST"
      printf 'printf "%%s\\n" "$@" >> "%s/calls.log"\n' "$TMPDIR_TEST"
      printf 'exit 0\n'
    } > "$TMPDIR_TEST/bin/$cmd"
    chmod +x "$TMPDIR_TEST/bin/$cmd"
  done

  export CF_TOKEN="mock-token"
  export CF_ZONE="mock-zone"
  export SERVER="mock-server.invalid"
  export SSH_KEY="$TMPDIR_TEST/mock-key"
  : > "$SSH_KEY"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
  rm -f /tmp/pwned-fnd1
}

# Helper: assert script aborted with non-zero exit AND made no outbound calls
# (curl / ssh / scp / openssl). Validation must reject before any side effect.
assert_blocked_before_calls() {
  [ "$status" -ne 0 ]
  if [ -f "$TMPDIR_TEST/calls.log" ]; then
    ! grep -q '^MOCK_' "$TMPDIR_TEST/calls.log"
  fi
}

# NOTE: 3rd positional argument is WEBROOT_NAME (a directory _name_ under
# /var/www/, not an absolute path). Strict regex blocks slashes and shell
# metacharacters at the validation gate.

@test "Finding 1: rejects domain with command substitution \$()" {
  run bash "$TEMPLATE" 'foo.com$(touch /tmp/pwned-fnd1)' 49.13.52.208 foo
  assert_blocked_before_calls
  [ ! -f /tmp/pwned-fnd1 ]
}

@test "Finding 1: rejects domain with semicolon" {
  run bash "$TEMPLATE" 'foo.com;rm -rf /' 49.13.52.208 foo
  assert_blocked_before_calls
}

@test "Finding 1: rejects domain with backticks" {
  run bash "$TEMPLATE" 'foo.com`whoami`' 49.13.52.208 foo
  assert_blocked_before_calls
}

@test "Finding 1: rejects domain with pipe" {
  run bash "$TEMPLATE" 'foo.com|cat /etc/passwd' 49.13.52.208 foo
  assert_blocked_before_calls
}

@test "Finding 1: rejects domain with space" {
  run bash "$TEMPLATE" 'foo.com bar' 49.13.52.208 foo
  assert_blocked_before_calls
}

@test "Finding 1: rejects server_ip with shell metacharacters" {
  run bash "$TEMPLATE" foo.example.com '49.13.52.208;rm -rf /' foo
  assert_blocked_before_calls
}

@test "Finding 1: rejects webroot_name with path traversal" {
  run bash "$TEMPLATE" foo.example.com 49.13.52.208 '../../etc'
  assert_blocked_before_calls
}

@test "Finding 1: rejects webroot_name with shell metacharacters" {
  run bash "$TEMPLATE" foo.example.com 49.13.52.208 'foo;rm -rf /'
  assert_blocked_before_calls
}

@test "Finding 1: accepts valid domain + ip + webroot_name (passes validation gate)" {
  run bash "$TEMPLATE" foo.example.com 49.13.52.208 foo
  [ -f "$TMPDIR_TEST/calls.log" ]
  grep -q '^MOCK_' "$TMPDIR_TEST/calls.log"
}
