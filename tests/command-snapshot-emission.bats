#!/usr/bin/env bats
#
# Command-bound snapshot emission directive wiring.
#
# Architectural decision: the snapshot-emission contract is bound to the
# COMMAND file (which owns the stage), not the agent file (reused across
# stages). Each CTA-emitting `commands/dr-*.md` declares a
# `## Stage Snapshot Emission` section carrying (a) a reference to the
# canonical recipe in `skills/cta-format/SKILL.md` § Snapshot Emission,
# (b) the literal stage value, and (c) the literal command value. The writer
# recipe body lives in `skills/cta-format/SKILL.md` (single source of truth).
#
# Checks 1-3 loop over COMMAND_PAIRS, so registering a new emitting command is
# a single-line edit. AC-1 pins the canonical emitter count and keeps
# COMMAND_PAIRS in sync with the on-disk stage declarations. The drift-guard
# asserts every `stage` declared across `commands/dr-*.md` is a member of
# SNAPSHOT_STAGE_RE read live from `scripts/lib/snapshot-writer.sh` — catching
# the class of bug where a command declares a stage the writer enum rejects.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

# Stage-to-command mapping (bash 3.2 compatible — no associative arrays).
# Format: <basename>|<stage-literal>|<command-literal>
COMMAND_PAIRS=(
    "dr-init|init|/dr-init"
    "dr-prd|prd|/dr-prd"
    "dr-plan|plan|/dr-plan"
    "dr-design|design|/dr-design"
    "dr-do|do|/dr-do"
    "dr-qa|qa|/dr-qa"
    "dr-compliance|compliance|/dr-compliance"
    "dr-auto|auto|/dr-auto"
)

# Canonical count of snapshot-emitting commands. dr-auto emits `stage: auto`.
EXPECTED_EMITTER_COUNT=8

# ---------- Check 1: section header present in every emitting command ----------

@test "every emitting command carries '## Stage Snapshot Emission' section" {
    for pair in "${COMMAND_PAIRS[@]}"; do
        base="${pair%%|*}"
        run grep -F '## Stage Snapshot Emission' "${REPO_ROOT}/commands/${base}.md"
        [ "$status" -eq 0 ] || { echo "missing '## Stage Snapshot Emission' in ${base}.md"; return 1; }
    done
}

# ---------- Check 2: literal stage value bound per command ----------

@test "every emitting command binds its literal stage value" {
    for pair in "${COMMAND_PAIRS[@]}"; do
        base="${pair%%|*}"
        rest="${pair#*|}"
        stage="${rest%%|*}"
        run grep -E "^- \`stage\`: \`${stage}\`$" "${REPO_ROOT}/commands/${base}.md"
        [ "$status" -eq 0 ] || { echo "missing stage literal '${stage}' in ${base}.md"; return 1; }
    done
}

# ---------- Check 3: reference to canonical recipe in cta-format.md ----------

@test "every emitting command references cta-format.md § Snapshot Emission" {
    for pair in "${COMMAND_PAIRS[@]}"; do
        base="${pair%%|*}"
        run grep -F 'skills/cta-format/SKILL.md` § Snapshot Emission' "${REPO_ROOT}/commands/${base}.md"
        [ "$status" -eq 0 ] || { echo "missing cta-format recipe reference in ${base}.md"; return 1; }
    done
}

# ---------- AC-1 aggregate gate ----------

@test "AC-1 — on-disk stage declarations match the canonical emitter count" {
    count="$(grep -lE '^- `stage`: `[a-z]+`$' "${REPO_ROOT}/commands/"dr-*.md | wc -l | tr -d ' ')"
    [ "$count" -eq "$EXPECTED_EMITTER_COUNT" ] || { echo "expected ${EXPECTED_EMITTER_COUNT} stage-declaring commands, found ${count}"; return 1; }
}

@test "AC-1 — COMMAND_PAIRS length matches the canonical emitter count" {
    [ "${#COMMAND_PAIRS[@]}" -eq "$EXPECTED_EMITTER_COUNT" ]
}

@test "AC-1 — cta-format.md carries write_stage_snapshot recipe (>=1 hit)" {
    count="$(grep -c 'write_stage_snapshot' "${REPO_ROOT}/skills/cta-format/SKILL.md" || true)"
    [ "$count" -ge 1 ]
}

# ---------- Drift-guard: command-declared stage is a writer-enum member ----------

@test "drift-guard — every command-declared stage is a member of SNAPSHOT_STAGE_RE" {
    stage_re="$(grep -E '^readonly SNAPSHOT_STAGE_RE=' "${REPO_ROOT}/scripts/lib/snapshot-writer.sh" \
        | sed -E "s/.*SNAPSHOT_STAGE_RE='([^']*)'.*/\1/")"
    [ -n "$stage_re" ] || { echo "could not read SNAPSHOT_STAGE_RE from snapshot-writer.sh"; return 1; }

    declared_any=0
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        declared_any=1
        stage="$(printf '%s\n' "$line" | sed -E 's/.*`stage`: `([a-z]+)`.*/\1/')"
        [[ "$stage" =~ $stage_re ]] || { echo "command-declared stage '${stage}' is not in SNAPSHOT_STAGE_RE (${stage_re})"; return 1; }
    done < <(grep -hE '^- `stage`: `[a-z]+`$' "${REPO_ROOT}/commands/"dr-*.md)

    [ "$declared_any" -eq 1 ] || { echo "no stage declarations found — drift-guard would be a no-op"; return 1; }
}
