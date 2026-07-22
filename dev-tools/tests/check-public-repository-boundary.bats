#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../check-public-repository-boundary.sh"
    REGEX_SOURCE="${BATS_TEST_DIRNAME}/../public-surface-forbidden.regex"
    WORK="$(mktemp -d -t public-boundary-XXXXXX)"
    REPO="${WORK}/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q -b main
    git -C "$REPO" config user.email "test@example.com"
    git -C "$REPO" config user.name "Test"
    printf '# Clean project\n' >"${REPO}/README.md"
    git -C "$REPO" add README.md
    git -C "$REPO" commit -q -m "initial"
    ALLOWLIST="${WORK}/allowlist.txt"
    REPORT="${WORK}/gitleaks.json"
    PROOF="${WORK}/proof.json"
    REGEX="${WORK}/public-surface-forbidden.regex"
    cp "$REGEX_SOURCE" "$REGEX"
    BIN="${WORK}/bin"
    mkdir -p "$BIN"
    cat >"${BIN}/gitleaks" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1-}" == version ]]; then
    printf 'test\n'
    exit 0
fi
out=''
while (($#)); do
    case "$1" in
        --report-path) out="${2-}"; shift 2 ;;
        *) shift ;;
    esac
done
[[ -n "$out" ]]
cp "$MOCK_GITLEAKS_REPORT" "$out"
[[ "$(jq 'length' "$out")" -eq 0 ]]
MOCK
    chmod +x "${BIN}/gitleaks"
    cat >"${BIN}/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1-}" == run && "${2-}" == view ]]; then
    attempt=1
    while (($#)); do
        if [[ "$1" == --attempt ]]; then attempt="$2"; break; fi
        shift
    done
    if [[ "$attempt" == 1 && -n "${MOCK_ACTION_LOG_ATTEMPT_1:-}" ]]; then
        printf '%s\n' "$MOCK_ACTION_LOG_ATTEMPT_1"
    else
        printf '%s\n' "${MOCK_ACTION_LOG:-clean action log}"
    fi
    exit 0
fi
endpoint="${*: -1}"
if [[ "$endpoint" == '/repos/owner/repo' ]]; then
    printf '{"id":123,"full_name":"owner/repo","has_wiki":false,"has_pages":%s,"has_discussions":%s}\n' "${MOCK_HAS_PAGES:-false}" "${MOCK_HAS_DISCUSSIONS:-false}"
elif [[ "$endpoint" == *'/git/matching-refs/'* ]]; then
    count=0
    [[ -f "$MOCK_REF_COUNTER" ]] && count="$(cat "$MOCK_REF_COUNTER")"
    count=$((count + 1))
    printf '%s' "$count" >"$MOCK_REF_COUNTER"
    if [[ "${MOCK_DRIFT_REFS:-0}" == 1 && "$count" -gt 1 ]]; then
        printf '[[{"ref":"refs/heads/main","object":{"sha":"0000000000000000000000000000000000000000"}}]]\n'
        exit 0
    fi
    git -C "$MOCK_GITHUB_REPO" for-each-ref --format='%(refname)=%(objectname)' refs/heads refs/tags \
      | LC_ALL=C sort \
      | jq -Rsc '[split("\n")[] | select(length>0) | split("=") | {ref:.[0],object:{sha:.[1]}}] | [.]'
elif [[ "$endpoint" == *'/actions/runs/77/attempts/'*'/jobs?'* ]]; then
    printf '[{"total_count":1,"jobs":[{"id":88,"runner_id":9,"status":"completed","conclusion":"success","steps":[{"status":"completed","conclusion":"success"}]}]}]\n'
elif [[ "$endpoint" == *'/actions/runs?'* ]]; then
    printf '[{"total_count":%s,"workflow_runs":[{"id":77,"run_attempt":2,"status":"completed","conclusion":"success"}]}]\n' "${MOCK_RUN_TOTAL:-1}"
elif [[ "$endpoint" == *'/actions/artifacts?'* ]]; then
    printf '[{"total_count":0,"artifacts":[]}]\n'
elif [[ "$endpoint" == *'/releases?'* ]]; then
    printf '[[]]\n'
elif [[ "$endpoint" == *'/issues?'* ]]; then
    if [[ "${MOCK_HAS_PR:-false}" == true ]]; then
        printf '[[{"number":5,"comments":0,"pull_request":{"url":"https://api.github.test/pulls/5"},"title":"clean pull request","body":"clean body"}]]\n'
    else
        printf '[[]]\n'
    fi
elif [[ "$endpoint" == *'/pulls/5/reviews?'* ]]; then
    printf '[[{"id":501,"body":"%s"}]]\n' "${MOCK_PR_REVIEW_BODY:-clean review}"
elif [[ "$endpoint" == *'/pulls/5/comments?'* ]]; then
    printf '[[{"id":502,"body":"clean inline comment"}]]\n'
elif [[ "$endpoint" == *'/discussions/9/comments/99/replies?'* ]]; then
    printf '[[{"id":100,"body":"%s"}]]\n' "${MOCK_REPLY_BODY:-clean reply}"
elif [[ "$endpoint" == *'/discussions/9/comments?'* ]]; then
    printf '[[{"id":99,"body":"clean comment"}]]\n'
elif [[ "$endpoint" == *'/discussions?'* ]]; then
    printf '[[{"number":9,"comments":1,"title":"clean discussion","body":"clean body"}]]\n'
else
    exit 1
fi
MOCK
    chmod +x "${BIN}/gh"
    export PATH="${BIN}:${PATH}"
    export MOCK_GITLEAKS_REPORT="$REPORT"
    export MOCK_GITHUB_REPO="$REPO"
    export MOCK_REF_COUNTER="${WORK}/ref-counter"
}

teardown() {
    rm -rf "$WORK"
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

write_allowlist() {
    git -C "$REPO" ls-tree -r --name-only HEAD | LC_ALL=C sort >"$ALLOWLIST"
}

write_clean_proof() {
    local sha tree report_hash refs_hash public_refs_hash allowlist_hash policy_hash repository_hash
    sha="$(git -C "$REPO" rev-parse HEAD)"
    tree="$(git -C "$REPO" rev-parse HEAD^{tree})"
    printf '[]\n' >"$REPORT"
    report_hash="$(sha256_file "$REPORT")"
    refs_hash="$(git -C "$REPO" for-each-ref --format='%(refname)=%(objectname)' | LC_ALL=C sort | sha256_stream)"
    public_refs_hash="$(git -C "$REPO" for-each-ref --format='%(refname)=%(objectname)' refs/heads refs/tags | LC_ALL=C sort | sha256_stream)"
    allowlist_hash="$(sha256_file "$ALLOWLIST")"
    policy_hash="$(sha256_file "$REGEX")"
    repository_hash="$(printf '123:owner/repo' | sha256_stream)"
    cat >"$PROOF" <<EOF
{"schema_version":1,"scanner":"gitleaks","scanner_version":"test","scope":"all-refs","head_sha":"${sha}","tree_id":"${tree}","refs_sha256":"${refs_hash}","public_refs_sha256":"${public_refs_hash}","allowlist_sha256":"${allowlist_hash}","policy_sha256":"${policy_hash}","repository_identity_sha256":"${repository_hash}","attested_at":"2026-07-22T00:00:00Z","exit_code":0,"findings":0,"report_sha256":"${report_hash}"}
EOF
}

sha256_stream() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    else
        shasum -a 256 | awk '{print $1}'
    fi
}

commit_all() {
    git -C "$REPO" add -A
    git -C "$REPO" commit -q -m "update"
}

run_gate() {
    run "$SCRIPT" --repo "$REPO" --github-repo owner/repo --ref HEAD --allowlist "$ALLOWLIST" \
        --regex "$REGEX" --secret-report "$REPORT" --secret-proof "$PROOF" --format json
}

@test "exact tracked manifest and clean all-ref proof pass" {
    write_allowlist
    write_clean_proof
    run_gate
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision":"pass"'* ]]
    [[ "$output" == *'"tracked_files":1'* ]]
}

@test "extra tracked path not in manifest fails" {
    write_allowlist
    printf 'extra\n' >"${REPO}/extra.txt"
    commit_all
    write_clean_proof
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'tree_manifest_mismatch'* ]]
}

