#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SOURCE="$ROOT/tests/run-customer-delivery-shard.py"
    CONTRACT="$ROOT/tests/customer-delivery-shard-runner.bats"
    PYTHON=/usr/bin/python3
}

@test "shard runner child-status and timeout-status mutants are independently killed" {
    local kind filter mutant
    for kind in child_status timeout_status; do
        mutant="$BATS_TEST_TMPDIR/runner-$kind.py"
        cp "$SOURCE" "$mutant"
        if [ "$kind" = child_status ]; then
            filter='customer-delivery shard runner propagates a nonzero child status'
            "$PYTHON" - "$mutant" <<'PY' || return 1
import sys
path = sys.argv[1]
source = open(path, encoding="utf-8").read()
old = "return returncode"
assert source.count(old) == 1
open(path, "w", encoding="utf-8").write(source.replace(old, "return 0"))
PY
        else
            filter='customer-delivery shard timeout kills the child group and returns 124'
            "$PYTHON" - "$mutant" <<'PY' || return 1
import sys
path = sys.argv[1]
source = open(path, encoding="utf-8").read()
old = "return 124"
assert source.count(old) == 1
open(path, "w", encoding="utf-8").write(source.replace(old, "return 0"))
PY
        fi
        run bats --filter "^${filter}$" "$CONTRACT"
        [ "$status" -eq 0 ] || return 1
        run env CUSTOMER_DELIVERY_SHARD_RUNNER_OVERRIDE="$mutant" \
            bats --filter "^${filter}$" "$CONTRACT"
        [ "$status" -ne 0 ] \
            && [[ "$output" == *"not ok 1 ${filter}"* ]] \
            || return 1
    done
}
