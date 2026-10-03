#!/usr/bin/env bats
# Synthetic gate observations test admission logic. Tag signatures and remote
# pushes are real: ephemeral SSH signer, allowed signers, and local bare origin.
setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/release-gate.sh"
    TEST_ROOT="$(mktemp -d)";REPO="$TEST_ROOT/repo";ORIGIN="$TEST_ROOT/origin.git"
    git init -q -b main "$REPO";git init -q --bare "$ORIGIN"
    git -C "$REPO" config user.email release@example.test
    git -C "$REPO" config user.name 'Release fixture'
    git -C "$REPO" config commit.gpgsign false
    git -C "$REPO" config tag.gpgsign false
    printf '0.6.4\n' > "$REPO/VERSION"
    mkdir -p "$REPO/.github/workflows"
    printf 'jobs:\n  release:\n    steps:\n      - uses: actions/attest-build-provenance@fixture\n' > "$REPO/.github/workflows/release.yml"
    git -C "$REPO" add VERSION .github;git -C "$REPO" commit -q -m 'fix: fixture baseline'
    git -C "$REPO" tag v0.6.3
    git -C "$REPO" commit -q --allow-empty -m 'fix: release fixture'
    git -C "$REPO" remote add origin "$ORIGIN";git -C "$REPO" push -q origin main
    ssh-keygen -q -t ed25519 -N '' -f "$TEST_ROOT/signing-key"
    printf 'release@example.test ' > "$TEST_ROOT/allowed-signers"
    cat "$TEST_ROOT/signing-key.pub" >> "$TEST_ROOT/allowed-signers"
    git -C "$REPO" config gpg.format ssh
    git -C "$REPO" config user.signingkey "$TEST_ROOT/signing-key"
    git -C "$REPO" config gpg.ssh.allowedSignersFile "$TEST_ROOT/allowed-signers"
    HOOK="$TEST_ROOT/probe"
    cat > "$HOOK" <<'PY'
#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
gate,repo,sha,version,registry=sys.argv[1:]
if os.environ.get('TEST_PROBE_FAILURE')==gate:sys.exit(1)
if gate=='G1' and os.environ.get('TEST_BAD_JSON'):print('not json');sys.exit(0)
if gate=='G1' and os.environ.get('TEST_BAD_SHA'):sha='0'*40
if gate=='G2' and os.environ.get('TEST_MUTATE_SOURCE'):Path(repo,'VERSION').write_text('9.9.9\n')
verdict={'G1':'success','G2':'ALL_PASS','G5':'not_published','G7':'success'}[gate]
verdict=os.environ.get('TEST_'+gate+'_VERDICT',verdict)
print(json.dumps({'schema':'ReleaseGateEvidence/v1','gate':gate,'source_commit':sha,'version':version,'registry':registry,'verdict':verdict,'evidence':'Explicit synthetic observation for admission test'}))
PY
    chmod +x "$HOOK"
    export GATE_CI_PROBE="$HOOK" GATE_QA_PROBE="$HOOK" GATE_REGISTRY_PROBE="$HOOK" GATE_SMOKE_PROBE="$HOOK"
    unset GATE_CI_STATUS GATE_QA_VERDICT GATE_VERSION_PUBLISHED GATE_SMOKE_STATUS GATE_CI_WORKFLOWS
    export GATE_AUDIT_DIR="$TEST_ROOT/audit"
}
teardown() { rm -rf -- "${TEST_ROOT:?}"; }
_run_gate() { run "$SCRIPT" --repo "$REPO" --version "${1:-0.6.4}" --registry gh "${@:2}"; }
_tag_exists() { git -C "$REPO" show-ref --verify --quiet "refs/tags/v$1"; }
_remote_tag() { git --git-dir="$ORIGIN" show-ref --verify --quiet "refs/tags/v$1"; }
_commit() { git -C "$REPO" add -A;git -C "$REPO" commit -q -m 'fix: update fixture';git -C "$REPO" push -q origin main; }

@test 'passing evidence creates a verified SSH-signed tag and pushes only its exact object' {
    git -C "$REPO" tag unrelated-local-tag
    _run_gate
    [ "$status" -eq 0 ]
    _tag_exists 0.6.4;_remote_tag 0.6.4
    run git -C "$REPO" verify-tag v0.6.4
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" rev-parse refs/tags/v0.6.4)" = "$(git --git-dir="$ORIGIN" rev-parse refs/tags/v0.6.4)" ]
    ! git --git-dir="$ORIGIN" show-ref --verify --quiet refs/tags/unrelated-local-tag
    run python3 -c 'import json,sys;r=json.load(open(sys.argv[1]));assert r["state"]=="smoke_verified";assert set(r["checks"])=={"G1","G2","G5","G7"}' "$GATE_AUDIT_DIR/release-0.6.4.json"
    [ "$status" -eq 0 ]
}

@test 'rejected exact tag push fails and retains the verified local tag without remote success' {
    printf '#!/bin/sh\nexit 1\n' > "$ORIGIN/hooks/pre-receive";chmod +x "$ORIGIN/hooks/pre-receive"
    _run_gate
    [ "$status" -ne 0 ];_tag_exists 0.6.4;! _remote_tag 0.6.4
    [[ "$output" != *'RELEASE VERIFIED'* ]]
    run python3 -c 'import json,sys;assert json.load(open(sys.argv[1]))["state"]=="signed_tag_verified"' "$GATE_AUDIT_DIR/release-0.6.4.json"
    [ "$status" -eq 0 ]
}

@test 'missing signing key blocks before tag creation' {
    git -C "$REPO" config --unset user.signingkey
    _run_gate;[ "$status" -eq 1 ];! _tag_exists 0.6.4
}

