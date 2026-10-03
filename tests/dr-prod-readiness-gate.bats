#!/usr/bin/env bats
# Tests for the two-stage prod-readiness gate (Vector A).
# Contract-presence tests over the shipped command surface (the gate lives in
# the command instruction bodies as a MUST step) plus a behavioural check of the
# read-only allow-list invariant.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    QA="$REPO_ROOT/commands/dr-qa.md"
    ARCHIVE="$REPO_ROOT/commands/dr-archive.md"
    SKILL="$REPO_ROOT/skills/prod-readiness-probe/SKILL.md"
}

@test "dr-qa carries Gate 4g Prod-Readiness layer" {
    grep -q '4g. Prod-Readiness Gate' "$QA"
}

@test "dr-qa Gate 4g triggers on deploy-class and blocks propose-merge on FAIL/BLOCKED" {
    grep -q 'check-deploy-class.sh' "$QA"
    grep -Eqi 'propose.merge|propose merge|merge' "$QA"
    grep -q 'prod-readiness-probe' "$QA"
}

@test "dr-archive carries Step 0.4 Prod-Merge Verification Gate" {
    # tolerate markdown bold around the title (**Prod-Merge Verification Gate**)
    grep -Eq '0\.4\..*Prod-Merge Verification Gate' "$ARCHIVE"
}

@test "dr-archive Step 0.4 blocks archive until prod-merge done+verified for deploy-class" {
    grep -q 'check-deploy-class.sh' "$ARCHIVE"
    grep -Eqi 'block.*archive|archive.*until|MUST NOT.*archive' "$ARCHIVE"
}

@test "probe skill defines the four verdicts" {
    for v in SKIP PASS FAIL BLOCKED; do
        grep -q "$v" "$SKILL"
    done
}

@test "probe skill prod hard-gate is read-only — no mutating commands in the allow-list" {
    # the allow-list section must NOT bless mutating systemctl verbs
    ! grep -Eq 'systemctl[[:space:]]+(start|stop|restart|enable|disable)' "$SKILL"
}

@test "probe skill BLOCKED never auto-resolves to PASS on unreachable" {
    grep -Eqi 'never auto.*PASS|BLOCKED never|silence is not success' "$SKILL"
}
