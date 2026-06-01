#!/usr/bin/env bats
# dr-archive-drift-substep.bats — V-4 / V-AC-8 scenario coverage for the
# level-2 dr-archive sub-step 0.15. The sub-step is an executable instruction
# (detector --check → resolve_backlog_sink → append_site_update_task); this
# test replays that exact pipeline against a fixture KB-root and asserts the
# three branches the sub-step prescribes:
#   (1) detector present + drift   → one site-update backlog line appended
#   (2) detector present + clean   → no-op
#   (3) detector absent            → no-op (silent skip)

setup() {
    REPO_ROOT="${BATS_TEST_DIRNAME}/.."
    DETECTOR="$REPO_ROOT/dev-tools/check-repo-site-sync.sh"
    LIB="$REPO_ROOT/dev-tools/lib/backlog-sink.sh"
    KB="$(mktemp -d)"
    STATE="$(mktemp -d)"
    export XDG_STATE_HOME="$STATE"
    mkdir -p "$KB/documentation/ecosystem-sync" "$KB/datarim"
    : > "$KB/datarim/backlog.md"
    # Fixture product "demo": git repo + site dir, fully synced by default.
    mkdir -p "$KB/repo/commands" "$KB/site"
    ( cd "$KB/repo" && git init -q && git config user.email t@t && git config user.name t )
    printf '1.0.0\n' > "$KB/repo/VERSION"
    : > "$KB/repo/commands/a.md"; : > "$KB/repo/commands/b.md"
    printf '# demo\nSee https://demo.example for the site.\n' > "$KB/repo/README.md"
    printf "<?php return ['version' => '1.0.0'];\n" > "$KB/site/config.php"
    printf '2 commands\n<a href="https://arcanada.one/ecosystem">eco</a>\n' > "$KB/site/features.php"
    ( cd "$KB/repo" && git add -A && git commit -qm init )
    write_registry
    export DATARIM_BACKLOG_PATH="$KB/datarim/backlog.md"
}

teardown() { rm -rf "$KB" "$STATE"; }

write_registry() {
    cat > "$KB/documentation/ecosystem-sync/registry.yml" <<EOF
products:
  demo:
    repo_local: repo
    domain: demo.example
    site_local: site
    head_site: arcanada.one
    version_repo: VERSION
    version_site: config.php
    feature_count_repo: commands
    feature_count_site: features.php
    readme_repo: README.md
EOF
}

# Replays sub-step 0.15 for product "demo": returns the detector exit and, on
# drift, performs the resolve+append the sub-step prescribes.
replay_substep() {  # $1=detector-path (may be a non-existent path to test absence)
    local detector="$1"
    # 0.15.1 applicability: skip silently if detector absent.
    [ -x "$detector" ] || return 0
    local rc=0
    "$detector" --check --product demo --root "$KB" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 1 ]; then
        . "$LIB"
        local backlog
        if backlog="$(resolve_backlog_sink --root "$KB")"; then
            append_site_update_task "$backlog" demo MEDIUM "repo↔site drift at archive"
        fi
    fi
    return 0
}

@test "V-4a: detector present + drift → one site-update line appended" {
    # Introduce drift: bump repo version so site (1.0.0) lags repo (1.1.0).
    printf '1.1.0\n' > "$KB/repo/VERSION"
    ( cd "$KB/repo" && git add -A && git commit -qm bump )
    run "$DETECTOR" --check --product demo --root "$KB"
    [ "$status" -eq 1 ]   # confirm fixture actually drifts
    replay_substep "$DETECTOR"
    [ "$(grep -cF 'drift-site-update-demo' "$DATARIM_BACKLOG_PATH")" -eq 1 ]
    grep -q 'Site-update demo' "$DATARIM_BACKLOG_PATH"
}

@test "V-4b: detector present + clean → no backlog line" {
    run "$DETECTOR" --check --product demo --root "$KB"
    [ "$status" -eq 0 ]   # synced fixture
    replay_substep "$DETECTOR"
    [ ! -s "$DATARIM_BACKLOG_PATH" ]
}

@test "V-4c: detector absent → silent no-op, no backlog line" {
    printf '1.1.0\n' > "$KB/repo/VERSION"
    ( cd "$KB/repo" && git add -A && git commit -qm bump )
    replay_substep "$KB/nonexistent-detector.sh"
    [ ! -s "$DATARIM_BACKLOG_PATH" ]
}

@test "V-4d: idempotent — replaying the drift sub-step twice keeps one line" {
    printf '1.1.0\n' > "$KB/repo/VERSION"
    ( cd "$KB/repo" && git add -A && git commit -qm bump )
    replay_substep "$DETECTOR"
    replay_substep "$DETECTOR"
    [ "$(grep -cF 'drift-site-update-demo' "$DATARIM_BACKLOG_PATH")" -eq 1 ]
}