@test "allowlisted path absent from tree fails" {
    write_allowlist
    printf 'missing.txt\n' >>"$ALLOWLIST"
    write_clean_proof
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'tree_manifest_mismatch'* ]]
}

@test "canonical forbidden reference in HEAD fails without echoing content" {
    printf 'See PRD-TEST-0001 for details.\n' >"${REPO}/README.md"
    commit_all
    write_allowlist
    write_clean_proof
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'forbidden_public_reference'* ]]
    [[ "$output" != *'See PRD-TEST-0001'* ]]
}

@test "forbidden reference removed from HEAD but reachable in history fails" {
    printf 'See PRD-TEST-0001 for details.\n' >"${REPO}/README.md"
    commit_all
    printf '# Clean again\n' >"${REPO}/README.md"
    commit_all
    write_allowlist
    write_clean_proof
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'forbidden_public_reference'* ]]
}

@test "private absolute path in reachable blob fails" {
    printf 'Local /Users/example/private/file.txt\n' >"${REPO}/README.md"
    commit_all
    write_allowlist
    write_clean_proof
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'private_absolute_path'* ]]
    [[ "$output" != *'/Users/example/private/file.txt'* ]]
}

@test "case-variant credential query key in reachable blob fails redacted" {
    printf 'https://cdn.example.test/file?X-Amz-Credential=do-not-print\n' >"${REPO}/README.md"
    commit_all
    write_allowlist
    write_clean_proof
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'credential_query_key'* ]]
    [[ "$output" != *'do-not-print'* ]]
}

