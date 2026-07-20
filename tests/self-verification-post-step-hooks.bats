#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SKILL="$REPO_ROOT/skills/self-verification/SKILL.md"
  MANUAL="$REPO_ROOT/commands/dr-verify.md"
  SHIPPED_PATHS=(
    commands/dr-prd.md
    commands/dr-plan.md
    commands/dr-do.md
    commands/dr-verify.md
    skills/self-verification/SKILL.md
    agents/reviewer.md
    CLAUDE.md
    README.md
    documentation/tutorials/getting-started.md
    documentation/explanation/pipeline.md
    documentation/reference/commands.md
    documentation/reference/skills.md
  )
}

@test "V-AC-01: PRD has exactly one automatic post-step call" {
  [ "$(grep -cF 'AUTOMATIC POST-STEP SELF-VERIFICATION' "$REPO_ROOT/commands/dr-prd.md")" -eq 1 ]
}

@test "V-AC-01: plan has exactly one automatic post-step call" {
  [ "$(grep -cF 'AUTOMATIC POST-STEP SELF-VERIFICATION' "$REPO_ROOT/commands/dr-plan.md")" -eq 1 ]
}

@test "V-AC-01: do has exactly one automatic post-step call" {
  [ "$(grep -cF 'AUTOMATIC POST-STEP SELF-VERIFICATION' "$REPO_ROOT/commands/dr-do.md")" -eq 1 ]
}

@test "V-AC-01: every call follows spec validation and precedes CTA and snapshot" {
  local file spec qend hook cta snapshot
  for file in commands/dr-prd.md commands/dr-plan.md commands/dr-do.md; do
    spec="$(grep -nF 'AUTOMATIC SPEC-GRAPH' "$REPO_ROOT/$file" | tail -1 | cut -d: -f1)"
    case "$file" in
      commands/dr-prd.md|commands/dr-plan.md)
        qend="$(grep -nF 'Utility exit 0 = appended' "$REPO_ROOT/$file" | tail -1 | cut -d: -f1)"
        ;;
      commands/dr-do.md)
        qend="$(grep -nF 'Missing append triggers' "$REPO_ROOT/$file" | tail -1 | cut -d: -f1)"
        ;;
    esac
    hook="$(grep -nF 'AUTOMATIC POST-STEP SELF-VERIFICATION' "$REPO_ROOT/$file" | cut -d: -f1)"
    cta="$(grep -nE '^## Next Steps \(CTA\)$' "$REPO_ROOT/$file" | cut -d: -f1)"
    snapshot="$(grep -nE '^## Stage Snapshot Emission' "$REPO_ROOT/$file" | cut -d: -f1)"
    [ -n "$spec" ] && [ -n "$qend" ] && [ -n "$hook" ] && [ -n "$cta" ] && [ -n "$snapshot" ] \
      && [ "$spec" -lt "$hook" ] && [ "$qend" -lt "$hook" ] && [ "$hook" -lt "$cta" ] && [ "$cta" -lt "$snapshot" ] || return 1
    [ "$(grep -cF '§ Automatic post_step profile' "$REPO_ROOT/$file")" -eq 1 ] || return 1
  done
}

@test "V-AC-02: L1 returns before floor and creates no automatic audit" {
  grep -Fq 'L1 | no | none | return without floor, audit, or model dispatch' "$SKILL"
}

@test "V-AC-03: L2 required role set is exactly peer-reviewer" {
  [ "$(grep -cF 'L2 | yes | `peer-reviewer` | exactly one clean-context worker' "$SKILL")" -eq 1 ] \
    && grep -Fq 'No separate peer-review layer or fourth model worker runs in the automatic profile' "$SKILL"
}

@test "V-AC-04: L3 and L4 retain the three-role nominal profile" {
  [ "$(grep -cF 'L3/L4 | yes | `reviewer`, `tester`, `security` | exactly three independent workers in parallel' "$SKILL")" -eq 1 ] \
    && grep -Fq 'No separate peer-review layer or fourth model worker runs in the automatic profile' "$SKILL"
}

