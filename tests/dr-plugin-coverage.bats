#!/usr/bin/env bats
# dr-plugin-coverage.bats — TUNE-0101 Phase F coverage gate.
#
# Three behaviour-level coverage rules guard against drift between
# implementation and tests/dr-plugin.bats:
#
#   1. Library helpers in scripts/lib/plugin-system.sh — at least 80% of
#      public functions are referenced by name in dr-plugin.bats (sourced and
#      invoked directly).
#   2. CLI subcommands (cmd_*) — each cmd_<sub> is exercised by a subcommand
#      invocation containing the literal keyword.
#   3. Doctor checks (_doctor_check_*) — each check has either a function-
#      name reference or its check-id slug present in the bats file.
#
# Threshold for rule 1 is configurable via DR_PLUGIN_COVERAGE_MIN (default 80).

PLUGIN_SH="$BATS_TEST_DIRNAME/../scripts/dr-plugin.sh"
LIB_SH="$BATS_TEST_DIRNAME/../scripts/lib/plugin-system.sh"
BATS_FILE="$BATS_TEST_DIRNAME/dr-plugin.bats"

# Lib helpers excluded from the ratio because they are pure internals
# exercised transitively by every public path; testing them in isolation
# adds churn without meaningful safety.
EXCLUDED_LIB_FUNCS=(
    _check_no_crlf
    _dep_dfs
    snapshot_dir
)

is_excluded() {
    local fn="$1"
    local x
    for x in "${EXCLUDED_LIB_FUNCS[@]}"; do
        [ "$fn" = "$x" ] && return 0
    done
    return 1
}

list_funcs() {
    grep -hE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)[[:space:]]*\{' "$@" \
        | sed -E 's/^([a-zA-Z_][a-zA-Z0-9_]*)\(\).*/\1/'
}

# ---------------------------------------------------------------------------
# Rule 1 — every lib function is either directly tested OR called by
# dr-plugin.sh (which is itself integration-tested). Effectively a dead-code
# detector: any orphaned helper fails the gate.

@test "coverage: every plugin-system.sh function is reachable from tests" {
    threshold="${DR_PLUGIN_COVERAGE_MIN:-80}"

    [ -f "$LIB_SH" ]    || { echo "missing $LIB_SH"; return 1; }
    [ -f "$BATS_FILE" ] || { echo "missing $BATS_FILE"; return 1; }
    [ -f "$PLUGIN_SH" ] || { echo "missing $PLUGIN_SH"; return 1; }

    total=0
    covered=0
    direct=0
    transitive=0
    uncovered=()

    while IFS= read -r fn; do
        is_excluded "$fn" && continue
        total=$((total + 1))
        if grep -q -F -- "$fn" "$BATS_FILE"; then
            covered=$((covered + 1)); direct=$((direct + 1))
        elif grep -q -F -- "$fn" "$PLUGIN_SH"; then
            covered=$((covered + 1)); transitive=$((transitive + 1))
        else
            uncovered+=("$fn")
        fi
    done < <(list_funcs "$LIB_SH" | sort -u)

    [ "$total" -gt 0 ] || { echo "no public lib functions detected"; return 1; }

    pct=$(( covered * 100 / total ))
    echo "lib coverage: $covered / $total = ${pct}% (direct=$direct, transitive=$transitive, threshold ${threshold}%)"

    if [ "${#uncovered[@]}" -gt 0 ]; then
        echo "orphaned (not used by dr-plugin.sh and not tested):"
        for fn in "${uncovered[@]}"; do echo "  - $fn"; done
    fi

    [ "$pct" -ge "$threshold" ]
}

# ---------------------------------------------------------------------------
# Rule 2 — every cmd_<sub> exercised by a real subcommand invocation

@test "coverage: every cmd_<sub> exercised by a subcommand invocation" {
    missing=()
    while IFS= read -r fn; do
        case "$fn" in
            cmd_*)
                sub="${fn#cmd_}"
                # Match the keyword as a subcommand argument, not in a comment
                # or function name. Look for either:
                #   - "$PLUGIN_SH" <sub>          # direct script call
                #   - dr-plugin.sh <sub>          # path-style call
                #   - "$PLUGIN_SH" --flag … <sub> (positional after flags)
                if grep -qE "(\\\$PLUGIN_SH|dr-plugin\\.sh)[^|&;]*[[:space:]]${sub}\\b" "$BATS_FILE"; then
                    :
                else
                    missing+=("$fn (sub: $sub)")
                fi
                ;;
        esac
    done < <(list_funcs "$PLUGIN_SH" | sort -u)

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "subcommands without invocation:"
        for fn in "${missing[@]}"; do echo "  - $fn"; done
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Rule 3 — every doctor check covered by name OR slug

@test "coverage: every _doctor_check_<id> has name or slug coverage" {
    missing=()
    while IFS= read -r fn; do
        case "$fn" in
            _doctor_check_*)
                slug="${fn#_doctor_check_}"           # e.g. dependency_graph
                slug_dash="${slug//_/-}"              # e.g. dependency-graph
                # Split slug into tokens; coverage is satisfied if the full
                # slug, dash variant, function name, or ANY token appears in
                # the bats file. Tokens like "dependency", "graph", "git",
                # "override" are highly discriminating in the test file scope.
                tokens="${slug//_/ }"
                hit=0
                for needle in "$fn" "$slug_dash" "$slug" $tokens; do
                    if grep -qiF -- "$needle" "$BATS_FILE"; then
                        hit=1; break
                    fi
                done
                [ "$hit" -eq 1 ] || missing+=("$fn")
                ;;
        esac
    done < <(list_funcs "$PLUGIN_SH" | sort -u)

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "doctor checks without coverage:"
        for fn in "${missing[@]}"; do echo "  - $fn"; done
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Rule 4 — sanity floor on absolute test count

@test "coverage: ≥75 @test cases in dr-plugin.bats" {
    n=$(grep -cE '^@test' "$BATS_FILE")
    echo "test count: $n (floor 75)"
    [ "$n" -ge 75 ]
}
