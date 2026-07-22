#!/usr/bin/env bash
# provenance-gate.sh — Step-0 provenance / tip-freshness gate for /dr-qa and
# /dr-compliance.
#
# Prevents false-green certification of a tree that is no longer the branch
# state (the ARAS-0033 failure: a COMPLIANT sign-off recorded against a commit
# that was later rebased away). At certification time the gate asserts:
#
#   1. The working tree is clean (`git status --porcelain` is empty).
#   2. The current tip (`git rev-parse HEAD`) equals the evidence SHA the
#      QA/compliance evidence was gathered on — supplied as an argument or read
#      from a well-known evidence-record file. A rebase, amend, or new commit
#      moves HEAD away from the recorded SHA and is therefore caught here; an
#      evidence SHA that no longer resolves (history rewritten / commit gc'd) is
#      caught too.
#
# Two modes:
#   --record   Assert a clean tree, then persist the current HEAD as the
#              evidence SHA (call at the START of a stage to pin what will be
#              certified).
#   (default)  Verify: assert a clean tree AND HEAD == the expected SHA (call
#              before writing the sign-off, and as Step 0 of a later stage that
#              must certify the same tip).
#
# Usage:
#   provenance-gate.sh --root <dir> --record (--evidence-file <path> | --task <ID>) [--stage <name>]
#   provenance-gate.sh --root <dir>          (--expected-sha <sha> | --evidence-file <path> | --task <ID>) [--stage <name>] [--allow-dirty]
#
# Evidence-file default when --task <ID> is given:
#   <root>/datarim/provenance/<TASK-ID>.sha
# (the datarim/ subtree is gitignored in Datarim-managed repos, so the record
# file never dirties the working tree).
#
# Exit codes:
#   0  gate passed
#   1  gate violation (dirty tree, tip drifted, or evidence SHA gone)
#   2  usage / environment error
#
# Security: S1 strict mode, all expansions quoted, no eval, argv validated.

set -euo pipefail

ROOT="$PWD"
MODE="verify"
EVIDENCE_FILE=""
EXPECTED_SHA=""
TASK=""
STAGE=""
ALLOW_DIRTY=0

usage_die() {
    printf 'provenance-gate: %s\n' "$*" >&2
    exit 2
}

block() {
    printf 'provenance-gate: BLOCKED — %s\n' "$*" >&2
    exit 1
}

print_usage() {
    sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) shift; [[ $# -gt 0 ]] || usage_die "--root requires a path"; ROOT="$1"; shift ;;
        --record) MODE="record"; shift ;;
        --evidence-file) shift; [[ $# -gt 0 ]] || usage_die "--evidence-file requires a path"; EVIDENCE_FILE="$1"; shift ;;
        --expected-sha) shift; [[ $# -gt 0 ]] || usage_die "--expected-sha requires a value"; EXPECTED_SHA="$1"; shift ;;
        --task) shift; [[ $# -gt 0 ]] || usage_die "--task requires an id"; TASK="$1"; shift ;;
        --stage) shift; [[ $# -gt 0 ]] || usage_die "--stage requires a value"; STAGE="$1"; shift ;;
        --allow-dirty) ALLOW_DIRTY=1; shift ;;
        --help|-h) print_usage; exit 0 ;;
        *) usage_die "unknown flag: $1" ;;
    esac
done

[[ -d "$ROOT" ]] || usage_die "root not found: $ROOT"

if [[ -n "$TASK" ]]; then
    [[ "$TASK" =~ ^[A-Z]+-[0-9]+(-[A-Za-z0-9]+)*$ ]] || usage_die "invalid task id: $TASK"
    [[ -n "$EVIDENCE_FILE" ]] || EVIDENCE_FILE="$ROOT/datarim/provenance/${TASK}.sha"
fi

git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || usage_die "not a git work tree: $ROOT"

HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" \
    || usage_die "cannot resolve HEAD in $ROOT (no commits yet?)"

# ── Clean-tree assertion (shared by both modes) ──────────────────────────────
if [[ "$ALLOW_DIRTY" -eq 0 ]]; then
    dirty="$(git -C "$ROOT" status --porcelain)"
    if [[ -n "$dirty" ]]; then
        block "working tree is not clean; commit or stash before certification:
${dirty}"
    fi
fi

stage_note=""
[[ -n "$STAGE" ]] && stage_note=" (stage ${STAGE})"

# ── Record mode ──────────────────────────────────────────────────────────────
if [[ "$MODE" == "record" ]]; then
    [[ -n "$EVIDENCE_FILE" ]] || usage_die "--record requires --evidence-file or --task"
    mkdir -p "$(dirname "$EVIDENCE_FILE")"
    printf '%s\n' "$HEAD_SHA" >"$EVIDENCE_FILE"
    printf 'provenance-gate: recorded evidence SHA %s%s -> %s\n' \
        "$HEAD_SHA" "$stage_note" "$EVIDENCE_FILE"
    exit 0
fi

# ── Verify mode ──────────────────────────────────────────────────────────────
expected=""
if [[ -n "$EXPECTED_SHA" ]]; then
    expected="$EXPECTED_SHA"
elif [[ -n "$EVIDENCE_FILE" ]]; then
    [[ -f "$EVIDENCE_FILE" ]] \
        || usage_die "evidence record not found: $EVIDENCE_FILE (run --record at stage start)"
    expected="$(head -n1 "$EVIDENCE_FILE" | tr -d '[:space:]')"
    [[ -n "$expected" ]] || usage_die "evidence record is empty: $EVIDENCE_FILE"
else
    usage_die "verify mode requires --expected-sha, --evidence-file, or --task"
fi

expected_full="$(git -C "$ROOT" rev-parse --verify --quiet "${expected}^{commit}" 2>/dev/null)" \
    || block "evidence SHA ${expected} no longer resolves in ${ROOT} — history was rewritten (rebase/amend) or the commit was garbage-collected"

if [[ "$HEAD_SHA" != "$expected_full" ]]; then
    block "branch tip moved since evidence was gathered${stage_note}:
  evidence SHA : ${expected_full}
  current HEAD : ${HEAD_SHA}
a rebase, amend, or new commit changed the tip; re-run the stage against the current tip"
fi

printf 'provenance-gate: OK — tip %s matches evidence%s, working tree clean\n' \
    "$HEAD_SHA" "$stage_note"
exit 0