@test "V-AC-04: automatic aggregation is all-settled with no single-prompt parity claim" {
  grep -Fq 'all-settled' "$SKILL" \
    && grep -Fq 'one failure does not cancel or erase validated findings from completed peers' "$SKILL" \
    && grep -Fq 'A single prompt is not three independent roles' "$SKILL" \
    && grep -Fq '600-second deadline per role and a 660-second aggregate deadline' "$SKILL" \
    && grep -Fq 'cancel or detach overdue handles' "$SKILL"
}

@test "V-AC-05: blocking floor findings fail fast before model dispatch" {
  grep -Fq 'A blocking floor finding fails fast before model dispatch' "$SKILL" \
    && grep -Fq 'launches no workers' "$SKILL"
}

@test "V-AC-04: selected bundle budget is reserved before any launch" {
  grep -Fq 'self-verify-degradation-policy.sh' "$SKILL" \
    && grep -Fq 'Reserve the selected bundle atomically before launch' "$SKILL" \
    && grep -Fq 'No fourth worker may consume the reservation' "$SKILL"
}

@test "V-AC-06: manual command keeps its public option set and full three layers" {
  grep -Fq -- '--stage={prd,plan,do,all}' "$MANUAL" \
    && grep -Fq -- '--max-iter=N' "$MANUAL" \
    && grep -Fq -- '--peer-provider={sonnet,haiku,opus,none}' "$MANUAL" \
    && grep -Fq -- '--no-fix' "$MANUAL" \
    && grep -Fq -- '--runtime={claude,codex}' "$MANUAL" \
    && grep -Fq -- '--external-verifier=PASS' "$MANUAL" \
    && grep -Fq -- '--cost-cap=N' "$MANUAL" \
    && grep -Fq 'optional, default 3' "$MANUAL" \
    && grep -Fq -- '--floor-only' "$MANUAL" \
    && grep -Fq 'Layer 1 — Deterministic floor' "$MANUAL" \
    && grep -Fq 'Layer 2 — Provider resolution + cross-model peer-review' "$MANUAL" \
    && grep -Fq 'Layer 3 — Native runtime dispatch' "$MANUAL" \
    && grep -Fq 'resolve-peer-provider.sh' "$MANUAL" \
    && grep -Fq 'WRITE AUDIT LOG' "$MANUAL" \
    && grep -Fq 'CTA per `cta-format.md`' "$MANUAL" \
    && ! grep -Fq 'Stage Snapshot Emission' "$MANUAL"
}

@test "V-AC-06: manual command exposes no automatic-hook flag" {
  ! grep -Eq -- '--(auto-hook|post-step|post_step)' "$MANUAL"
}

@test "V-AC-07: every incomplete reason is explicit" {
  grep -Fq 'missing or malformed complexity, missing or duplicate role identity, timeout, provider failure, malformed output, unsupported runtime, invalid budget evidence, degradation evaluation failure, missing or invalid budget reservation, cost exhaustion, recursive invocation, auto-fix transaction uncertainty, or audit persistence failure' "$SKILL" \
    && grep -Fq 'Every listed reason sets `execution_status: incomplete`' "$SKILL"
}

@test "V-AC-07: incomplete execution cannot PASS or advance" {
  grep -Fq 'PASS requires `execution_status: complete`' "$SKILL" \
    && grep -Fq '`execution_status: incomplete` always selects a non-advancing route' "$SKILL"
}

@test "V-AC-08: workers are one-pass findings-only and parent owns output" {
  grep -Fq 'one pass and findings-only' "$SKILL" \
    && grep -Fq 'no mutation, network, stage-command, nested-agent, audit-write, CTA, or snapshot authority' "$SKILL" \
    && grep -Fq 'Only the parent stage writes the audit, selects the CTA, and emits the terminal snapshot' "$SKILL"
}

