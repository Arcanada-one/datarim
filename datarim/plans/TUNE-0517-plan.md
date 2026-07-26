# Vendor-Default Model and Latest CLI-Agent Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `executing-plans` to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Follow current CLI-agent vendor defaults and prefer current stable
CLI versions without adding a gate or guessing model IDs.

**Architecture:** The canonical rule lives in
`skills/datarim-system/model-assignment.md`; consumer surfaces cross-link it.
Model tiers use `vendor-default` semantics. Fleet selection keeps binary
presence as its only availability gate and adds an optional diagnostic that
cannot affect selection.

**Tech Stack:** Markdown policy, YAML configuration, Bash, bats-core.

---

## Decisions

- No matching sibling archive landed after initialization.
- The stale concrete pins and dangling reference were confirmed before edits.
- The requested vendor-documentation connector was unavailable. Per the brief,
  semantic `vendor-default` values replace guessed model IDs.
- The version diagnostic is opt-in, local-only, and advisory. It does not query
  a registry or claim that a newer version exists.

## Component Breakdown

| File | Responsibility |
|------|----------------|
| `skills/datarim-system/model-assignment.md` | Canonical runtime policy |
| `config/model-tiers.yaml` | Semantic tier mappings |
| `CLAUDE.md` | Source-of-truth pointer |
| `commands/dr-orchestrate.md` | Fleet policy pointer |
| `skills/autonomous-mode/SKILL.md` | Pre-resolved model decision |
| `plugins/dr-orchestrate/scripts/subagent_resolver.sh` | Optional hint |
| `tests/tune-0517-vendor-default-policy.bats` | Regression contract |

## Security Summary

The changed runtime surface executes only a locally resolved CLI with
`--version`, after presence succeeds and only under explicit opt-in. Probe
output is bounded to one line. Failures are discarded. No install, network
query, privilege escalation, secret access, backend reorder, or exit-status
dependency is introduced.

## Implementation Steps

### Task 1: Lock the policy contract with failing tests

- [ ] Add presence assertions for canonical wording, cross-links, semantic
  mappings, autonomous pre-resolution, and fail-open behavior.
  **Verifies: V-AC-1, V-AC-2, V-AC-3, V-AC-4, V-AC-5, V-AC-6**
- [ ] Run `bats tests/tune-0517-vendor-default-policy.bats`; confirm the policy
  cases fail before implementation. **Verifies: V-AC-7**

### Task 2: Add policy and semantic mappings

- [ ] Add current vendor-default model and effort policy, deliberate pin
  exception, permission-aware CLI upgrade guidance, and the scoped
  project-dependency cross-link. **Verifies: V-AC-1, V-AC-2**
- [ ] Replace concrete provider IDs with four `vendor-default` tier selections,
  explicitly define omit-the-model-override adapter behavior, preserve
  `runtime_default: inherit`, and repair the dangling reference.
  **Verifies: V-AC-5**
- [ ] Add concise CLAUDE, orchestration, and auto-mode pointers without
  duplicating policy or changing routing. **Verifies: V-AC-4, V-AC-6**

### Task 3: Add optional fleet version diagnostics

- [ ] Add an opt-in helper that invokes `--version`, emits one advisory line on
  success, and returns success for all outcomes. **Verifies: V-AC-3**
- [ ] Invoke it only after presence succeeds and ignore its return status.
  Verify disabled, success, and failed-probe cases. **Verifies: V-AC-3, V-AC-7**

### Task 4: Verify and ship

- [ ] Run focused bats, Bash syntax, shellcheck, YAML parsing, framework
  validation, and the full bats suite. **Verifies: V-AC-7, V-AC-8**
- [ ] Scan added shipped lines for non-ASCII and prohibited operator literals.
  **Verifies: V-AC-8**
- [ ] Sign and push each lifecycle checkpoint, then archive the task.
  **Verifies: V-AC-8**

## Test Plan

- Focused contract: `bats tests/tune-0517-vendor-default-policy.bats`
- Fleet regression: `bats plugins/dr-orchestrate/tests/test_fleet_selector.bats`
- Syntax: `bash -n plugins/dr-orchestrate/scripts/subagent_resolver.sh`
- Changed shell: `shellcheck -x -P plugins/dr-orchestrate/scripts
  plugins/dr-orchestrate/scripts/subagent_resolver.sh`
- Framework: `./validate.sh`
- Full regression: `bats tests plugins/dr-orchestrate/tests`

## Rollback Strategy

Revert the feature commit on this branch, rerun the focused contract to confirm
the policy assertions fail again, then push the revert. No data migration,
deployment, or external-state rollback is required.

## Validation Checklist

- [ ] **V-AC-1:** Canonical policy follows vendor-default model and effort,
  permits a reasoned deliberate pin, and treats stale pins as bugs.
- [ ] **V-AC-2:** CLI-version guidance is permission-aware and non-blocking.
- [ ] **V-AC-3:** Version diagnostics are optional, fail-open, and
  selection-neutral.
- [ ] **V-AC-4:** Auto-mode pre-resolves model and effort selection.
- [ ] **V-AC-5:** Four tiers use `vendor-default` selection with
  omit-the-model-override adapter behavior,
  `runtime_default: inherit` remains, and the dangling reference is absent.
- [ ] **V-AC-6:** Consumer surfaces point to the canonical policy.
- [ ] **V-AC-7:** Focused policy and fleet tests pass.
- [ ] **V-AC-8:** Full validation, hygiene, signing, push, and archive pass.

## Out of Scope

- Project dependency selection, concrete generation IDs, forced upgrades,
  routing or exit-code changes, public release, and production deploy.
- Site data sync: skip - internal policy and mechanics change; confirm during
  compliance.

## Next Steps

Execute `/dr-do TUNE-0517` with TDD.
