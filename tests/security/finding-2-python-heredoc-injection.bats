#!/usr/bin/env bats
# Origin: corporate audit 2026-04-28, Finding 2
# Severity: HIGH (Python code injection via unquoted heredoc terminator)
# Source: templates/cloudflare-nginx-setup.sh (pre-fix: <<PY without quotes;
#         ${DOMAIN} and ${CF_TOKEN} interpolated into Python source).
#
# This is a static-grep regression test guarding the P1.2 fix.

setup() {
  REPO_ROOT="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  TEMPLATE="$REPO_ROOT/templates/cloudflare-nginx-setup.sh"
}

@test "Finding 2: Python heredoc terminator is quoted (<<'PY')" {
  # Look at executable lines only (skip comment lines starting with '#'). Every
  # heredoc-open line must be <<'PY' (single-quoted terminator).
  unquoted="$(grep -nE "<<[[:space:]]*PY\b" "$TEMPLATE" \
              | grep -vE "^[[:space:]]*[0-9]+:#" \
              | grep -v "<<'PY'" || true)"
  [ -z "$unquoted" ]
}

@test "Finding 2: Python heredoc body reads from os.environ, not shell interpolation" {
  body="$(python3 - "$TEMPLATE" <<'PYEXTRACT'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"<<'PY'\n(.*?)\nPY\b", src, re.S)
sys.stdout.write(m.group(1) if m else '')
PYEXTRACT
)"
  [ -n "$body" ]
  # Must use os.environ
  echo "$body" | grep -qE "os\.environ\[['\"]DOMAIN['\"]\]"
  # Must NOT contain ${DOMAIN} / ${CF_TOKEN} / ${CF_API} interpolation
  ! echo "$body" | grep -qE '\$\{?(DOMAIN|CF_TOKEN|CF_API|TMP)\}?'
}