@test 'untrusted signing identity never pushes a tag' {
    ssh-keygen -q -t ed25519 -N '' -f "$TEST_ROOT/untrusted-key"
    printf 'other@example.test ' > "$TEST_ROOT/other-signers";cat "$TEST_ROOT/untrusted-key.pub" >> "$TEST_ROOT/other-signers"
    git -C "$REPO" config gpg.ssh.allowedSignersFile "$TEST_ROOT/other-signers"
    _run_gate;[ "$status" -ne 0 ];! _remote_tag 0.6.4
}

@test 'missing registry probe is unknown and never becomes unpublished' {
    unset GATE_REGISTRY_PROBE
    _run_gate;[ "$status" -eq 1 ];! _tag_exists 0.6.4
}

@test 'missing smoke probe blocks before publication' {
    unset GATE_SMOKE_PROBE
    _run_gate;[ "$status" -eq 1 ];! _tag_exists 0.6.4
}

@test 'naked success environment values are refused as evidence' {
    export GATE_CI_STATUS=success
    _run_gate;[ "$status" -eq 1 ];! _tag_exists 0.6.4
}

@test 'wrong source SHA in a hook observation is refused' {
    export TEST_BAD_SHA=1
    _run_gate;[ "$status" -eq 1 ];! _tag_exists 0.6.4
}

@test 'invalid hook JSON and failing hook commands both fail closed' {
    export TEST_BAD_JSON=1
    _run_gate;[ "$status" -eq 1 ];! _tag_exists 0.6.4
    unset TEST_BAD_JSON;export TEST_PROBE_FAILURE=G5
    _run_gate;[ "$status" -eq 1 ];! _tag_exists 0.6.4
}

@test 'QA or registry failure blocks before tagging' {
    export TEST_G2_VERDICT=BLOCKED
    _run_gate;[ "$status" -eq 1 ];! _tag_exists 0.6.4
    unset TEST_G2_VERDICT;export TEST_G5_VERDICT=published
    _run_gate;[ "$status" -eq 1 ];! _tag_exists 0.6.4
}

@test 'source mutation by a hook invalidates previously measured evidence' {
    export TEST_MUTATE_SOURCE=1
    _run_gate;[ "$status" -eq 1 ];! _tag_exists 0.6.4
}

@test 'a dirty tracked source is not certified' {
    printf '0.6.3\n' > "$REPO/VERSION"
    _run_gate;[ "$status" -eq 1 ];! _tag_exists 0.6.4
}

@test 'unpublished local source does not match the remote release branch' {
    git -C "$REPO" commit -q --allow-empty -m 'fix: not pushed'
    _run_gate;[ "$status" -eq 1 ];! _tag_exists 0.6.4
}

@test 'signed pipeline reference and selected release branch are mandatory' {
    rm "$REPO/.github/workflows/release.yml";_commit
    _run_gate;[ "$status" -eq 1 ];! _tag_exists 0.6.4
}

@test 'major classifier escalation never creates a tag or audit' {
    git -C "$REPO" commit -q --allow-empty -m 'feat!: breaking fixture'
    _run_gate 1.0.0;[ "$status" -eq 10 ];! _tag_exists 1.0.0
    [ ! -d "$GATE_AUDIT_DIR" ]
}

@test 'post-push failed smoke is nonzero and preserves the actual published tag' {
    export TEST_G7_VERDICT=failure
    _run_gate;[ "$status" -eq 4 ];_remote_tag 0.6.4
    [[ "$output" != *'RELEASE VERIFIED'* ]]
}

@test 'dry run states that signing push and smoke have not executed' {
    _run_gate 0.6.4 --dry-run;[ "$status" -eq 0 ];! _tag_exists 0.6.4
    [[ "$output" == *'signing, push, and smoke not executed'* ]]
}

@test 'manifest mismatch and invalid registry/version arguments are refused' {
    printf '0.6.3\n' > "$REPO/VERSION";_commit
    _run_gate;[ "$status" -eq 1 ];! _tag_exists 0.6.4
    _run_gate invalid;[ "$status" -eq 2 ]
    run "$SCRIPT" --repo "$REPO" --version 0.6.4 --registry unsupported;[ "$status" -eq 2 ]
}

@test 'native CI refuses missing required workflows or a latest failure at the exact SHA' {
    mkdir "$TEST_ROOT/bin";cat > "$TEST_ROOT/bin/gh" <<'PY'
#!/usr/bin/env python3
import json,os,sys
sha=sys.argv[sys.argv.index('--commit')+1]
runs=[{'databaseId':1,'workflowName':'verify','headSha':sha,'status':'completed','conclusion':'success'}]
if os.environ.get('TEST_CI_LATEST_FAILURE'):runs.append({'databaseId':2,'workflowName':'verify','headSha':sha,'status':'completed','conclusion':'failure'})
if os.environ.get('TEST_CI_WRONG_SHA'):runs[0]['headSha']='0'*40
print(json.dumps(runs))
PY
    chmod +x "$TEST_ROOT/bin/gh";export PATH="$TEST_ROOT/bin:$PATH";unset GATE_CI_PROBE
    export GATE_CI_WORKFLOWS=verify,required-missing
    _run_gate;[ "$status" -eq 1 ];! _tag_exists 0.6.4
    export GATE_CI_WORKFLOWS=verify TEST_CI_LATEST_FAILURE=1
    _run_gate;[ "$status" -eq 1 ];! _tag_exists 0.6.4
    unset TEST_CI_LATEST_FAILURE;export TEST_CI_WRONG_SHA=1
    _run_gate;[ "$status" -eq 1 ];! _tag_exists 0.6.4
    unset TEST_CI_WRONG_SHA
    _run_gate 0.6.4 --dry-run;[ "$status" -eq 0 ]
}
