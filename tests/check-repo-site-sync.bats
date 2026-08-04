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

# Helper: extend the fixture for dimension (5) narrative parity. Adds two
# hyphenated commands (so a `dr-` token prefix is derivable), keeps the
# rendered feature count in sync, and creates matching bound site pages.
narrative_fixture() {
    printf '# run\nRuns things. Supports `--fast` and `--dry` flags.\n' > "$KB/repo/commands/dr-run.md"
    printf '# stop\nStops things.\n' > "$KB/repo/commands/dr-stop.md"
    printf '4 commands\n<a href="https://arcanada.one/ecosystem">eco</a>\n' > "$KB/site/features.php"
    ( cd "$KB/repo" && git add -A && git commit -qm narrative-fixture )
    mkdir -p "$KB/site/data/commands"
    printf '<?php // page for /dr-run — use --fast for speed\n' > "$KB/site/data/commands/dr-run.php"
    printf '<?php // page for /dr-stop\n' > "$KB/site/data/commands/dr-stop.php"
    printf '<?php // page a\n' > "$KB/site/data/commands/a.php"
    printf '<?php // page b\n' > "$KB/site/data/commands/b.php"
}

@test "narrative: synced fixture with bound pages exits 0 under --narrative" {
    narrative_fixture
    run bash "$DETECTOR" --check --narrative --root "$KB"
    [ "$status" -eq 0 ]
}

@test "narrative: orphan site page (artefact removed) → exit 1 + narrative finding" {
    narrative_fixture
    printf '<?php // page for a command that no longer exists\n' > "$KB/site/data/commands/dr-gone.php"
    run bash "$DETECTOR" --check --narrative --root "$KB"
    [ "$status" -eq 1 ]
    run bash "$DETECTOR" --report --narrative --root "$KB"
    [[ "$output" == *narrative* ]]
    [[ "$output" == *"removed artefact"* ]]
}

@test "narrative: stale slash-command token → exit 1 names the token" {
    narrative_fixture
    printf '<?php // see also /dr-vanished for details\n' >> "$KB/site/data/commands/dr-run.php"
    run bash "$DETECTOR" --check --narrative --root "$KB"
    [ "$status" -eq 1 ]
    run bash "$DETECTOR" --report --narrative --root "$KB"
    [[ "$output" == *"/dr-vanished"* ]]
}

@test "narrative: retired command still narrated in repo corpus is NOT drift" {
    narrative_fixture
    printf 'Historical note: replaces the former dr-legacy command.\n' >> "$KB/repo/commands/dr-run.md"
    ( cd "$KB/repo" && git commit -qam legacy-note )
    printf '<?php // replaced the former /dr-legacy command\n' >> "$KB/site/data/commands/dr-run.php"
    run bash "$DETECTOR" --check --narrative --root "$KB"
    [ "$status" -eq 0 ]
}

@test "narrative: command token inside a path context is NOT drift" {
    narrative_fixture
    printf '<?php // implemented by dev-tools/dr-floor.sh helper\n' >> "$KB/site/data/commands/dr-run.php"
    run bash "$DETECTOR" --check --narrative --root "$KB"
    [ "$status" -eq 0 ]
}

@test "narrative: stale --flag token (in no repo artefact) → exit 1 names the flag" {
    narrative_fixture
    printf '<?php // pass --vanished-flag to enable\n' >> "$KB/site/data/commands/dr-run.php"
    run bash "$DETECTOR" --check --narrative --root "$KB"
    [ "$status" -eq 1 ]
    run bash "$DETECTOR" --report --narrative --root "$KB"
    [[ "$output" == *"--vanished-flag"* ]]
}

@test "narrative: dimension is opt-in — same drift fixture passes without --narrative" {
    narrative_fixture
    printf '<?php // page for a command that no longer exists\n' > "$KB/site/data/commands/dr-gone.php"
    printf '<?php // see also /dr-vanished and --vanished-flag\n' >> "$KB/site/data/commands/dr-run.php"
    run bash "$DETECTOR" --check --root "$KB"
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
