#!/usr/bin/env bats
# check-repo-site-sync.bats — V-AC matrix for the ecosystem repo↔site drift
# detector (ARCA-0143). Each test builds a throwaway KB-root with a fixture
# product (git repo + site dir + registry) and asserts detector behaviour.

setup() {
    DETECTOR="${BATS_TEST_DIRNAME}/../dev-tools/check-repo-site-sync.sh"
    KB="$(mktemp -d)"
    mkdir -p "$KB/documentation/ecosystem-sync"
    # Fixture product "demo": a git repo + a site dir.
    mkdir -p "$KB/repo/commands" "$KB/site"
    ( cd "$KB/repo" && git init -q && git config user.email t@t && git config user.name t )
    printf '1.0.0\n' > "$KB/repo/VERSION"
    : > "$KB/repo/commands/a.md"; : > "$KB/repo/commands/b.md"     # 2 commands
    printf '# demo\nSee https://demo.example for the site.\n' > "$KB/repo/README.md"
    printf "<?php return ['version' => '1.0.0'];\n" > "$KB/site/config.php"
    printf '2 commands\n<a href="https://arcanada.one/ecosystem">eco</a>\n' > "$KB/site/features.php"
    ( cd "$KB/repo" && git add -A && git commit -qm init )
    write_registry  # default: fully-synced
}

teardown() { rm -rf "$KB"; }

# Helper: write a registry for product "demo" pointing at the fixtures.
write_registry() {
    cat > "$KB/documentation/ecosystem-sync/registry.yml" <<EOF
products:
  demo:
    repo_local: repo
    repo_remote: Arcanada-one/demo
    domain: demo.example
    site_local: site
    deploy_path: deploy.sh
    head_site: arcanada.one
    version_repo: VERSION
    version_site: config.php
    feature_count_repo: commands
    feature_count_site: features.php
    readme_repo: README.md
    page_bindings:
      - commands/*.md => data/commands/*.php
EOF
}

@test "help exits 0" {
    run bash "$DETECTOR" --help
    [ "$status" -eq 0 ]
}

@test "unknown flag exits 2" {
    run bash "$DETECTOR" --bogus --root "$KB"
    [ "$status" -eq 2 ]
}

@test "missing registry exits 3" {
    rm -f "$KB/documentation/ecosystem-sync/registry.yml"
    run bash "$DETECTOR" --check --root "$KB"
    [ "$status" -eq 3 ]
}

@test "fully synced fixture: --check exits 0" {
    run bash "$DETECTOR" --check --root "$KB"
    [ "$status" -eq 0 ]
}

@test "version mismatch site-ahead: exit 1 + HIGH severity (V-AC-3/7)" {
    printf "<?php return ['version' => '1.1.0'];\n" > "$KB/site/config.php"  # site ahead
    run bash "$DETECTOR" --check --root "$KB"
    [ "$status" -eq 1 ]
    run bash "$DETECTOR" --report --root "$KB"
    [[ "$output" == *HIGH* ]]
    [[ "$output" == *version* ]]
}

@test "version mismatch site-behind: exit 1 + MEDIUM severity (V-AC-7)" {
    printf '1.2.0\n' > "$KB/repo/VERSION"   # repo ahead → site behind
    ( cd "$KB/repo" && git commit -qam bump )
    run bash "$DETECTOR" --check --root "$KB"
    [ "$status" -eq 1 ]
    run bash "$DETECTOR" --report --root "$KB"
    [[ "$output" == *MEDIUM* ]]
}

@test "feature count mismatch: exit 1 (V-AC-3)" {
    : > "$KB/repo/commands/c.md"   # now 3 commands, site still says "2 commands"
    ( cd "$KB/repo" && git add -A && git commit -qm add-cmd )
    run bash "$DETECTOR" --check --root "$KB"
    [ "$status" -eq 1 ]
}

@test "reverse link missing in README: exit 1 (V-AC-6)" {
    printf '# demo\nno site link here\n' > "$KB/repo/README.md"
    ( cd "$KB/repo" && git commit -qam delink )
    run bash "$DETECTOR" --check --root "$KB"
    [ "$status" -eq 1 ]
    run bash "$DETECTOR" --report --root "$KB"
    [[ "$output" == *linkage* ]] || [[ "$output" == *link* ]]
}

@test "footer-SHA staleness: stamp at HEAD~1 + newer content commit → exit 1 (V-AC-5)" {
    local oldsha; oldsha=$( cd "$KB/repo" && git rev-parse --short HEAD )
    printf 'new content\n' >> "$KB/repo/commands/a.md"
    ( cd "$KB/repo" && git commit -qam content )
    printf '%s\n' "$oldsha" > "$KB/site/.build-sha"   # stamp points to the OLD commit
    run bash "$DETECTOR" --check --root "$KB"
    [ "$status" -eq 1 ]
    run bash "$DETECTOR" --report --root "$KB"
    [[ "$output" == *stale* ]] || [[ "$output" == *STALE* ]]
}

@test "footer-SHA absent: not a drift (skip), synced fixture stays exit 0 (V-AC-5)" {
    # no .build-sha file present (default) — staleness check skips, others clean
    run bash "$DETECTOR" --check --root "$KB"
    [ "$status" -eq 0 ]
}

@test "--product scopes to one id; unknown product exits 0 clean" {
    run bash "$DETECTOR" --check --product nonexistent --root "$KB"
    [ "$status" -eq 0 ]
}

@test "path traversal in repo_local is rejected (source unavailable, no escape)" {
    sed -i.bak 's|repo_local: repo|repo_local: ../../../../etc|' "$KB/documentation/ecosystem-sync/registry.yml"
    run bash "$DETECTOR" --check --root "$KB"
    # escaping path → treated as source unavailable → skipped → clean exit 0
    [ "$status" -eq 0 ]
    run bash "$DETECTOR" --report --root "$KB"
    [[ "$output" == *unavailable* ]] || [[ "$output" == *skip* ]]
}
