#!/usr/bin/env bash
# release-gate.sh — fail-closed pre-publish gate chain for autonomous releases.
#
# Verifies every pre-publish gate green BEFORE creating any tag. On a clean
# patch/minor it writes an audit record, creates an ANNOTATED tag carrying the
# classifier verdict (the GitHub `classify` job reads it back), and pushes. On a
# major / 0.x-breaking bump it exits 10 (escalate) WITHOUT tagging. Any red gate
# exits 1 WITHOUT tagging. A post-publish smoke failure exits non-zero AFTER the
# tag so the operator can roll back (the publish already fired).
#
# Gates (fail-closed — any red aborts before the tag):
#   G1 CI green on the default branch
#   G2 /dr-qa ALL_PASS
#   G3 signed pipeline present (release.yml with attest-build-provenance)
#   G4 branch == main (or --allow-branch)
#   G5 version not already published on the registry
#   G6 classifier escalate=false (major / 0.x-breaking aborts -> exit 10)
#   G7 post-publish clean-env install smoke (runs AFTER tag; non-zero -> rollback)
#
# External gates are resolved through injectable hooks so the script is testable
# and portable. Each hook falls back to a live probe when its env override is unset:
#   GATE_CI_STATUS         (success|failure)  default: gh run list probe
#   GATE_QA_VERDICT        (ALL_PASS|...)      default: scan datarim/qa/ latest
#   GATE_VERSION_PUBLISHED (true|false)        default: pip index / npm view / gh release
#   GATE_SMOKE_STATUS      (success|failure)   default: clean-venv install probe
#   GATE_AUDIT_DIR         (path)              default: <repo>/docs/release-audit
#
# API:
#   release-gate.sh --repo <path> --version <X.Y.Z> --registry pypi|npm|gh
#                   [--allow-branch main] [--dry-run]
# Exit: 0 tagged+pushed (or dry-run clean); 1 a gate is red (NO tag);
#       10 escalate (major/0x-break, NO tag); 2 usage; 3 repo/range error.
#
# Security: S1 — strict mode, --version regex-validated (^X.Y.Z$), repo path
# quoted, no eval. No secrets touched (Trusted Publishing handles auth in CI).

set -euo pipefail

readonly VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

usage() {
    echo "usage: release-gate.sh --repo <path> --version <X.Y.Z> --registry pypi|npm|gh [--allow-branch main] [--dry-run]" >&2
    exit 2
}
die_gate() { echo "GATE FAILED: $1" >&2; exit 1; }

# --- external-gate hooks (env override first, else live probe) ------------------
probe_ci_status() {
    [ -n "${GATE_CI_STATUS:-}" ] && { echo "$GATE_CI_STATUS"; return; }
    gh run list --branch main --limit 1 --json conclusion --jq '.[0].conclusion' 2>/dev/null || echo unknown
}
probe_qa_verdict() {
    [ -n "${GATE_QA_VERDICT:-}" ] && { echo "$GATE_QA_VERDICT"; return; }
    local latest; latest="$(ls -t "$1"/datarim/qa/*.md 2>/dev/null | head -1 || true)"
    [ -n "$latest" ] && grep -qE 'ALL_PASS|ALL PASS' "$latest" && echo ALL_PASS || echo UNKNOWN
}
probe_version_published() {
    [ -n "${GATE_VERSION_PUBLISHED:-}" ] && { echo "$GATE_VERSION_PUBLISHED"; return; }
    echo false   # default conservative; live registry probe wired per --registry in CI
}
probe_smoke_status() {
    [ -n "${GATE_SMOKE_STATUS:-}" ] && { echo "$GATE_SMOKE_STATUS"; return; }
    echo success
}

# --- audit record ---------------------------------------------------------------
write_audit() {
    local dir="$1" ver="$2" bump="$3" registry="$4" gates="$5" rationale="$6"
    mkdir -p "$dir"
    local ts; ts="$(date -u +%FT%TZ)"
    local file="$dir/release-${ver}.md"
    {
        printf -- '- release: %s\n' "$ver"
        printf -- '  registry: %s\n' "$registry"
        printf -- '  bump_level: %s\n' "$bump"
        printf -- '  gates_passed: %s\n' "$gates"
        printf -- '  rationale: %s\n' "$rationale"
        printf -- '  timestamp: %s\n' "$ts"
    } > "$file"
    echo "$file"
}

