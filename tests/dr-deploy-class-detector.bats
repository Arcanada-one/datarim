#!/usr/bin/env bats
# Tests for dev-tools/check-deploy-class.sh (deploy-class classifier — the gate trigger)
# and dev-tools/check-deploy-readiness.sh --validate-yaml (deploy-readiness.yml contract validator).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    DETECT="$REPO_ROOT/dev-tools/check-deploy-class.sh"
    VALIDATE="$REPO_ROOT/dev-tools/check-deploy-readiness.sh"
    TMP="$BATS_TEST_TMPDIR"
}

# ---- check-deploy-class.sh: classifier ----

@test "classifier: systemd unit file path => deploy-class (exit 0)" {
    cat > "$TMP/td.md" <<'EOF'
## Overview
Add _deploy/systemd/aio-worker.service and wire it via CI cutover.
EOF
    run bash "$DETECT" --task-description "$TMP/td.md"
    [ "$status" -eq 0 ]
}

@test "classifier: sudoers mention => deploy-class (exit 0)" {
    cat > "$TMP/td.md" <<'EOF'
## Overview
Update /etc/sudoers.d/app-deploy with NOPASSWD rules for the worker.
EOF
    run bash "$DETECT" --task-description "$TMP/td.md"
    [ "$status" -eq 0 ]
}

@test "classifier: .env-deploy mention => deploy-class (exit 0)" {
    cat > "$TMP/td.md" <<'EOF'
## Overview
Ship new defaults in .env-deploy template for the production rollout.
EOF
    run bash "$DETECT" --task-description "$TMP/td.md"
    [ "$status" -eq 0 ]
}

@test "classifier: pure docs task => NOT deploy-class (exit 1)" {
    cat > "$TMP/td.md" <<'EOF'
## Overview
Rewrite the getting-started guide for clarity. No deploy surface touched.
EOF
    run bash "$DETECT" --task-description "$TMP/td.md"
    [ "$status" -eq 1 ]
}

@test "classifier: missing file => usage error (exit 2)" {
    run bash "$DETECT" --task-description "$TMP/does-not-exist.md"
    [ "$status" -eq 2 ]
}

# ---- check-deploy-readiness.sh --validate-yaml: contract validator ----

write_valid_contract() {
    cat > "$1" <<'EOF'
schema_version: 1
runners:
  test:
    name: test
    ssh: ssh generic-test-runner.internal
    required_sudoers:
      - systemctl daemon-reload
      - systemctl restart <UNIT>
    units:
      - name: app-worker
        state: enabled
    ports:
      - port: 8080
        expect: bound
    versions:
      node: ">= 18.20.0"
  prod:
    name: prod
    ssh: ssh generic-prod-runner.internal
    required_sudoers:
      - systemctl daemon-reload
      - systemctl restart <UNIT>
    units:
      - name: app-worker
        state: enabled
    ports:
      - port: 8080
        expect: bound
    versions:
      node: ">= 18.20.0"
EOF
}

@test "validator: well-formed contract => exit 0" {
    write_valid_contract "$TMP/dr.yml"
    run bash "$VALIDATE" --validate-yaml "$TMP/dr.yml"
    [ "$status" -eq 0 ]
}

@test "validator: secret-bearing line => exit 1" {
    write_valid_contract "$TMP/dr.yml"
    printf '    password: hunter2\n' >> "$TMP/dr.yml"
    run bash "$VALIDATE" --validate-yaml "$TMP/dr.yml"
    [ "$status" -eq 1 ]
}

@test "validator: wrong runner cardinality (missing prod) => exit 1" {
    cat > "$TMP/dr.yml" <<'EOF'
schema_version: 1
runners:
  test:
    name: test
    ssh: ssh generic-test-runner.internal
EOF
    run bash "$VALIDATE" --validate-yaml "$TMP/dr.yml"
    [ "$status" -eq 1 ]
}

@test "validator: disallowed sudoers stem => exit 1" {
    write_valid_contract "$TMP/dr.yml"
    # inject a command outside the allow-list (systemctl/cp/mkdir/journalctl)
    sed -i.bak 's/- systemctl daemon-reload/- rm -rf \/var\/www/' "$TMP/dr.yml"
    run bash "$VALIDATE" --validate-yaml "$TMP/dr.yml"
    [ "$status" -eq 1 ]
}

@test "validator: injection canary — command-substitution value parsed as data, canary absent" {
    write_valid_contract "$TMP/dr.yml"
    CANARY="$TMP/canary-$$"
    # an attacker value that would create the canary if the validator eval'd it
    printf '      - systemctl restart $(touch %s)\n' "$CANARY" >> "$TMP/dr.yml"
    run bash "$VALIDATE" --validate-yaml "$TMP/dr.yml"
    # the canary MUST NOT exist — proves no eval/command-substitution happened
    [ ! -e "$CANARY" ]
}
