#!/usr/bin/env bats
# test-tune-0266-validator-warn-all-static.bats — Phase 4 --all advisory
# warning "all wishes evidence_type=static" + legacy task skip semantics.
#
# Covers:
#   - 3 wishes, all evidence_type: static → exit 0 + stdout WARNING line
#   - 3 wishes, mixed (2 static + 1 empirical) → no warning
#   - 1 wish (L1 skeleton, single-wish exemption) → no warning
#   - legacy: true in task-description frontmatter → no warning
#   - captured_at < TUNE-0266 pivot date → skipped as legacy
#   - DATARIM_TUNE_0266_PIVOT_DATE env override moves the pivot
#
# Companion plan: datarim/plans/TUNE-0266-plan.md § Phase 4.

CHECK="$BATS_TEST_DIRNAME/../dev-tools/check-expectations-checklist.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/tasks"
}

teardown() {
    rm -rf "$TMPROOT"
}

# --- Helpers ----------------------------------------------------------------

# write_description <ID> [legacy_flag] [created_date]
write_description() {
    local id="$1"
    local legacy_line=""
    local created="${3:-2026-05-20}"
    [ "${2:-}" = "true" ] && legacy_line="legacy: true"
    cat > "$TMPROOT/datarim/tasks/${id}-task-description.md" <<EOF
---
task_id: $id
artifact: task-description
complexity: L3
status: in_progress
created: $created
$legacy_line
---

# $id — Test description

(тестовое описание)
EOF
}

# write_expectations <ID> <captured_at> <evidence_type_1> [evidence_type_2] [evidence_type_3]
# Writes a v2 expectations file with 1, 2 or 3 wishes depending on args.
write_expectations() {
    local id="$1"; local captured_at="$2"
    local ev1="${3:-}"; local ev2="${4:-}"; local ev3="${5:-}"
    local file="$TMPROOT/datarim/tasks/${id}-expectations.md"

    cat > "$file" <<EOF
---
task_id: $id
artifact: expectations
schema_version: 2
captured_at: $captured_at
captured_by: /dr-init
agent: planner
status: canonical
---

# $id — Ожидания оператора

## Ожидания

EOF

    local i=1
    for ev in "$ev1" "$ev2" "$ev3"; do
        [ -z "$ev" ] && continue
        cat >> "$file" <<EOF
- **${i}. Ожидание номер ${i}.**
  - wish_id: ozhidanie-nomer-${i}
  - Что хочу проверить: тестовое описание ${i}.
  - Как проверить (success criterion): сигнал проверки ${i}.
  - Связанный AC из PRD: V-AC-${i}
  - evidence_type: ${ev}
  - #### История статусов
    - 2026-05-23T00:00:00Z / 03:00 (MSK) · pending → pending · /dr-init · reason: пункт создан
  - #### Текущий статус
    - pending

EOF
        i=$(( i + 1 ))
    done

    cat >> "$file" <<EOF
## Append-log (operator amendments)

_(пусто на момент создания)_
EOF
}

# --- Cases ------------------------------------------------------------------

@test "warn-all-static: 3 wishes all static → exit 0 + WARNING line" {
    write_description "TUNETEST-0001"
    write_expectations "TUNETEST-0001" "2026-05-23" "static" "static" "static"
    run "$CHECK" --all --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TUNETEST-0001"* ]]
    [[ "$output" == *"WARNING"* ]]
    [[ "$output" == *"all wishes"* ]]
    [[ "$output" == *"static"* ]]
}

@test "warn-all-static: 3 wishes mixed (2 static + 1 empirical) → no warning" {
    write_description "TUNETEST-0002"
    write_expectations "TUNETEST-0002" "2026-05-23" "static" "static" "empirical"
    run "$CHECK" --all --root "$TMPROOT"
    [ "$status" -eq 0 ]
    if [[ "$output" == *"TUNETEST-0002"*"WARNING"* ]]; then
        echo "mixed evidence_type triggered WARNING — expected silence" >&2
        return 1
    fi
}

@test "warn-all-static: single-wish L1 skeleton (1 static) → no warning" {
    write_description "TUNETEST-0003"
    write_expectations "TUNETEST-0003" "2026-05-23" "static"
    run "$CHECK" --all --root "$TMPROOT"
    [ "$status" -eq 0 ]
    if [[ "$output" == *"TUNETEST-0003"*"WARNING"* ]]; then
        echo "single-wish all-static triggered WARNING — expected silence" >&2
        return 1
    fi
}

@test "warn-all-static: legacy: true in description → skipped (no warning)" {
    write_description "TUNETEST-0004" "true"
    write_expectations "TUNETEST-0004" "2026-05-23" "static" "static" "static"
    run "$CHECK" --all --root "$TMPROOT"
    [ "$status" -eq 0 ]
    if [[ "$output" == *"TUNETEST-0004"*"WARNING"* ]]; then
        echo "legacy: true task triggered WARNING — expected silence" >&2
        return 1
    fi
}

@test "warn-all-static: captured_at < TUNE-0266 pivot → auto-legacy skip" {
    # Default pivot is 2026-05-23 (TUNE-0266 archive date). 2026-04-01 < pivot.
    write_description "TUNETEST-0005"
    write_expectations "TUNETEST-0005" "2026-04-01" "static" "static" "static"
    run "$CHECK" --all --root "$TMPROOT"
    [ "$status" -eq 0 ]
    if [[ "$output" == *"TUNETEST-0005"*"WARNING"* ]]; then
        echo "captured_at < pivot triggered WARNING — expected auto-legacy skip" >&2
        return 1
    fi
}

@test "warn-all-static: DATARIM_TUNE_0266_PIVOT_DATE env override moves pivot" {
    write_description "TUNETEST-0006"
    write_expectations "TUNETEST-0006" "2026-05-23" "static" "static" "static"
    # Push pivot into the future → captured_at < pivot → skip
    DATARIM_TUNE_0266_PIVOT_DATE=2026-12-31 run "$CHECK" --all --root "$TMPROOT"
    [ "$status" -eq 0 ]
    if [[ "$output" == *"TUNETEST-0006"*"WARNING"* ]]; then
        echo "env override did not move pivot — expected auto-legacy skip" >&2
        return 1
    fi
}
