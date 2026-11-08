#!/usr/bin/env bash
set -euo pipefail
mapfile -d '' mds < <(find skills agents commands templates docs -name '*.md' -print0 2>/dev/null || true)
if [ "${#mds[@]}" -eq 0 ]; then
  echo "no markdown in shipped scopes"
  exit 0
fi
fail=0
for md in "${mds[@]}"; do
  awk '
    /^[[:space:]]*<!--[[:space:]]*security:counter-example[[:space:]]*-->[[:space:]]*$/ { skip=1; next }
    /^[[:space:]]*<!--[[:space:]]*\/security:counter-example[[:space:]]*-->[[:space:]]*$/ { skip=0; next }
    /^[[:space:]]*<!--[[:space:]]*security:rule-statement[[:space:]]*-->[[:space:]]*$/ { skip=1; next }
    /^[[:space:]]*<!--[[:space:]]*\/security:rule-statement[[:space:]]*-->[[:space:]]*$/ { skip=0; next }
    skip == 1 { next }
    /StrictHostKeyChecking=no/ { printf "%s:%d:[ssh-disable] %s\n", FILENAME, NR, $0; found=1 }
    /curl[[:space:]]+[^|]*\|[[:space:]]*bash([[:space:]]|$)/ { printf "%s:%d:[curl-bash] %s\n", FILENAME, NR, $0; found=1 }
    /curl[[:space:]]+[^|]*\|[[:space:]]*sh([[:space:]]|$)/ { printf "%s:%d:[curl-sh] %s\n", FILENAME, NR, $0; found=1 }
    /client_secret_[a-zA-Z0-9_-]{20,}/ { printf "%s:%d:[client-secret] %s\n", FILENAME, NR, $0; found=1 }
    END { exit (found ? 1 : 0) }
  ' "$md" || fail=1
done
if [ "$fail" -ne 0 ]; then
  echo "::error::anti-pattern(s) found in shipped markdown outside counter-example fences"
  exit 1
fi
echo "markdown-policy: clean"
