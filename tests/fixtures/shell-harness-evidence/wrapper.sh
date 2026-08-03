#!/usr/bin/env bash
# Reference seam for testing a wrapper that transforms a child result into
# QA/compliance evidence. It deliberately distinguishes child failure from an
# expected-red assertion and from an invalid harness/setup failure.
set -u

if [ "$#" -eq 0 ]; then
    printf 'HARNESS_INVALID:no-child\n' >&2
    exit 65
fi

child_output=$("$@" 2>&1)
child_status=$?
printf '%s\n' "$child_output"

if [ -n "${EXPECTED_SENTINEL:-}" ]; then
    if [ "$child_status" -eq 0 ]; then
        printf 'HARNESS_INVALID:expected-red-child-passed\n' >&2
        exit 65
    fi

    case "$child_output" in
        "$EXPECTED_SENTINEL")
            printf 'EXPECTED_RED_CONFIRMED:%s\n' "$EXPECTED_SENTINEL"
            exit 0
            ;;
        *)
            printf 'HARNESS_INVALID:missing-sentinel:%s\n' "$EXPECTED_SENTINEL" >&2
            exit 65
            ;;
    esac
fi

if [ "$child_status" -ne 0 ]; then
    printf 'CHILD_FAILURE:%s\n' "$child_status" >&2
    exit "$child_status"
fi

printf 'HARNESS_PASS\n'
