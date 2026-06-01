#!/usr/bin/env bats
# backlog-sink.bats — unit matrix for the shared backlog-sink resolver library
# consumed by both the dr-archive sub-step (level 2) and the cron sweep
# (level 3). Each test sources the library in a throwaway KB-root and asserts
# the resolve_backlog_sink fallback chain plus the append_site_update_task
# idempotency / injection-gate contract.

setup() {
    LIB="${BATS_TEST_DIRNAME}/../dev-tools/lib/backlog-sink.sh"
    KB="$(mktemp -d)"
    unset DATARIM_BACKLOG_PATH
}

teardown() { rm -rf "$KB"; }

# Write a space.yml under a spaces/<name>/ tree with a chosen backend.
write_space_yml() {  # $1=backend $2=datarim_path
    mkdir -p "$KB/spaces/arcanada"
    cat > "$KB/spaces/arcanada/space.yml" <<EOF
space: arcanada
infra:
  knowledge_base:
    current_backend: $1
    datarim_path: $2
EOF
}

# ---- resolve_backlog_sink fallback chain (V-2) ----

@test "V-2a: DATARIM_BACKLOG_PATH env override wins" {
    export DATARIM_BACKLOG_PATH="$KB/custom-backlog.md"
    run bash -c "source '$LIB'; resolve_backlog_sink --root '$KB'"
    [ "$status" -eq 0 ]
    [ "$output" = "$KB/custom-backlog.md" ]
}

@test "V-2b: space.yml file-based-datarim resolves datarim_path/backlog.md" {
    mkdir -p "$KB/datarim"
    write_space_yml file-based-datarim "$KB/datarim"
    run bash -c "cd '$KB/spaces/arcanada'; source '$LIB'; resolve_backlog_sink"
    [ "$status" -eq 0 ]
    [ "$output" = "$KB/datarim/backlog.md" ]
}

@test "V-2c: space.yml non-file backend (future muneral) → exit 1, no path" {
    write_space_yml muneral "$KB/datarim"
    run bash -c "cd '$KB/spaces/arcanada'; source '$LIB'; resolve_backlog_sink"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "V-2d: bare datarim/backlog.md fallback when no space.yml" {
    mkdir -p "$KB/datarim"
    run bash -c "cd '$KB'; source '$LIB'; resolve_backlog_sink"
    [ "$status" -eq 0 ]
    [ "$output" = "$KB/datarim/backlog.md" ]
}

@test "V-2e: nothing resolvable → exit 1" {
    run bash -c "cd '$KB'; source '$LIB'; resolve_backlog_sink"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

# ---- append_site_update_task idempotency (V-3) ----

@test "V-3: two appends for same product produce exactly one backlog line" {
    bl="$KB/backlog.md"; : > "$bl"
    bash -c "source '$LIB'; append_site_update_task '$bl' demo MEDIUM 'site behind repo'"
    bash -c "source '$LIB'; append_site_update_task '$bl' demo MEDIUM 'site behind repo'"
    run grep -cF 'drift-site-update-demo' "$bl"
    [ "$output" -eq 1 ]
}

@test "V-3b: distinct products produce distinct anchored lines" {
    bl="$KB/backlog.md"; : > "$bl"
    bash -c "source '$LIB'; append_site_update_task '$bl' alpha MEDIUM 'x'"
    bash -c "source '$LIB'; append_site_update_task '$bl' beta HIGH 'y'"
    [ "$(grep -cF 'drift-site-update-alpha' "$bl")" -eq 1 ]
    [ "$(grep -cF 'drift-site-update-beta' "$bl")" -eq 1 ]
}

# ---- line-injection gate (V-6 / S9) ----

@test "V-6a: embedded newline in detail is rejected, no forged line" {
    bl="$KB/backlog.md"; : > "$bl"
    run bash -c "source '$LIB'; append_site_update_task '$bl' demo MEDIUM \$'line1\nINJECTED pending P0'"
    [ "$status" -ne 0 ]
    ! grep -q 'INJECTED' "$bl"
}

@test "V-6b: non-printable byte in detail is rejected" {
    bl="$KB/backlog.md"; : > "$bl"
    run bash -c "source '$LIB'; append_site_update_task '$bl' demo MEDIUM \$'bad\x01ctrl'"
    [ "$status" -ne 0 ]
}

@test "V-6c: product id with regex-meta / path-traversal is rejected" {
    bl="$KB/backlog.md"; : > "$bl"
    run bash -c "source '$LIB'; append_site_update_task '$bl' '../etc' MEDIUM 'x'"
    [ "$status" -ne 0 ]
    [ ! -s "$bl" ]
}

@test "V-6d: leading-dash product slug is rejected" {
    bl="$KB/backlog.md"; : > "$bl"
    run bash -c "source '$LIB'; append_site_update_task '$bl' '-evil' MEDIUM 'x'"
    [ "$status" -ne 0 ]
}

# ---- atomic append preserves prior content (V-3 atomicity) ----

@test "V-3c: append preserves pre-existing backlog content" {
    bl="$KB/backlog.md"
    printf -- '- EXISTING-0001 · pending · keep me\n' > "$bl"
    bash -c "source '$LIB'; append_site_update_task '$bl' demo MEDIUM 'd'"
    grep -q 'EXISTING-0001' "$bl"
    grep -q 'drift-site-update-demo' "$bl"
}