@test "non-empty secret report fails without copying secret value" {
    write_allowlist
    write_clean_proof
    printf '[{"Secret":"do-not-print"}]\n' >"$REPORT"
    local report_hash
    report_hash="$(sha256_file "$REPORT")"
    jq --arg h "$report_hash" '.report_sha256=$h | .findings=1 | .exit_code=1' "$PROOF" >"${PROOF}.new"
    mv "${PROOF}.new" "$PROOF"
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'secret_scan_findings'* ]]
    [[ "$output" != *'do-not-print'* ]]
}

@test "secret proof bound to another SHA fails" {
    write_allowlist
    write_clean_proof
    jq '.head_sha="0000000000000000000000000000000000000000"' "$PROOF" >"${PROOF}.new"
    mv "${PROOF}.new" "$PROOF"
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'proof_binding_mismatch'* ]]
}

@test "secret report digest mismatch fails" {
    write_allowlist
    write_clean_proof
    printf '[] ' >"$REPORT"
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'proof_binding_mismatch'* ]]
}

@test "symlink entry fails closed" {
    ln -s /Users/example/private "${REPO}/private-link"
    commit_all
    write_allowlist
    write_clean_proof
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'unsupported_git_entry'* ]]
}

@test "Git LFS pointer fails closed" {
    cat >"${REPO}/asset.bin" <<'EOF'
version https://git-lfs.github.com/spec/v1
oid sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
size 42
EOF
    commit_all
    write_allowlist
    write_clean_proof
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'unsupported_blob'* ]]
}

@test "unsafe allowlist entry is an invocation error" {
    printf '../outside\n' >"$ALLOWLIST"
    printf '[]\n' >"$REPORT"
    printf '{}\n' >"$PROOF"
    run_gate
    [ "$status" -eq 2 ]
    [[ "$output" == *'unsafe_allowlist_entry'* ]]
}

@test "malformed proof is an invocation error" {
    write_allowlist
    printf '[]\n' >"$REPORT"
    printf '{not-json\n' >"$PROOF"
    run_gate
    [ "$status" -eq 2 ]
    [[ "$output" == *'invalid_secret_proof'* ]]
}

@test "forbidden content in a live Actions log fails redacted" {
    write_allowlist
    write_clean_proof
    export MOCK_ACTION_LOG='Internal AGENT-0001 do-not-print'
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'forbidden_hosted_surface'* ]]
    [[ "$output" != *'do-not-print'* ]]
}

