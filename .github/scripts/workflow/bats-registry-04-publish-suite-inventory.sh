#!/usr/bin/env bash
set -euo pipefail
total=$(find . -type f -name '*.bats' ! -path './.git/*' | wc -l)
running=$(bash tests/run-bats-discovery.sh --list | wc -l)
managed=3
{
  echo "### bats inventory"
  echo
  echo "| metric | count |"
  echo "| --- | --- |"
  echo "| suites on disk | ${total} |"
  echo "| suites executed monolithically | ${running} |"
  echo "| suites executed by exact shards | ${managed} |"
  echo "| excluded (registry) | $(( total - running )) |"
} >> "$GITHUB_STEP_SUMMARY"
echo "on disk: ${total}, monolithic: ${running}, exact-sharded: ${managed}"
