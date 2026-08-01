#!/usr/bin/env bats
#
# plugins/dr-fleet-evolution/tests/plugin-contract.bats
#
# Minimal contract suite for the dr-fleet-evolution plugin.
#
# WHY
# ---
# This plugin shipped with no suite of its own. Seven root-level suites
# (tests/test-fleet-evolution-*.bats) exercise its adapters, gates, jsonl
# helpers and loop behaviour, so it was never truly untested — but nothing
# asserted the *structural* contract: that every shipped script parses, that the
# gate runner still discovers each gate, and that the adapter registry does not
# point at files that no longer exist. Those are exactly the breakages a rename
# or a partial refactor introduces, and behavioural tests elsewhere would not
# necessarily catch them.
#
# Scope is deliberately structural. Behaviour lives in the root-level suites.

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export PLUGIN_ROOT
}

# --- shipped shell integrity -------------------------------------------------

@test "every shipped shell script parses under bash -n" {
    local failed=""
    while IFS= read -r f; do
        bash -n "$f" 2>/dev/null || failed="${failed} ${f}"
    done < <(find "$PLUGIN_ROOT" -type f -name '*.sh' | sort)
    [ -z "$failed" ] || {
        echo "scripts failed bash -n:${failed}"
        return 1
    }
}

@test "every shipped shell script is shellcheck-clean at error severity" {
    if ! command -v shellcheck >/dev/null 2>&1; then
        skip "shellcheck not installed"
    fi
    local failed=""
    while IFS= read -r f; do
        shellcheck -S error "$f" >/dev/null 2>&1 || failed="${failed} ${f}"
    done < <(find "$PLUGIN_ROOT" -type f -name '*.sh' | sort)
    [ -z "$failed" ] || {
        echo "scripts failed shellcheck -S error:${failed}"
        return 1
    }
}

@test "the plugin actually ships shell scripts (guards against an empty glob)" {
    # Without this, every assertion above would vacuously pass if the find
    # pattern or the layout changed.
    local n
    n="$(find "$PLUGIN_ROOT" -type f -name '*.sh' | wc -l)"
    [ "$n" -ge 10 ]
}

# --- gate runner contract ----------------------------------------------------

@test "run-all-gates.sh exits 2 on missing arguments" {
    run bash "$PLUGIN_ROOT/gates/run-all-gates.sh"
    [ "$status" -eq 2 ]
}

@test "run-all-gates.sh exits 2 when the candidate file does not exist" {
    run bash "$PLUGIN_ROOT/gates/run-all-gates.sh" "$BATS_TEST_TMPDIR/absent.md" l1-basic
    [ "$status" -eq 2 ]
}

@test "run-all-gates.sh discovers gates by glob, and at least one gate exists" {
    # The runner iterates "$GATES_DIR"/gate-*.sh. Assert the glob is non-empty,
    # otherwise the runner would report success having run nothing at all —
    # the same fail-open shape this whole task exists to remove.
    local n
    n="$(find "$PLUGIN_ROOT/gates" -maxdepth 1 -type f -name 'gate-*.sh' | wc -l)"
    [ "$n" -ge 1 ]

    grep -q 'gate-\*\.sh' "$PLUGIN_ROOT/gates/run-all-gates.sh"
}

@test "every gate script parses and responds to a missing candidate" {
    while IFS= read -r gate; do
        bash -n "$gate"
    done < <(find "$PLUGIN_ROOT/gates" -maxdepth 1 -type f -name 'gate-*.sh' | sort)
}

# --- adapter registry contract ----------------------------------------------

@test "source-adapters.conf references only adapter scripts that exist" {
    local conf="$PLUGIN_ROOT/adapters/source-adapters.conf"
    [ -f "$conf" ]

    local rows=0 line script
    while IFS= read -r line; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        rows=$(( rows + 1 ))
        script="${line%%|*}"
        [ -n "$script" ]
        [ -f "$PLUGIN_ROOT/$script" ] || {
            echo "adapter registry points at a missing script: $script"
            return 1
        }
    done <"$conf"

    # A registry that parsed to zero rows would pass vacuously.
    [ "$rows" -ge 1 ]
}

@test "every source-adapters.conf row has the documented three fields" {
    local conf="$PLUGIN_ROOT/adapters/source-adapters.conf"
    local line n
    while IFS= read -r line; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        n="$(awk -F'|' '{print NF}' <<<"$line")"
        [ "$n" -eq 3 ] || {
            echo "row does not have 3 pipe-separated fields: $line"
            return 1
        }
    done <"$conf"
}

# --- library + entry point ---------------------------------------------------

@test "lib helpers are sourceable without side effects" {
    while IFS= read -r lib; do
        run bash -c "source '$lib'"
        [ "$status" -eq 0 ]
    done < <(find "$PLUGIN_ROOT/lib" -maxdepth 1 -type f -name '*.sh' | sort)
}

@test "evolution-loop.sh --help exits 0 and describes the pipeline" {
    run bash "$PLUGIN_ROOT/evolution-loop.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pipeline"* ]]
}

@test "README documents the entry point" {
    [ -f "$PLUGIN_ROOT/README.md" ]
    grep -q 'evolution-loop.sh' "$PLUGIN_ROOT/README.md"
}
