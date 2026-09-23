#!/usr/bin/env bats

setup() {
  FRAMEWORK_ROOT="${BATS_TEST_DIRNAME}/.."
  SECURITY_SKILL="$FRAMEWORK_ROOT/skills/security/SKILL.md"
}

@test "sensitive source classification is checked before source inspection" {
  grep -qF 'Consult existing source classifications before opening or searching task files.' "$SECURITY_SKILL"
}

@test "sensitive context handoff binds the sanitized source and protected constraints" {
  grep -qF 'approved sanitized path, immutable original source pin, sanitized digest' "$SECURITY_SKILL" \
    && grep -qF 'omission/redaction constraints' "$SECURITY_SKILL"
}

@test "missing or stale sanitized context blocks the affected read" {
  grep -qF 'If the approved copy, pin or constraints are missing or stale, STOP the affected read' "$SECURITY_SKILL"
}

@test "reasoning cannot consume raw sources and redact after exposure" {
  grep -qF 'Reason only over the approved sanitized copy.' "$SECURITY_SKILL" \
    && grep -qF 'MUST NOT enter model context through reads, grep/diff output, quotations or delegation' "$SECURITY_SKILL" \
    && grep -qF 'redact later is not a recovery strategy for context exposure' "$SECURITY_SKILL"
}

@test "original reconstruction is bounded controller-only with metadata output" {
  grep -qF 'authorized controller-only bounded read' "$SECURITY_SKILL" \
    && grep -qF 'metadata-only output' "$SECURITY_SKILL" \
    && grep -qF 'never in LLM context, model mounts or worker mounts' "$SECURITY_SKILL"
}

@test "context protection does not grant repair or external action authority" {
  grep -qF 'does not authorize repairs, credential changes or external actions' "$SECURITY_SKILL"
}

@test "source-reading roles load the canonical rule before direct source reads" {
  local role context
  for role in developer reviewer security devops sre tester researcher code-simplifier compliance architect; do
    context="$(awk '/\*\*Context Loading\*\*/ { found=1; next } found && /^- READ:/ { exit } found { print }' "$FRAMEWORK_ROOT/agents/$role.md")"
    [[ "$context" == *'including direct invocation'* ]] \
      && [[ "$context" == *'MUST LOAD'* ]] \
      && [[ "$context" == *'${DATARIM_RUNTIME:?}/skills/security/SKILL.md'* ]] \
      && [[ "$context" == *'Sensitive source context boundary'* ]] || return 1
  done
}

@test "task constraints carry the metadata-only sanitized binding via the canonical rule" {
  local constraints
  constraints="$(sed -n '/^## Constraints$/,/^## Out of Scope$/p' "$FRAMEWORK_ROOT/templates/task-template.md")"
  [[ "$constraints" == *'metadata-only sanitized binding'* ]] \
    && [[ "$constraints" == *'approved sanitized path, original source pin, sanitized digest'* ]] \
    && [[ "$constraints" == *'omission/redaction constraints'* ]] \
    && [[ "$constraints" == *'${DATARIM_RUNTIME:?}/skills/security/SKILL.md'* ]]
}

@test "prework pins source constraints prospectively without retroactive compliance claims" {
  local prework
  prework="$(sed -n '/^## U3\./,/^## U4\./p' "$FRAMEWORK_ROOT/skills/customer-delivery/SKILL.md")"
  [[ "$prework" == *'existing constraints/policies selection'* ]] \
    && [[ "$prework" == *'before future affected reads or work'* ]] \
    && [[ "$prework" == *'does not establish retroactive pre-work compliance'* ]] \
    && [[ "$prework" == *'Sensitive source context boundary'* ]]
}

@test "session protected Layer 1 preserves sanitized source bindings without copying original values" {
  local related
  related="$(sed -n '/^## Layer 1 /,/^## Layer 2 /p' "$FRAMEWORK_ROOT/skills/session-handoff-writer/SKILL.md")"
  [[ "$related" == *'approved sanitized path, original source pin, sanitized digest'* ]] \
    && [[ "$related" == *'omission/redaction constraints'* ]] \
    && [[ "$related" == *'metadata only, never original values'* ]] \
    && [[ "$related" == *'${DATARIM_RUNTIME:?}/skills/security/SKILL.md'* ]]
}

@test "isolated peer reviewer requires a sanitized binding before source reads" {
  local peer="$FRAMEWORK_ROOT/agents/peer-reviewer.md"
  grep -qF 'Before source reads or delegation (including direct invocation), MUST LOAD' "$peer" \
    && grep -qF '${DATARIM_RUNTIME:?}/skills/security/SKILL.md' "$peer" \
    && grep -qF 'classification, approved sanitized path, immutable original source pin, sanitized digest' "$peer" \
    && grep -qF 'STOP the affected read' "$peer"
}

@test "session replay verifies bindings under the security rule before content probes" {
  local preprobe
  preprobe="$(sed -n '/^## Re-verification protocol/,/^\*\*Probe 1/p' "$FRAMEWORK_ROOT/skills/session-handoff-replay/SKILL.md")"
  [[ "$preprobe" == *'Before content probes or diffs, MUST LOAD'* ]] \
    && [[ "$preprobe" == *'${DATARIM_RUNTIME:?}/skills/security/SKILL.md'* ]] \
    && [[ "$preprobe" == *'verify the sanitized path, original source pin, sanitized digest and constraints'* ]] \
    && [[ "$preprobe" == *'missing, stale or truncated'* ]] \
    && [[ "$preprobe" == *'STOP the affected probe'* ]]
}
