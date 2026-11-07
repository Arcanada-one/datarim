#!/usr/bin/env bats
# Origin: corporate audit 2026-04-28, Finding 1
# Severity: HIGH (remote command injection as root via DOMAIN/WEBROOT in SSH cmd)
# Source: templates/cloudflare-nginx-setup.sh (pre-fix: ${DOMAIN}/${WEBROOT}
#         interpolated into ssh "<remote-cmd>" without input validation).

setup() {
  REPO_ROOT="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  TEMPLATE="$REPO_ROOT/templates/cloudflare-nginx-setup.sh"
  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
  export PATH="$TMPDIR_TEST/bin:$PATH"
  mkdir -p "$TMPDIR_TEST/bin"
  CANARY_DIR="$(mktemp -d "$TMPDIR_TEST/canary.XXXXXX")"
  CANARY="$CANARY_DIR/pwned"

  # Mock every external request boundary, including the embedded urllib call.
  # Capture invocations so the positive case proves validation admitted input
  # while no network-capable implementation was reached.
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
  cat > "$TMPDIR_TEST/bin/python3" <<'MOCK'
#!/usr/bin/env bash
printf 'MOCK_PYTHON3_INVOKED\n' >> "$TMPDIR_TEST/calls.log"
cat >/dev/null
printf 'CERT_OK\n'
MOCK
  chmod +x "$TMPDIR_TEST/bin/python3"

  export CF_TOKEN="mock-token"
  export CF_ZONE="mock-zone"
  export SERVER="mock-server.invalid"
  export SSH_KEY="$TMPDIR_TEST/mock-key"
  : > "$SSH_KEY"
}

teardown() {
  rm -rf -- "$TMPDIR_TEST"
}

# Helper: assert script aborted with non-zero exit AND reached no mocked
# outbound-request boundary. Validation must reject before any side effect.
assert_blocked_before_calls() {
  [ "$status" -ne 0 ] || return 1
  if [ -f "$TMPDIR_TEST/calls.log" ]; then
    ! grep -q '^MOCK_' "$TMPDIR_TEST/calls.log" || return 1
  fi
}

# NOTE: 3rd positional argument is WEBROOT_NAME (a directory _name_ under
# /var/www/, not an absolute path). Strict regex blocks slashes and shell
# metacharacters at the validation gate.

@test "Finding 1: rejects domain with command substitution \$()" {
  local payload="foo.com\$(touch \"$CANARY\")"
  run bash "$TEMPLATE" "$payload" 203.0.113.10 foo
  assert_blocked_before_calls || return 1
  [ ! -e "$CANARY" ] || return 1
}

@test "Finding 1: rejects domain with semicolon" {
  run bash "$TEMPLATE" 'foo.com;rm -rf /' 203.0.113.10 foo
  assert_blocked_before_calls || return 1
}

@test "Finding 1: rejects domain with backticks" {
  run bash "$TEMPLATE" 'foo.com`whoami`' 203.0.113.10 foo
  assert_blocked_before_calls || return 1
}

@test "Finding 1: rejects domain with pipe" {
  run bash "$TEMPLATE" 'foo.com|cat /etc/passwd' 203.0.113.10 foo
  assert_blocked_before_calls || return 1
}

@test "Finding 1: rejects domain with space" {
  run bash "$TEMPLATE" 'foo.com bar' 203.0.113.10 foo
  assert_blocked_before_calls || return 1
}

@test "Finding 1: rejects server_ip with shell metacharacters" {
  run bash "$TEMPLATE" foo.example.com '203.0.113.10;rm -rf /' foo
  assert_blocked_before_calls || return 1
}

@test "Finding 1: rejects webroot_name with path traversal" {
  run bash "$TEMPLATE" foo.example.com 203.0.113.10 '../../etc'
  assert_blocked_before_calls || return 1
}

@test "Finding 1: rejects webroot_name with shell metacharacters" {
  run bash "$TEMPLATE" foo.example.com 203.0.113.10 'foo;rm -rf /'
  assert_blocked_before_calls || return 1
}

@test "Finding 1: accepts valid domain + ip + webroot_name (passes validation gate)" {
  run bash "$TEMPLATE" foo.example.com 203.0.113.10 foo
  [ "$status" -eq 0 ] || return 1
  [ -f "$TMPDIR_TEST/calls.log" ] || return 1
  for boundary in CURL OPENSSL PYTHON3 SCP SSH; do
    grep -q "^MOCK_${boundary}_INVOKED$" "$TMPDIR_TEST/calls.log" || return 1
  done
}