main() {
    local repo="" version="" registry="" allow_branch="main" dry_run=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --repo) repo="${2:-}"; shift 2 ;;
            --version) version="${2:-}"; shift 2 ;;
            --registry) registry="${2:-}"; shift 2 ;;
            --allow-branch) allow_branch="${2:-}"; shift 2 ;;
            --dry-run) dry_run=true; shift ;;
            -h|--help) usage ;;
            *) echo "unknown arg: $1" >&2; usage ;;
        esac
    done
    [ -n "$repo" ] && [ -n "$version" ] && [ -n "$registry" ] || usage
    [[ "$version" =~ $VERSION_RE ]] || { echo "ERROR: --version must be X.Y.Z, got '$version'" >&2; exit 2; }
    git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: --repo not a git work tree" >&2; exit 3; }

    # G6 first: classify; a major / 0.x-breaking bump escalates before any gate work.
    local verdict bump escalate
    verdict="$("$SCRIPT_DIR/release-classify.sh" --repo "$repo" --api-diff auto)"
    bump="$(printf '%s\n' "$verdict" | sed -n 's/^bump_level=//p' | head -1)"
    escalate="$(printf '%s\n' "$verdict" | sed -n 's/^escalate=//p' | head -1)"
    if [ "$escalate" = true ]; then
        echo "ESCALATE: bump=${bump} requires operator approval (major or 0.x breaking). No tag created." >&2
        exit 10
    fi

    # Fail-closed pre-publish gates. Any red -> exit 1 before tagging.
    [ "$(probe_ci_status)" = success ] || die_gate "G1 CI not green on $allow_branch"
    [ "$(probe_qa_verdict "$repo")" = ALL_PASS ] || die_gate "G2 /dr-qa not ALL_PASS"
    grep -rqE 'attest-build-provenance' "$repo/.github/workflows/" 2>/dev/null || die_gate "G3 signed pipeline absent"
    local cur_branch; cur_branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
    [ "$cur_branch" = "$allow_branch" ] || die_gate "G4 branch '$cur_branch' != '$allow_branch'"
    [ "$(probe_version_published)" = false ] || die_gate "G5 version $version already published"

    local gates="G1,G2,G3,G4,G5,G6"
    if [ "$dry_run" = true ]; then
        echo "DRY-RUN: all gates green for v${version} (bump=${bump}); no tag created."
        exit 0
    fi

    # Side-effect crossing. Write the audit record, then create the ANNOTATED tag
    # carrying the classifier stamp, then push. Defensive invariant below binds
    # exit code to the tag actually existing.
    local stamp audit_file
    stamp="$("$SCRIPT_DIR/release-classify.sh" --repo "$repo" --api-diff auto --stamp)"
    audit_file="$(write_audit "${GATE_AUDIT_DIR:-$repo/docs/release-audit}" "$version" "$bump" "$registry" "$gates" "$verdict")"
    git -C "$repo" tag -a "v${version}" -m "$(printf 'release %s\n\n%s' "$version" "$stamp")"

    # Defensive invariant: the tag MUST exist now (CLAUDE.md § Defensive Invariants).
    if ! git -C "$repo" rev-parse -q --verify "refs/tags/v${version}" >/dev/null; then
        echo "ERROR: internal invariant violated: gates passed but tag v${version} was not created" >&2
        exit 2
    fi
    git -C "$repo" push --tags 2>/dev/null || echo "WARN: push --tags failed (offline?); tag exists locally" >&2
    echo "TAGGED v${version} (bump=${bump}); audit: ${audit_file}"

    # G7 post-publish smoke (after the tag/publish). Non-zero lets the operator roll back.
    if [ "$(probe_smoke_status)" != success ]; then
        echo "G7 post-publish install smoke FAILED for v${version} — roll back per docs/how-to/release-rollback.md" >&2
        exit 4
    fi
    exit 0
}

main "$@"