@test "V-AC-08: capability and evidence preflights fail closed" {
  grep -Fq 'the parent performs a capability preflight' "$SKILL" \
    && grep -Fq 'launch none and record `unsupported runtime`' "$SKILL" \
    && grep -Fq 'The parent creates an evidence manifest before dispatch' "$SKILL" \
    && grep -Fq 'never shell-evaluate reviewer text' "$SKILL"
}

@test "V-AC-09: automatic audit namespace includes mode and invocation identity" {
  grep -Fq 'verify-{TASK-ID}-{stage}-post-step-{invocation_id}.md' "$SKILL" \
    && grep -Fq 'Reserve a separate invocation claim with exclusive creation' "$SKILL" \
    && grep -Fq 'with a no-replace primitive' "$SKILL" \
    && grep -Fq 'apply `chmod a-w` to the temporary file' "$SKILL" \
    && grep -Fq 'release the task-stage lock, then atomically publish' "$SKILL" \
    && grep -Fq 'All result-affecting cleanup occurs before publication' "$SKILL" \
    && grep -Fq 'best-effort orphan housekeeping, not a result-affecting step' "$SKILL" \
    && grep -Fq 'If any pre-publication or publish step fails, no final audit is claimed' "$SKILL" \
    && grep -Fq 'dispatch handles, budget reservation/consumption estimates' "$SKILL"
}

@test "V-AC-03: canonical peer-reviewer role identifier is consistent" {
  grep -Fq 'canonical `peer-reviewer` role' "$REPO_ROOT/agents/peer-reviewer.md" \
    && grep -Fq 'agent_origin: peer-reviewer | reviewer | tester | security' "$SKILL" \
    && ! grep -Rq 'peer_reviewer' "$REPO_ROOT/agents/peer-reviewer.md" "$SKILL"
}

@test "V-AC-09: recursive automatic entry is guarded and cleaned up" {
  grep -Fq 'active-invocation key `{TASK-ID}:{stage}:post_step`' "$SKILL" \
    && grep -Fq 'Re-entry while that key is active launches no work' "$SKILL" \
    && grep -Fq 'clear the key in a finally-equivalent cleanup path' "$SKILL"
}

@test "V-AC-07: every stage routing table gives incomplete and blocked precedence" {
  local file
  for file in commands/dr-prd.md commands/dr-plan.md commands/dr-do.md; do
    grep -Fq 'execution_status: incomplete` or verdict `BLOCKED`' "$REPO_ROOT/$file" \
      && grep -Fq 'overrides every normal advancing route' "$REPO_ROOT/$file" \
      || return 1
  done
}

@test "V-AC-09: do context does not require a QA report" {
  grep -Fq 'first persist the current implementation notes and executable evidence' "$REPO_ROOT/commands/dr-do.md" \
    && grep -Fq 'Only after that write succeeds' "$REPO_ROOT/commands/dr-do.md" \
    && grep -Fq 'A QA report is optional' "$REPO_ROOT/commands/dr-do.md"
}

@test "V-AC-10: stale manual-only and coworker semantic-review claims are removed" {
  ! grep -Eqi 'manual on-demand only|automated post-step hook is a separate future evolution|pre-emptive verify hook is a deferred future evolution|DeepSeek default|DeepSeek via coworker|vendor-neutral via coworker abstraction' "${SHIPPED_PATHS[@]/#/$REPO_ROOT/}"
}

@test "V-AC-10: every exact shipped surface changes from the stacked parent" {
  local file
  for file in "${SHIPPED_PATHS[@]}"; do
    git -C "$REPO_ROOT" diff --quiet a46872d -- "$file" && return 1
  done
  return 0
}

@test "TUNE-0140: automatic profile orders floor, guarded auto-fix, then reviewers" {
  grep -Fq 'deterministic floor → guarded auto-fix loop → model reviewer dispatch' "$SKILL" \
    && grep -Fq 'self-verify-auto-fix.sh' "$SKILL"
}

