#!/usr/bin/env bats
# tune-0133-legacy-hardware-probe-checklist.bats — TUNE-0133 regression.
#
# Class A evolution proposal from reflection-INFRA-0073 (approved 2026-05-08):
# a 7-step probe checklist for legacy embedded Linux integrations, run before
# committing to an architectural approach in /dr-plan.

TEMPLATE="$BATS_TEST_DIRNAME/../templates/legacy-hardware-probe-checklist.md"
GATE="$BATS_TEST_DIRNAME/../scripts/stack-agnostic-gate.sh"

@test "T1 template file exists" {
    [ -f "$TEMPLATE" ]
}

@test "T2 all 7 probe steps present in order" {
    local s1 s2 s3 s4 s5 s6 s7
    s1=$(grep -n '^## Step 1 —' "$TEMPLATE" | cut -d: -f1)
    s2=$(grep -n '^## Step 2 —' "$TEMPLATE" | cut -d: -f1)
    s3=$(grep -n '^## Step 3 —' "$TEMPLATE" | cut -d: -f1)
    s4=$(grep -n '^## Step 4 —' "$TEMPLATE" | cut -d: -f1)
    s5=$(grep -n '^## Step 5 —' "$TEMPLATE" | cut -d: -f1)
    s6=$(grep -n '^## Step 6 —' "$TEMPLATE" | cut -d: -f1)
    s7=$(grep -n '^## Step 7 —' "$TEMPLATE" | cut -d: -f1)
    [ -n "$s1" ] && [ -n "$s2" ] && [ -n "$s3" ] && [ -n "$s4" ] && [ -n "$s5" ] && [ -n "$s6" ] && [ -n "$s7" ]
    [ "$s1" -lt "$s2" ] && [ "$s2" -lt "$s3" ] && [ "$s3" -lt "$s4" ] && [ "$s4" -lt "$s5" ] && [ "$s5" -lt "$s6" ] && [ "$s6" -lt "$s7" ]
}

@test "T3 covers the 7 probe domains named in the backlog spec" {
    grep -qi 'uname' "$TEMPLATE"
    grep -q '/dev/net/tun' "$TEMPLATE"
    grep -qi 'free -m' "$TEMPLATE"
    grep -qi 'pbkdf2' "$TEMPLATE"
    grep -qi 'busybox' "$TEMPLATE"
    grep -q '/var/spool/cron' "$TEMPLATE"
    grep -qi 'serial' "$TEMPLATE"
    grep -qi 'MAC' "$TEMPLATE"
}

@test "T4 stack-agnostic gate passes on the template" {
    [ -x "$GATE" ]
    run "$GATE" "$TEMPLATE"
    [ "$status" -eq 0 ]
}

@test "T5 reporting template block present" {
    grep -q '### Legacy Hardware Probe' "$TEMPLATE"
}
