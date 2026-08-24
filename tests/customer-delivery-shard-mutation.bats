#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SOURCE="$ROOT/tests/run-customer-delivery-shard.py"
    CONTRACT="$ROOT/tests/customer-delivery-shard-runner.bats"
    PYTHON=/usr/bin/python3
    MUTATION_HARNESS="$ROOT/dev-tools/tests/customer-delivery-mutation.bats"
}

@test "shard runner child-status timeout output-count and alternate-syntax mutants are independently killed" {
    local kind filter mutant
    for kind in child_status timeout_status output_count alternate_syntax; do
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
        elif [ "$kind" = timeout_status ]; then
            filter='customer-delivery shard timeout kills the child group and returns 124'
            "$PYTHON" - "$mutant" <<'PY' || return 1
import sys
path = sys.argv[1]
source = open(path, encoding="utf-8").read()
old = "return 124"
assert source.count(old) == 1
open(path, "w", encoding="utf-8").write(source.replace(old, "return 0"))
PY
        elif [ "$kind" = output_count ]; then
            filter='customer-delivery shard runner rejects empty successful Bats output'
            "$PYTHON" - "$mutant" <<'PY' || return 1
import sys
path = sys.argv[1]
source = open(path, encoding="utf-8").read()
old = "validate_bats_execution(output, len(names))"
assert source.count(old) == 1
open(path, "w", encoding="utf-8").write(source.replace(old, "None"))
PY
        else
            filter='customer-delivery shard runner rejects alternate Bats syntax instead of dead-testing it'
            "$PYTHON" - "$mutant" <<'PY' || return 1
import sys
path = sys.argv[1]
source = open(path, encoding="utf-8").read()
old = "if ALTERNATE_TEST_PATTERN.fullmatch(line):"
assert source.count(old) == 1
open(path, "w", encoding="utf-8").write(source.replace(old, "if False:"))
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

@test "mutation attribution false-kill acceptance mutants are independently rejected" {
    local kind mutant filter='mutation kill attribution rejects setup syntax timeout and wrong-assertion failures'
    for kind in wrong_assertion timeout syntax; do
        mutant="$BATS_TEST_TMPDIR/attribution-${kind}.bats"
        cp "$MUTATION_HARNESS" "$mutant"
        "$PYTHON" - "$mutant" "$kind" <<'PY' || return 1
import sys
path, kind = sys.argv[1:]
source = open(path, encoding="utf-8").read()
replacements = {
    "wrong_assertion": ('    if [ "$matched" -ne 1 ]; then', '    if false; then'),
    "timeout": ('    if [ "$nested_status" -eq 124 ] \\\n', '    if false \\\n'),
    "syntax": ('        || [[ "$nested_output" == *"syntax error"* ]] \\\n', '        || false \\\n'),
}
old, new = replacements[kind]
if source.count(old) != 1:
    raise SystemExit(f"attribution seam missing: {kind}")
open(path, "w", encoding="utf-8").write(source.replace(old, new))
PY
        run bats --filter "^${filter}$" "$mutant"
        [ "$status" -ne 0 ] \
            && [[ "$output" == *"not ok 1 ${filter}"* ]] \
            || return 1
    done
}