@test "TUNE-0140: every parent stage names the guarded runner in its post-step contract" {
  local file
  for file in commands/dr-prd.md commands/dr-plan.md commands/dr-do.md; do
    grep -Fq 'self-verify-auto-fix.sh' "$REPO_ROOT/$file" \
      && grep -Fq 'one finding, then rerun the stage validators and deterministic floor' "$REPO_ROOT/$file" \
      || return 1
  done
}

@test "TUNE-0140: mutation loop is bounded and refreshes stale preimages" {
  grep -Fq '32 total runner invocations' "$SKILL" \
    && grep -Fq 'Never select a second finding from a pre-mutation floor result' "$SKILL" \
    && grep -Fq 'attempted-finding set for that unchanged floor generation' "$SKILL"
}

@test "TUNE-0140: history authority cannot be supplied by a finding or caller" {
  grep -Fq 'datarim/qa/self-verification-auto-fix-history/records/' "$SKILL" \
    && grep -Fq 'cannot substitute a history path' "$SKILL" \
    && grep -Fq 'strict `10 * false_positive < 3 * total`' "$SKILL"
}

@test "TUNE-0140: original finding and every runner result remain audit-visible" {
  grep -Fq 'retain every original floor finding unchanged' "$SKILL" \
    && grep -Fq 'one structured result for every runner invocation' "$SKILL" \
    && grep -Fq '`auto_fix_applied` is a derived count' "$SKILL"
}

@test "TUNE-0140: transaction uncertainty is incomplete and non-advancing" {
  grep -Fq 'rollback_integrity_failure' "$SKILL" \
    && grep -Fq 'journal_conflict' "$SKILL" \
    && grep -Fq 'transaction persistence uncertainty' "$SKILL" \
    && grep -Fq 'launch no model reviewers and take the parent non-advancing route' "$SKILL"
}

@test "TUNE-0140: peer reviewer prose never becomes executable authority" {
  grep -Fq 'Reviewer prose is never executable authority' "$REPO_ROOT/agents/peer-reviewer.md" \
    && grep -Fq 'cannot invoke the deterministic auto-fix runner' "$REPO_ROOT/agents/peer-reviewer.md"
}

@test "TUNE-0140: manual verify remains findings-only and cannot invoke runner" {
  grep -Fq 'Manual `/dr-verify` remains findings-only' "$MANUAL" \
    && ! grep -Fq 'self-verify-auto-fix.sh' "$MANUAL"
}

@test "TUNE-0140: root documentation distinguishes automatic auto-fix from manual findings-only" {
  grep -Fq 'strictly below 30%' "$REPO_ROOT/CLAUDE.md" \
    && grep -Fq 'manual `/dr-verify` remains findings-only' "$REPO_ROOT/CLAUDE.md" \
    && grep -Fq 'strictly below 30%' "$REPO_ROOT/README.md" \
    && grep -Fq 'Manual `/dr-verify` never auto-fixes' "$REPO_ROOT/README.md"
}

@test "TUNE-0140: tutorial and pipeline explanation document visible audit results" {
  grep -Fq 'Guarded automatic fixes' "$REPO_ROOT/documentation/tutorials/getting-started.md" \
    && grep -Fq 'Every attempted result remains visible in the immutable verification audit' "$REPO_ROOT/documentation/tutorials/getting-started.md" \
    && grep -Fq 'Guarded auto-fix boundary' "$REPO_ROOT/documentation/explanation/pipeline.md" \
    && grep -Fq 'reruns the validators and floor after each mutation' "$REPO_ROOT/documentation/explanation/pipeline.md"
}

@test "TUNE-0140: command and skill references expose the same bounded policy" {
  grep -Fq 'guarded deterministic auto-fix' "$REPO_ROOT/documentation/reference/commands.md" \
    && grep -Fq 'manual `/dr-verify` remains findings-only' "$REPO_ROOT/documentation/reference/commands.md" \
    && grep -Fq 'strictly below 30%' "$REPO_ROOT/documentation/reference/skills.md" \
    && grep -Fq 'fixed immutable history namespace' "$REPO_ROOT/documentation/reference/skills.md"
}