@test "a forbidden prior Actions attempt is included and fails" {
    write_allowlist
    write_clean_proof
    export MOCK_ACTION_LOG_ATTEMPT_1='Internal AGENT-0001 prior-attempt-secret'
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'forbidden_hosted_surface'* ]]
    [[ "$output" != *'prior-attempt-secret'* ]]
}

@test "GitHub Pages enabled without a supported audit fails closed" {
    write_allowlist
    write_clean_proof
    export MOCK_HAS_PAGES=true
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'unsupported_hosted_surface'* ]]
}

@test "nested discussion replies are included and scanned" {
    write_allowlist
    write_clean_proof
    export MOCK_HAS_DISCUSSIONS=true
    export MOCK_REPLY_BODY='Internal AGENT-0001 nested-reply-secret'
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'forbidden_hosted_surface'* ]]
    [[ "$output" != *'nested-reply-secret'* ]]
}

@test "pull request reviews and inline comments are included and scanned" {
    write_allowlist
    write_clean_proof
    export MOCK_HAS_PR=true
    export MOCK_PR_REVIEW_BODY='Internal AGENT-0001 pull-review-secret'
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'forbidden_hosted_surface'* ]]
    [[ "$output" != *'pull-review-secret'* ]]
}

@test "object pagination total mismatch is an invocation error" {
    write_allowlist
    write_clean_proof
    export MOCK_RUN_TOTAL=2
    run_gate
    [ "$status" -eq 2 ]
    [[ "$output" == *'hosting_api_error'* ]]
}

@test "hosted and ref state changing during the audit fails" {
    write_allowlist
    write_clean_proof
    export MOCK_DRIFT_REFS=1
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'public_ref_drift'* ]]
}

@test "sensitive encoded and escaped query keys fail redacted" {
    for value in \
        'https://e.test/?client_secret=do-not-print' \
        'https://e.test/?secret=do-not-print' \
        'https://e.test/?sv=1&amp;sig=do-not-print' \
        'https://e.test/?X%2DAmz%2DCredential=do-not-print'; do
        printf '%s\n' "$value" >"${REPO}/README.md"
        commit_all
    done
    write_allowlist
    write_clean_proof
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'credential_query_key'* ]]
    [[ "$output" != *'do-not-print'* ]]
}

@test "Windows private path in a filename fails redacted" {
    printf 'clean\n' >"${REPO}/C:\\Users\\alice\\private.txt"
    commit_all
    write_allowlist
    write_clean_proof
    run_gate
    [ "$status" -eq 1 ]
    [[ "$output" == *'private_absolute_path'* ]]
    [[ "$output" != *'alice'* ]]
}

@test "text evidence includes immutable repository scanner and time fields" {
    write_allowlist
    write_clean_proof
    run "$SCRIPT" --repo "$REPO" --github-repo owner/repo --ref HEAD --allowlist "$ALLOWLIST" \
        --regex "$REGEX" --secret-report "$REPORT" --secret-proof "$PROOF" --format text
    [ "$status" -eq 0 ]
    [[ "$output" == *'head_sha='* ]]
    [[ "$output" == *'repository_id=123'* ]]
    [[ "$output" == *'scanner_version=test'* ]]
    [[ "$output" == *'attested_at='* ]]
    [[ "$output" == *'hosted_surface_sha256='* ]]
}

@test "malformed canonical regex is an invocation error" {
    write_allowlist
    write_clean_proof
    printf '[unterminated\n' >"$REGEX"
    run_gate
    [ "$status" -eq 2 ]
    [[ "$output" == *'invalid_policy'* ]]
}

@test "invalid ref is an invocation error" {
    write_allowlist
    write_clean_proof
    run "$SCRIPT" --repo "$REPO" --github-repo owner/repo --ref refs/heads/missing --allowlist "$ALLOWLIST" \
        --regex "$REGEX" --secret-report "$REPORT" --secret-proof "$PROOF"
    [ "$status" -eq 2 ]
    [[ "$output" == *'invalid_ref'* ]]
}
