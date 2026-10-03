#!/usr/bin/env bash
# Fail-closed release gate. Evidence hooks are executables, never scalar verdicts.
# Hook arguments: gate, repository, exact source SHA, version, registry.
# Hook stdout: ReleaseGateEvidence/v1 JSON bound to those arguments, with verdict
# and a nonempty evidence description. Registry/QA/smoke have no guessed default.
# Native CI additionally needs GATE_CI_WORKFLOWS (comma-separated required names).
# Exit: 0 exact signed tag pushed + smoke verified (or dry-run); 1 preflight/tag/
# push failed; 2 usage; 3 invalid repository; 4 smoke failed after push; 10 major.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { echo 'usage: release-gate.sh --repo PATH --version X.Y.Z --registry pypi|npm|gh [--allow-branch main] [--dry-run]' >&2; exit 2; }
die_gate() { echo "GATE FAILED: $1" >&2; exit 1; }

resolve_manifest_version() {
    local repo="$1" value=""
    if [ -f "$repo/pyproject.toml" ]; then
        value="$(sed -n 's/^version *= *"\([0-9][0-9.]*\).*/\1/p' "$repo/pyproject.toml" | head -1)"
    fi
    if [ -z "$value" ] && [ -f "$repo/VERSION" ]; then value="$(tr -d ' \t\n' < "$repo/VERSION")"; fi
    printf '%s' "$value"
}

native_ci() {
    [ -n "${GATE_CI_WORKFLOWS:-}" ] || return 1
    (cd "$repo" && gh run list --branch "$allow_branch" --commit "$source_sha" --limit 100 \
        --json databaseId,workflowName,headSha,status,conclusion) > "$scratch/ci-runs.json" || return 1
    python3 - "$scratch/ci-runs.json" "$source_sha" "$version" "$registry" "$GATE_CI_WORKFLOWS" <<'PY'
import json,sys
runs=json.load(open(sys.argv[1]));sha,version,registry,required=sys.argv[2:]
names=required.split(',')
if not isinstance(runs,list) or not runs or len(runs)>=100 or any(not n or n.strip()!=n for n in names) or len(names)!=len(set(names)):sys.exit(1)
latest={}
for run in runs:
    if not isinstance(run,dict) or run.get('headSha')!=sha or type(run.get('databaseId')) is not int:sys.exit(1)
    name=run.get('workflowName')
    if name in names and (name not in latest or run['databaseId']>latest[name]['databaseId']):latest[name]=run
if set(latest)!=set(names) or any(r.get('status')!='completed' or r.get('conclusion')!='success' for r in latest.values()):sys.exit(1)
print(json.dumps({'schema':'ReleaseGateEvidence/v1','gate':'G1','source_commit':sha,'version':version,'registry':registry,'verdict':'success','evidence':'Exact SHA; latest successful runs for every explicitly required workflow','runs':{name:r['databaseId'] for name,r in latest.items()}}))
PY
}

probe() {
    local gate="$1" executable="$2" expected="$3"
    local output="$scratch/$gate.json"
    if [ "$gate" = G1 ] && [ -z "$executable" ]; then
        native_ci > "$output" || die_gate 'G1 exact-SHA CI evidence unavailable; set required workflows or GATE_CI_PROBE'
    else
        [ -f "$executable" ] && [ -x "$executable" ] || die_gate "$gate executable evidence hook is required"
        "$executable" "$gate" "$repo" "$source_sha" "$version" "$registry" > "$output" || die_gate "$gate evidence hook failed"
    fi
    python3 - "$output" "$gate" "$source_sha" "$version" "$registry" "$expected" <<'PY' || die_gate "$gate evidence invalid, stale, or not passing"
import json,sys
from pathlib import Path
p=Path(sys.argv[1]);gate,sha,version,registry,expected=sys.argv[2:]
try:
    if p.stat().st_size>1024*1024:sys.exit(1)
    def unique(pairs):
        out={}
        for key,value in pairs:
            if key in out:raise ValueError('duplicate evidence field')
            out[key]=value
        return out
    result=json.loads(p.read_text(),object_pairs_hook=unique)
    required={'schema':'ReleaseGateEvidence/v1','gate':gate,'source_commit':sha,'version':version,'registry':registry,'verdict':expected}
    if not isinstance(result,dict) or any(result.get(k)!=v for k,v in required.items()):sys.exit(1)
    if not isinstance(result.get('evidence'),str) or not 1<=len(result['evidence'].strip())<=4000:sys.exit(1)
except (OSError,ValueError,TypeError):sys.exit(1)
PY
}

