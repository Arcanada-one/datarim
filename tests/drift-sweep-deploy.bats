#!/usr/bin/env bats
# drift-sweep-deploy.bats — invariants for the level-3 scheduler templates.
# These are static-file assertions (V-10 + crontab-doc presence).

DEPLOY="${BATS_TEST_DIRNAME}/../dev-tools/deploy"

@test "V-10a: timer template declares no Requires=" {
    run grep -q '^Requires=' "$DEPLOY/drift-sweep.timer"
    [ "$status" -ne 0 ]
}

@test "V-10b: service template declares no Requires=" {
    run grep -q '^Requires=' "$DEPLOY/drift-sweep.service"
    [ "$status" -ne 0 ]
}

@test "V-10c: timer binds the service via Unit= and installs to timers.target" {
    grep -q '^Unit=drift-sweep.service' "$DEPLOY/drift-sweep.timer"
    grep -q '^WantedBy=timers.target' "$DEPLOY/drift-sweep.timer"
}

@test "V-10d: service is oneshot" {
    grep -q '^Type=oneshot' "$DEPLOY/drift-sweep.service"
}

@test "deploy README documents the operator-installed crontab line" {
    grep -q 'check-site-drift-sweep.sh' "$DEPLOY/README.md"
    grep -qi 'crontab' "$DEPLOY/README.md"
}