@test "TUNE-0139: automatic L3/L4 profiles use the fixed omission lattice" {
  grep -Fq '`full -> deep_only -> floor_only`' "$SKILL" \
    && grep -Fq 'omit `multi_vote_adversarial` first' "$SKILL" \
    && grep -Fq 'then omit `deep_cross_artifact`' "$SKILL" \
    && grep -Fq 'The deterministic floor is never omitted' "$SKILL"
}

@test "TUNE-0139: floor auto-fix refresh policy reservation dispatch and audit stay ordered" {
  grep -Fq 'floor -> guarded auto-fix -> validator/floor refresh -> degradation decision -> atomic reservation -> selected dispatch -> immutable audit' "$SKILL" \
    && grep -Fq 'Never evaluate a pre-mutation ledger or stale floor generation' "$SKILL"
}

@test "TUNE-0139: parent owns digest sequence lock recheck and reservation race" {
  grep -Fq 'expected_sequence = previous_sequence + 1' "$SKILL" \
    && grep -Fq 'freeze the ledger digest under the same task-stage lock' "$SKILL" \
    && grep -Fq 'recheck the digest, sequence, and remaining budget while still holding the lock immediately before dispatch' "$SKILL" \
    && grep -Fq 'Exactly one competing reservation may win' "$SKILL"
}

@test "TUNE-0139: invalid policy execution is audited incomplete without reactive downgrade" {
  grep -Fq 'nonzero exit, signal termination, empty stdout, malformed JSON, or missing required decision field' "$SKILL" \
    && grep -Fq 'parent-synthesized redacted `incomplete` decision' "$SKILL" \
    && grep -Fq 'never retry a weaker profile after a worker or provider failure' "$SKILL"
}

@test "TUNE-0139: stage commands carry identical stage-bound callouts" {
  local file stage
  for file in commands/dr-prd.md commands/dr-plan.md commands/dr-do.md; do
    stage="${file#commands/dr-}"
    stage="${stage%.md}"
    grep -Fq "self-verify-degradation-policy.sh\` with \`stage=$stage\`" "$REPO_ROOT/$file" \
      && grep -Fq 'automatic L3/L4 only' "$REPO_ROOT/$file" \
      && grep -Fq 'deterministic floor remains mandatory' "$REPO_ROOT/$file" \
      || return 1
  done
}

@test "TUNE-0139: L1 L2 and manual verification never use degradation policy" {
  grep -Fq 'L1 and L2 never invoke the degradation evaluator' "$SKILL" \
    && grep -Fq 'Manual `/dr-verify` never invokes `self-verify-degradation-policy.sh`' "$SKILL" \
    && grep -Fq 'cost-adaptive automatic profile does not apply' "$MANUAL"
}

@test "TUNE-0139: canonical deep-only role remains read-only reviewer" {
  grep -Fq 'canonical automatic `deep_only` role' "$REPO_ROOT/agents/reviewer.md" \
    && grep -Fq 'budget evidence or select a degradation profile' "$REPO_ROOT/agents/reviewer.md"
}

@test "TUNE-0139: every public surface names coverage and the hard floor" {
  local file
  for file in CLAUDE.md README.md documentation/tutorials/getting-started.md documentation/explanation/pipeline.md documentation/reference/commands.md documentation/reference/skills.md; do
    grep -Fq 'floor_only' "$REPO_ROOT/$file" \
      && grep -Fq 'deterministic floor' "$REPO_ROOT/$file" \
      && grep -Fq 'verification_coverage' "$REPO_ROOT/$file" \
      || return 1
  done
}

@test "TUNE-0139: audit records normalized decision fields without raw ledger" {
  grep -Fq 'degradation section' "$SKILL" \
    && grep -Fq '`policy_version`, `signal_source`, `signal_digest`, `signal_sequence`' "$SKILL" \
    && grep -Fq '`selected_profile`, `omitted_passes`, `trigger_axes`, and `reason_code`' "$SKILL" \
    && grep -Fq 'never persist the raw budget ledger' "$SKILL"
}