write_audit() {
    local state="$1" tag_object="${2:-}"
    python3 - "$audit_file" "$scratch" "$source_sha" "$version" "$registry" "$bump" "$state" "$tag_object" <<'PY'
from pathlib import Path
from datetime import datetime,timezone
import json,sys
file,scratch,sha,version,registry,bump,state,tag=sys.argv[1:]
checks={}
for p in Path(scratch).glob('G*.json'):
    try:checks[p.stem]=json.loads(p.read_text())
    except (OSError,ValueError):checks[p.stem]={'evidence_state':'invalid'}
record={'schema':'ReleaseGateAudit/v1','source_commit':sha,'version':version,'registry':registry,'bump_level':bump,'state':state,'tag_object':tag,'timestamp':datetime.now(timezone.utc).isoformat(),'checks':checks}
p=Path(file);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(record,indent=2)+'\n')
PY
}

assert_source() {
    [ "$(git -C "$repo" rev-parse HEAD)" = "$source_sha" ] || die_gate 'Source SHA changed during gate execution'
    [ -z "$(git -C "$repo" status --porcelain --untracked-files=no)" ] || die_gate 'Tracked source is dirty'
}

main() {
    repo="";version="";registry="";allow_branch=main;local dry_run=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --repo|--version|--registry|--allow-branch)
                [ $# -ge 2 ] || usage
                case "$1" in --repo) repo="$2";; --version) version="$2";; --registry) registry="$2";; --allow-branch) allow_branch="$2";; esac;shift 2;;
            --dry-run) dry_run=true;shift;;
            *) usage;;
        esac
    done
    [ -n "$repo" ] && [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
    case "$registry" in pypi|npm|gh);; *) usage;; esac
    git check-ref-format "refs/heads/$allow_branch" >/dev/null || usage
    git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 3
    repo="$(cd "$repo" && pwd)";source_sha="$(git -C "$repo" rev-parse HEAD)"
    assert_source
    for deprecated in GATE_CI_STATUS GATE_QA_VERDICT GATE_VERSION_PUBLISHED GATE_SMOKE_STATUS; do
        [ -z "${!deprecated:-}" ] || die_gate "Deprecated scalar $deprecated is not evidence; configure an executable probe"
    done
    local verdict escalate
    verdict="$("$SCRIPT_DIR/release-classify.sh" --repo "$repo" --to "$source_sha" --api-diff auto)"
    bump="$(printf '%s\n' "$verdict" | sed -n 's/^bump_level=//p' | head -1)"
    escalate="$(printf '%s\n' "$verdict" | sed -n 's/^escalate=//p' | head -1)"
    if [ "$escalate" = true ]; then echo 'ESCALATE: major or 0.x breaking release; no tag created' >&2;exit 10;fi
    [ "$escalate" = false ] || die_gate 'Classifier verdict unavailable'
    [ "$(resolve_manifest_version "$repo")" = "$version" ] || die_gate 'G0 manifest version mismatch; bump manifest and CHANGELOG before tagging'
    [ "$(git -C "$repo" branch --show-current)" = "$allow_branch" ] || die_gate 'G4 release branch mismatch'
    [ "$(git -C "$repo" ls-remote origin "refs/heads/$allow_branch" | awk '{print $1}')" = "$source_sha" ] || die_gate 'Remote release branch does not match exact source SHA'
    python3 - "$repo/.github/workflows" <<'PYG3' || die_gate 'G3 executable pinned attestation step absent or workflow validation unavailable'
