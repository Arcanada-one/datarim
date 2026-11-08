#!/usr/bin/env bash
# Discover and run every tracked node:test suite (node-tests.yml body).
set -euo pipefail
files=()
while IFS= read -r -d '' file; do files+=("$file"); done \
  < <(git ls-files -z -- '*.test.mjs' '*.test.js' '*.test.cjs')
if [ "${#files[@]}" -eq 0 ]; then
  echo "::error::no node test files discovered; refusing an empty pass"
  exit 1
fi
printf 'discovered: %s\n' "${files[@]}"
tap="$RUNNER_TEMP/node-tests.tap"
node --test \
  --test-reporter=spec --test-reporter-destination=stdout \
  --test-reporter=tap --test-reporter-destination="$tap" \
  "${files[@]}"
grep -Eq '^# pass [1-9][0-9]*$' "$tap" || { echo "::error::no test passed"; exit 1; }
if [ "${IS_LINUX:-}" = "true" ] && ! grep -qx '# skipped 0' "$tap"; then
  echo "::error::tests were skipped on Linux; every suite must run here"
  grep -E '^# (tests|pass|skipped)' "$tap"
  exit 1
fi
grep -E '^# (tests|pass|fail|skipped)' "$tap"
