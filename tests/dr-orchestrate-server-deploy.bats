#!/usr/bin/env bats
# dr-orchestrate-server-deploy.bats — invariants for the dr-orchestrate-server
# supervision-unit templates (TUNE-0339: replaces the foreground `start &`
# invocation in the Phase G runbook with systemd + launchd restart-with-backoff
# templates). Static-file assertions only — neither unit is installed/enabled
# by these tests or by the change itself.

DEPLOY="${BATS_TEST_DIRNAME}/../plugins/dr-orchestrate/deploy"
SERVICE="$DEPLOY/dr-orchestrate-server.service"
PLIST="$DEPLOY/com.arcanada.dr-orchestrate-server.plist"

@test "systemd unit file exists" {
    [ -f "$SERVICE" ]
}

@test "launchd plist file exists" {
    [ -f "$PLIST" ]
}

@test "deploy README documents both platforms" {
    grep -qi 'systemd' "$DEPLOY/README.md"
    grep -qi 'launchd' "$DEPLOY/README.md"
}

# --- systemd -----------------------------------------------------------

@test "systemd unit points ExecStart at dr_orchestrate_server.sh start" {
    grep -q '^ExecStart=.*dr_orchestrate_server\.sh start$' "$SERVICE"
}

@test "systemd unit declares Restart=on-failure with a RestartSec delay" {
    grep -q '^Restart=on-failure$' "$SERVICE"
    grep -q '^RestartSec=' "$SERVICE"
}

@test "systemd unit caps restart attempts (StartLimitIntervalSec + StartLimitBurst)" {
    grep -q '^StartLimitIntervalSec=' "$SERVICE"
    grep -q '^StartLimitBurst=' "$SERVICE"
}

@test "systemd unit is enableable (WantedBy in [Install])" {
    grep -q '^WantedBy=' "$SERVICE"
}

@test "systemd unit applies the hardening floor (matches drift-sweep.service precedent)" {
    grep -q '^NoNewPrivileges=true$' "$SERVICE"
    grep -q '^ProtectSystem=strict$' "$SERVICE"
}

# --- launchd -------------------------------------------------------------

@test "launchd plist is well-formed XML" {
    run python3 -c "import xml.dom.minidom as m; m.parse('$PLIST')"
    [ "$status" -eq 0 ]
}

@test "launchd plist ProgramArguments invokes dr_orchestrate_server.sh start" {
    grep -q 'dr_orchestrate_server.sh' "$PLIST"
    grep -q '<string>start</string>' "$PLIST"
}

@test "launchd plist restarts only on non-zero exit (KeepAlive.SuccessfulExit=false)" {
    run python3 - "$PLIST" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    data = plistlib.load(f)
keepalive = data.get("KeepAlive")
assert isinstance(keepalive, dict), f"KeepAlive must be a dict, got {keepalive!r}"
assert keepalive.get("SuccessfulExit") is False
PY
    [ "$status" -eq 0 ]
}

@test "launchd plist declares a ThrottleInterval restart delay" {
    grep -q '<key>ThrottleInterval</key>' "$PLIST"
}

@test "launchd plist Label matches the systemd unit name (cross-platform parity)" {
    grep -q '<string>com.arcanada.dr-orchestrate-server</string>' "$PLIST"
}