from pathlib import Path
import re,sys
try:
    import yaml
    found=False
    for p in Path(sys.argv[1]).glob('*.y*ml'):
        value=yaml.safe_load(p.read_text())
        if not isinstance(value,dict):continue
        jobs=value.get('jobs',{})
        if not isinstance(jobs,dict):continue
        for job in jobs.values():
            if not isinstance(job,dict):continue
            steps=job.get('steps',[])
            if not isinstance(steps,list):continue
            for step in steps:
                if isinstance(step,dict) and isinstance(step.get('uses'),str):
                    found |= bool(re.fullmatch(r'actions/attest-build-provenance@[0-9a-f]{40}',step['uses']))
    sys.exit(0 if found else 1)
except (ImportError,OSError,ValueError,yaml.YAMLError if 'yaml' in globals() else ValueError):
    sys.exit(1)
PYG3
    [ -f "${GATE_SMOKE_PROBE:-}" ] && [ -x "$GATE_SMOKE_PROBE" ] || die_gate 'G7 measured smoke hook required before publication'
    [ -n "$(git -C "$repo" config user.signingkey || true)" ] || die_gate 'Signed release tag requires a configured signing key'
    scratch="$(mktemp -d)";trap 'rm -rf -- "${scratch:?}"' EXIT
    probe G1 "${GATE_CI_PROBE:-}" success
    probe G2 "${GATE_QA_PROBE:-}" ALL_PASS
    probe G5 "${GATE_REGISTRY_PROBE:-}" not_published
    assert_source
    if [ "$dry_run" = true ]; then echo "DRY-RUN: exact-source preflight verified for v$version; signing, push, and smoke not executed";return;fi
    audit_file="${GATE_AUDIT_DIR:-$repo/documentation/release-audit}/release-$version.json"
    write_audit preflight_verified
    local stamp tag_object remote_object
    stamp="$("$SCRIPT_DIR/release-classify.sh" --repo "$repo" --to "$source_sha" --api-diff auto --stamp)"
    git -C "$repo" tag -s "v$version" "$source_sha" -m "$(printf 'release %s\n\n%s' "$version" "$stamp")" || die_gate 'Signed tag creation failed'
    if [ "$(git -C "$repo" config gpg.format || true)" = ssh ] && [ -f "$repo/.github/ssh-signing-allowed-signers" ]; then
        git -C "$repo" -c "gpg.ssh.allowedSignersFile=$repo/.github/ssh-signing-allowed-signers" verify-tag "v$version" || die_gate 'Repository-trusted tag signature verification failed; local tag retained'
    else
        git -C "$repo" verify-tag "v$version" || die_gate 'Signed tag verification failed; local tag retained'
    fi
    tag_object="$(git -C "$repo" rev-parse "refs/tags/v$version")"
    write_audit signed_tag_verified "$tag_object"
    git -C "$repo" push origin "refs/tags/v$version:refs/tags/v$version" || die_gate 'Exact tag push failed; local signed tag and audit retained'
    remote_object="$(git -C "$repo" ls-remote origin "refs/tags/v$version" | awk '{print $1}')"
    [ "$remote_object" = "$tag_object" ] || die_gate 'Remote tag object verification failed'
    write_audit pushed_verified "$tag_object"
    if ! (probe G7 "$GATE_SMOKE_PROBE" success); then
        write_audit smoke_failed "$tag_object"
        echo 'G7 smoke evidence failed after exact signed tag push; investigate the published release' >&2;exit 4
    fi
    assert_source
    write_audit smoke_verified "$tag_object"
    echo "RELEASE VERIFIED v$version; exact signed tag pushed; audit: $audit_file"
}
main "$@"
