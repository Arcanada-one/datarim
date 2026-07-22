#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

usage() {
    printf '%s\n' 'usage: check-public-repository-boundary.sh --repo DIR --github-repo OWNER/REPO --ref REF --allowlist FILE --regex FILE --secret-report FILE --secret-proof FILE [--format text|json]'
}

repo='' github_repo='' ref='' allowlist='' regex='' report='' proof='' format='text'
while (($#)); do
    case "$1" in
        --repo) repo="${2-}"; shift 2 ;;
        --github-repo) github_repo="${2-}"; shift 2 ;;
        --ref) ref="${2-}"; shift 2 ;;
        --allowlist) allowlist="${2-}"; shift 2 ;;
        --regex) regex="${2-}"; shift 2 ;;
        --secret-report) report="${2-}"; shift 2 ;;
        --secret-proof) proof="${2-}"; shift 2 ;;
        --format) format="${2-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

failures=''
add_failure() { failures+="${1}"$'\n'; }
hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi
}
hash_stream() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'; else shasum -a 256 | awk '{print $1}'; fi
}
emit() {
    local decision="$1" code="$2" tracked="${3:-0}" commits="${4:-0}" blobs="${5:-0}" bytes="${6:-0}"
    local unique
    unique="$(printf '%s' "$failures" | awk 'NF && !seen[$0]++' | jq -Rsc 'split("\n") | map(select(length>0))')"
    if [[ "$format" == json ]]; then
        jq -cn --arg decision "$decision" --arg sha "${sha:-}" --arg tree "${tree:-}" \
          --arg refs "${refs_hash:-}" --arg public_refs "${public_refs_hash:-}" --arg allowlist "${allowlist_hash:-}" --arg policy "${policy_hash:-}" \
          --arg report "${report_hash:-}" --arg repository "${repository_identity_sha256:-}" --arg attested_at "${attested_at:-}" \
          --arg repository_id "${repository_id:-}" --arg name_with_owner "${name_with_owner:-}" \
          --arg scanner_version "${live_version:-}" --arg hosted_surface "${hosted_surface_hash:-}" \
          --argjson failures "$unique" \
          --argjson tracked "$tracked" --argjson commits "$commits" --argjson blobs "$blobs" --argjson bytes "$bytes" \
          --argjson hosted_items "${hosted_items:-0}" --argjson hosted_pages "${hosted_pages:-0}" --argjson hosted_bytes "${hosted_bytes:-0}" \
          '{decision:$decision,head_sha:$sha,tree_id:$tree,refs_sha256:$refs,public_refs_sha256:$public_refs,allowlist_sha256:$allowlist,policy_sha256:$policy,report_sha256:$report,hosted_surface_sha256:$hosted_surface,repository_identity_sha256:$repository,repository_id:$repository_id,name_with_owner:$name_with_owner,scanner_version:$scanner_version,attested_at:$attested_at,failures:$failures,tracked_files:$tracked,reachable_commits:$commits,scanned_blobs:$blobs,scanned_bytes:$bytes,hosted_items:$hosted_items,hosted_pages:$hosted_pages,hosted_bytes:$hosted_bytes}'
    else
        printf 'decision=%s head_sha=%s tree_id=%s refs_sha256=%s public_refs_sha256=%s allowlist_sha256=%s policy_sha256=%s report_sha256=%s hosted_surface_sha256=%s repository_identity_sha256=%s repository_id=%s name_with_owner=%s scanner_version=%s attested_at=%s tracked_files=%s reachable_commits=%s scanned_blobs=%s scanned_bytes=%s hosted_items=%s hosted_pages=%s hosted_bytes=%s failures=%s\n' \
          "$decision" "${sha:-}" "${tree:-}" "${refs_hash:-}" "${public_refs_hash:-}" "${allowlist_hash:-}" "${policy_hash:-}" "${report_hash:-}" "${hosted_surface_hash:-}" "${repository_identity_sha256:-}" "${repository_id:-}" "${name_with_owner:-}" "${live_version:-}" "${attested_at:-}" "$tracked" "$commits" "$blobs" "$bytes" "${hosted_items:-0}" "${hosted_pages:-0}" "${hosted_bytes:-0}" "$(printf '%s' "$failures" | awk 'NF && !seen[$0]++' | paste -sd, -)"
    fi
    exit "$code"
}

if ! command -v git >/dev/null 2>&1 || ! command -v gh >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1 || ! command -v gitleaks >/dev/null 2>&1 || \
   ! command -v file >/dev/null 2>&1 || ! command -v strings >/dev/null 2>&1; then
    add_failure missing_tool
    emit error 2
fi
[[ "$format" == text || "$format" == json ]] || { add_failure invalid_format; emit error 2; }
[[ -n "$repo" && "$github_repo" =~ ^[^/[:space:]]+/[^/[:space:]]+$ && -n "$ref" && -f "$allowlist" && -f "$regex" && -f "$report" && -f "$proof" ]] || { add_failure missing_input; emit error 2; }
[[ ! -L "$repo" && ! -L "$repo/.git" ]] || { add_failure invalid_repository; emit error 2; }
git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { add_failure invalid_repository; emit error 2; }
repo_physical="$(cd "$repo" && pwd -P)"
root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || { add_failure invalid_repository; emit error 2; }
root_physical="$(cd "$root" && pwd -P)"
[[ "$root_physical" == "$repo_physical" ]] || { add_failure noncanonical_repository_root; emit error 2; }
sha="$(git -C "$repo" rev-parse --verify "${ref}^{commit}" 2>/dev/null)" || { add_failure invalid_ref; emit error 2; }
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { add_failure invalid_ref; emit error 2; }
tree="$(git -C "$repo" rev-parse "${sha}^{tree}")"
[[ -z "$(git -C "$repo" status --porcelain=v1 --untracked-files=all)" ]] || add_failure dirty_worktree

tmpdir="$(mktemp -d -t public-boundary.XXXXXX)"
# shellcheck disable=SC2329
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT
actual="$tmpdir/actual"
manifest="$tmpdir/manifest"
patterns="$tmpdir/patterns"
binary_patterns="$tmpdir/binary-patterns"
refs="$tmpdir/refs"
public_refs="$tmpdir/public-refs"

# Validate the manifest before using it. Each line is one normalized POSIX path.
if [[ ! -s "$allowlist" ]] || LC_ALL=C grep -q $'\r' "$allowlist" || awk '
  /^$/ || /^\// || /^-/ || /(^|\/)\.\.($|\/)/ || /(^|\/)\.git($|\/)/ || /^\.\// || /[[:cntrl:]]/ { bad=1 }
  { if (seen[$0]++) bad=1 }
  END { exit bad ? 0 : 1 }
' "$allowlist"; then
    add_failure unsafe_allowlist_entry
    emit error 2
fi

: >"$actual"
while IFS= read -r -d '' path; do printf '%s\n' "$path" >>"$actual"; done < <(git -C "$repo" ls-tree -r -z --name-only "$sha")
LC_ALL=C sort "$actual" -o "$actual"
LC_ALL=C sort "$allowlist" >"$manifest"
tracked="$(wc -l <"$actual" | tr -d ' ')"
cmp -s "$actual" "$manifest" || add_failure tree_manifest_mismatch

while IFS=$'\t' read -r metadata path; do
    mode="${metadata%% *}"
    [[ "$mode" != 120000 && "$mode" != 160000 ]] || add_failure unsupported_git_entry
done < <(git -C "$repo" ls-tree -r "$sha")

git -C "$repo" for-each-ref --format='%(refname)=%(objectname)' | LC_ALL=C sort >"$refs"
[[ -s "$refs" ]] || add_failure zero_scope
refs_hash="$(hash_file "$refs")"
git -C "$repo" for-each-ref --format='%(refname)=%(objectname)' refs/heads refs/tags | LC_ALL=C sort >"$public_refs"
[[ -s "$public_refs" ]] || add_failure zero_scope
public_refs_hash="$(hash_file "$public_refs")"
allowlist_hash="$(hash_file "$allowlist")"
policy_hash="$(hash_file "$regex")"
report_hash="$(hash_file "$report")"

# Re-fetch immutable GitHub identity and every branch/tag ref before disclosure.
github_json="$(gh api "/repos/${github_repo}" 2>/dev/null)" || { add_failure hosting_api_error; emit error 2 "$tracked"; }
repository_id="$(jq -r '.id | tostring' <<<"$github_json")"
name_with_owner="$(jq -r '.full_name // ""' <<<"$github_json")"
[[ "$repository_id" =~ ^[1-9][0-9]*$ && "$name_with_owner" == "$github_repo" ]] || { add_failure hosting_api_error; emit error 2 "$tracked"; }
repository_identity_sha256="$(printf '%s:%s' "$repository_id" "$name_with_owner" | hash_stream)"
remote_refs_json="$(gh api --paginate --slurp "/repos/${github_repo}/git/matching-refs/" 2>/dev/null)" || { add_failure hosting_api_error; emit error 2 "$tracked"; }
remote_public_refs_hash="$(jq -r '.[][] | select(.ref | startswith("refs/heads/") or startswith("refs/tags/")) | "\(.ref)=\(.object.sha)"' <<<"$remote_refs_json" | LC_ALL=C sort | hash_stream)" || { add_failure hosting_api_error; emit error 2 "$tracked"; }
[[ "$remote_public_refs_hash" == "$public_refs_hash" ]] || add_failure public_ref_drift

jq -e '
  .schema_version == 1 and .scanner == "gitleaks" and (.scanner_version | type == "string" and length > 0) and
  .scope == "all-refs" and (.head_sha | type == "string") and (.tree_id | type == "string") and
  (.refs_sha256 | type == "string") and (.allowlist_sha256 | type == "string") and
  (.policy_sha256 | type == "string") and (.report_sha256 | type == "string") and
  (.repository_identity_sha256 | type == "string") and (.public_refs_sha256 | type == "string") and (.attested_at | type == "string" and length > 0) and
  (.exit_code | type == "number") and (.findings | type == "number")
' "$proof" >/dev/null 2>&1 || { add_failure invalid_secret_proof; emit error 2 "$tracked"; }
jq -e 'type == "array"' "$report" >/dev/null 2>&1 || { add_failure invalid_secret_report; emit error 2 "$tracked"; }
proof_attested_at="$(jq -r '.attested_at' "$proof")"
[[ "$proof_attested_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || { add_failure invalid_secret_proof; emit error 2 "$tracked"; }
if ! jq -e --arg sha "$sha" --arg tree "$tree" --arg refs "$refs_hash" --arg public_refs "$public_refs_hash" --arg allow "$allowlist_hash" \
    --arg policy "$policy_hash" --arg report "$report_hash" --arg repository "$repository_identity_sha256" '
      .head_sha==$sha and .tree_id==$tree and .refs_sha256==$refs and .allowlist_sha256==$allow and
      .public_refs_sha256==$public_refs and .policy_sha256==$policy and .report_sha256==$report and .repository_identity_sha256==$repository
    ' "$proof" >/dev/null; then
    add_failure proof_binding_mismatch
fi
proof_findings="$(jq -r '.findings' "$proof")"
proof_exit="$(jq -r '.exit_code' "$proof")"
report_findings="$(jq 'length' "$report")"
if ((proof_findings != 0 || proof_exit != 0 || report_findings != 0)); then add_failure secret_scan_findings; fi

# Re-run the substantive scanner; a caller-authored proof is never sufficient.
live_report="$tmpdir/gitleaks-live.json"
set +e
gitleaks git --no-banner --redact --report-format json --report-path "$live_report" "$repo" >/dev/null 2>&1
live_scan_exit=$?
set -e
[[ -f "$live_report" ]] || { add_failure secret_scanner_error; emit error 2 "$tracked"; }
jq -e 'type == "array"' "$live_report" >/dev/null 2>&1 || { add_failure secret_scanner_error; emit error 2 "$tracked"; }
((live_scan_exit <= 1)) || { add_failure secret_scanner_error; emit error 2 "$tracked"; }
live_report_hash="$(hash_file "$live_report")"
live_findings="$(jq 'length' "$live_report")"
live_version="$(gitleaks version 2>/dev/null | tail -n 1 | tr -d '[:space:]')"
proof_version="$(jq -r '.scanner_version' "$proof")"
if [[ "$live_report_hash" != "$report_hash" || "$live_version" != "$proof_version" ]]; then add_failure proof_binding_mismatch; fi
if ((live_scan_exit != 0 || live_findings != 0)); then add_failure secret_scan_findings; fi

awk 'NF && $0 !~ /^#/' "$regex" >"$patterns"
[[ -s "$patterns" ]] || { add_failure invalid_policy; emit error 2 "$tracked"; }
while IFS= read -r pattern; do
    if printf '' | grep -E "$pattern" >/dev/null 2>&1; then :; else
        regex_exit=$?
        ((regex_exit == 1)) || { add_failure invalid_policy; emit error 2 "$tracked"; }
    fi
done <"$patterns"
awk 'index($0, "\\bM[") != 1' "$patterns" >"$binary_patterns" || { add_failure invalid_policy; emit error 2 "$tracked"; }

scan_query_keys() {
    local source="$1" normalized="$tmpdir/query-normalized"
    sed -E \
      -e 's/&amp;/\&/g' \
      -e 's/%2[dD]/-/g' \
      -e 's/%3[fF]/?/g' \
      -e 's/%26/\&/g' \
      -e 's/%3[dD]/=/g' \
      -e 's/%5[fF]/_/g' "$source" | tr '[:upper:]' '[:lower:]' >"$normalized"
    grep -E -q '([?&])(client[-_]?secret|secret|credential|token|signature|sig|security[-_]?token|access[-_]?token|api[-_]?key|access[-_]?key|auth|session|policy|key[-_]?pair[-_]?id|x-amz-[a-z0-9_-]+|x-goog-[a-z0-9_-]+)=' "$normalized"
}

scan_text_surface() {
    local source="$1" forbidden_code="$2" path_normalized="$tmpdir/hosted-path-normalized"
    if grep -E -q -f "$patterns" "$source"; then add_failure "$forbidden_code"; else
        local grep_exit=$?; ((grep_exit == 1)) || { add_failure invalid_policy; emit error 2 "$tracked"; }
    fi
    sed -e 's#/home/runner/#/github-runner/#g' -e 's#/home/dependabot/#/github-dependabot/#g' "$source" >"$path_normalized"
    if grep -E -q '(/Users/|/home/|/root/|[A-Za-z]:\\Users\\|file://|/mnt/[A-Za-z]/Users/)' "$path_normalized" 2>/dev/null; then add_failure "private_absolute_path_hosted_${source##*/}"; fi
    if scan_query_keys "$source"; then add_failure "credential_query_key_hosted_${source##*/}"; else
        local query_exit=$?; ((query_exit == 1)) || { add_failure hosted_scan_error; emit error 2 "$tracked"; }
    fi
}

fetch_hosted_state() {
    local target="$1" id number attempt attempts comment_id
    mkdir -p "$target"
    gh api "/repos/${github_repo}" 2>/dev/null | jq -cS . >"$target/repository.json" || return 1
    gh api --paginate --slurp "/repos/${github_repo}/actions/runs?per_page=100" 2>/dev/null | jq -cS . >"$target/actions-runs.json" || return 1
    gh api --paginate --slurp "/repos/${github_repo}/actions/artifacts?per_page=100" 2>/dev/null | jq -cS . >"$target/actions-artifacts.json" || return 1
    gh api --paginate --slurp "/repos/${github_repo}/releases?per_page=100" 2>/dev/null | jq -cS . >"$target/releases.json" || return 1
    gh api --paginate --slurp "/repos/${github_repo}/issues?state=all&per_page=100" 2>/dev/null | jq -cS . >"$target/issues.json" || return 1

    if jq -e '.has_discussions == true' "$target/repository.json" >/dev/null; then
        gh api --paginate --slurp "/repos/${github_repo}/discussions?per_page=100" 2>/dev/null | jq -cS . >"$target/discussions.json" || return 1
    else
        printf '[]\n' >"$target/discussions.json"
    fi

    if jq -e '.has_wiki == true or .has_pages == true' "$target/repository.json" >/dev/null; then add_failure unsupported_hosted_surface; fi
    [[ "$(jq '.[0].total_count // -1' "$target/actions-runs.json")" -eq "$(jq '[.[] | .workflow_runs[]?] | length' "$target/actions-runs.json")" ]] || return 1
    [[ "$(jq '.[0].total_count // -1' "$target/actions-artifacts.json")" -eq "$(jq '[.[] | .artifacts[]?] | length' "$target/actions-artifacts.json")" ]] || return 1
    if jq -e '[.[] | .artifacts[]?] | length > 0' "$target/actions-artifacts.json" >/dev/null; then add_failure unsupported_hosted_surface; fi
    if jq -e '[.[][]? | .assets[]?] | length > 0' "$target/releases.json" >/dev/null; then add_failure unsupported_hosted_surface; fi
    if jq -e '[.[] | .workflow_runs[]? | select(.status != "completed")] | length > 0' "$target/actions-runs.json" >/dev/null; then add_failure incomplete_hosted_surface; fi

    while IFS=$'\t' read -r id attempts; do
        [[ "$id" =~ ^[1-9][0-9]*$ && "$attempts" =~ ^[1-9][0-9]*$ ]] || return 1
        for ((attempt=1; attempt<=attempts; attempt++)); do
            gh api --paginate --slurp "/repos/${github_repo}/actions/runs/${id}/attempts/${attempt}/jobs?per_page=100" 2>/dev/null | jq -cS . >"$target/action-jobs-${id}-attempt-${attempt}.json" || return 1
            [[ "$(jq '.[0].total_count // -1' "$target/action-jobs-${id}-attempt-${attempt}.json")" -eq "$(jq '[.[] | .jobs[]?] | length' "$target/action-jobs-${id}-attempt-${attempt}.json")" ]] || return 1
            if jq -e '[.[] | .jobs[]?.steps[]? | select(.status == "completed")] | length > 0' "$target/action-jobs-${id}-attempt-${attempt}.json" >/dev/null; then
                gh run view "$id" --attempt "$attempt" --repo "$github_repo" --log >"$target/action-log-${id}-attempt-${attempt}.txt" 2>/dev/null || return 1
            fi
        done
    done < <(jq -r '.[] | .workflow_runs[]? | [.id, (.run_attempt // 1)] | @tsv' "$target/actions-runs.json")

    while IFS= read -r number; do
        [[ "$number" =~ ^[1-9][0-9]*$ ]] || return 1
        gh api --paginate --slurp "/repos/${github_repo}/issues/${number}/comments?per_page=100" 2>/dev/null | jq -cS . >"$target/issue-comments-${number}.json" || return 1
    done < <(jq -r '.[][]? | select((.comments // 0) > 0) | .number' "$target/issues.json")

    while IFS= read -r number; do
        [[ "$number" =~ ^[1-9][0-9]*$ ]] || return 1
        gh api --paginate --slurp "/repos/${github_repo}/pulls/${number}/reviews?per_page=100" 2>/dev/null | jq -cS . >"$target/pull-reviews-${number}.json" || return 1
        gh api --paginate --slurp "/repos/${github_repo}/pulls/${number}/comments?per_page=100" 2>/dev/null | jq -cS . >"$target/pull-comments-${number}.json" || return 1
    done < <(jq -r '.[][]? | select(.pull_request != null) | .number' "$target/issues.json")

    while IFS= read -r number; do
        [[ "$number" =~ ^[1-9][0-9]*$ ]] || return 1
        gh api --paginate --slurp "/repos/${github_repo}/discussions/${number}/comments?per_page=100" 2>/dev/null | jq -cS . >"$target/discussion-comments-${number}.json" || return 1
        while IFS= read -r comment_id; do
            [[ "$comment_id" =~ ^[1-9][0-9]*$ ]] || return 1
            gh api --paginate --slurp "/repos/${github_repo}/discussions/${number}/comments/${comment_id}/replies?per_page=100" 2>/dev/null | jq -cS . >"$target/discussion-replies-${number}-${comment_id}.json" || return 1
        done < <(jq -r '.[][]? | .id' "$target/discussion-comments-${number}.json")
    done < <(jq -r '.[][]? | select((.comments // 0) > 0) | .number' "$target/discussions.json")
}

hash_hosted_state() {
    local target="$1" item
    for item in "$target"/*; do printf '%s=%s\n' "${item##*/}" "$(hash_file "$item")"; done | LC_ALL=C sort | hash_stream
}

hosted_initial="$tmpdir/hosted-initial"
fetch_hosted_state "$hosted_initial" || { add_failure hosting_api_error; emit error 2 "$tracked"; }
hosted_initial_hash="$(hash_hosted_state "$hosted_initial")"

commits="$(git -C "$repo" rev-list --all | awk 'NF' | sort -u | wc -l | tr -d ' ')"
((commits > 0)) || add_failure zero_scope

# Scan ref names and commit/tag identity metadata without ever emitting matches.
metadata="$tmpdir/metadata"
{
    git -C "$repo" for-each-ref --format='%(refname)'
    git -C "$repo" log --all --format='%an%n%ae%n%cn%n%ce%n%B'
    git -C "$repo" for-each-ref --format='%(contents)' refs/tags
} >"$metadata" 2>/dev/null || add_failure unreadable_metadata
if grep -E -q -f "$patterns" "$metadata"; then add_failure forbidden_public_reference; else
    grep_exit=$?; ((grep_exit == 1)) || { add_failure invalid_policy; emit error 2 "$tracked"; }
fi
if grep -E -q '(/Users/|/home/|/root/|[A-Za-z]:\\Users\\|file://|/mnt/[A-Za-z]/Users/)' "$metadata" 2>/dev/null; then add_failure private_absolute_path; fi
blobs=0
bytes=0
while IFS=' ' read -r oid _path; do
    [[ "$oid" != missing* ]] || { add_failure missing_object; continue; }
    type="$(git -C "$repo" cat-file -t "$oid" 2>/dev/null)" || { add_failure unreadable_object; continue; }
    [[ "$type" == blob ]] || continue
    if [[ "${_path:-}" =~ (^|/)(\.git)(/|$) ]] || [[ "${_path:-}" =~ /\.\./ ]]; then add_failure unsafe_history_path; fi
    if printf '%s\n' "${_path:-}" | grep -E -q -f "$patterns"; then add_failure forbidden_public_reference; else
        grep_exit=$?; ((grep_exit == 1)) || { add_failure invalid_policy; emit error 2 "$tracked"; }
    fi
    if printf '%s\n' "${_path:-}" | grep -E -q '(/Users/|/home/|/root/|[A-Za-z]:\\Users\\|file://|/mnt/[A-Za-z]/Users/)'; then add_failure private_absolute_path; fi
    size="$(git -C "$repo" cat-file -s "$oid" 2>/dev/null)" || { add_failure unreadable_object; continue; }
    blobs=$((blobs + 1)); bytes=$((bytes + size))
    blob="$tmpdir/blob"
    git -C "$repo" cat-file blob "$oid" >"$blob" || { add_failure unreadable_object; continue; }
    ((size == 0)) && continue
    if grep -q '^version https://git-lfs.github.com/spec/v1$' "$blob"; then add_failure unsupported_blob; continue; fi
    if ((size > 5242880)); then add_failure unsupported_blob; continue; fi
    mime="$(file -b --mime-encoding "$blob" 2>/dev/null || true)"
    scan_target="$blob"
    case "$mime" in
        us-ascii|utf-8) ;;
        binary)
            mime_type="$(file -b --mime-type "$blob" 2>/dev/null || true)"
            case "$mime_type" in image/png|image/jpeg|image/gif|image/webp) ;; *) add_failure unsupported_blob; continue ;; esac
            command -v strings >/dev/null 2>&1 || { add_failure missing_tool; continue; }
            scan_target="$tmpdir/blob-strings"
            strings -a "$blob" >"$scan_target" || { add_failure unreadable_object; continue; }
            scan_patterns="$binary_patterns"
            ;;
        *) add_failure unsupported_blob; continue ;;
    esac
    scan_patterns="${scan_patterns:-$patterns}"
    if grep -E -q -f "$scan_patterns" "$scan_target"; then add_failure forbidden_public_reference; else
        grep_exit=$?; ((grep_exit == 1)) || { add_failure invalid_policy; emit error 2 "$tracked"; }
    fi
    unset scan_patterns
    if grep -E -q '(/Users/|/home/|/root/|[A-Za-z]:\\Users\\|file://|/mnt/[A-Za-z]/Users/)' "$scan_target" 2>/dev/null; then add_failure private_absolute_path; fi
    if scan_query_keys "$scan_target"; then add_failure "credential_query_key_local_${oid:0:12}"; else
        query_exit=$?; ((query_exit == 1)) || { add_failure invalid_policy; emit error 2 "$tracked"; }
    fi
done < <(git -C "$repo" rev-list --objects --all)
((blobs > 0 && bytes > 0)) || add_failure zero_scope

# Collect the provider surfaces a second time. Identical digests make the
# evidence a bounded snapshot; any concurrent edit, run, comment, or log
# change fails closed instead of crossing the visibility boundary unaudited.
hosted_final="$tmpdir/hosted-final"
fetch_hosted_state "$hosted_final" || { add_failure hosting_api_error; emit error 2 "$tracked" "$commits" "$blobs" "$bytes"; }
hosted_surface_hash="$(hash_hosted_state "$hosted_final")"
[[ "$hosted_surface_hash" == "$hosted_initial_hash" ]] || add_failure hosted_surface_drift
hosted_items="$((1 +
    $(jq '[.[] | .workflow_runs[]?] | length' "$hosted_final/actions-runs.json") +
    $(jq '[.[] | .artifacts[]?] | length' "$hosted_final/actions-artifacts.json") +
    $(jq '[.[][]?] | length' "$hosted_final/releases.json") +
    $(jq '[.[][]?] | length' "$hosted_final/issues.json") +
    $(jq '[.[][]?] | length' "$hosted_final/discussions.json")
))"
hosted_pages="$((
    $(jq 'length' "$hosted_final/actions-runs.json") +
    $(jq 'length' "$hosted_final/actions-artifacts.json") +
    $(jq 'length' "$hosted_final/releases.json") +
    $(jq 'length' "$hosted_final/issues.json") +
    $(jq 'length' "$hosted_final/discussions.json")
))"
hosted_bytes=0
for hosted_file in "$hosted_final"/*; do
    hosted_bytes=$((hosted_bytes + $(wc -c <"$hosted_file" | tr -d ' ')))
    scan_text_surface "$hosted_file" forbidden_hosted_surface
    case "${hosted_file##*/}" in
        action-jobs-*.json)
            hosted_items=$((hosted_items + $(jq '[.[] | .jobs[]?] | length' "$hosted_file") + $(jq '[.[] | .jobs[]?.steps[]?] | length' "$hosted_file")))
            hosted_pages=$((hosted_pages + $(jq 'length' "$hosted_file")))
            ;;
        action-log-*.txt) hosted_items=$((hosted_items + 1)) ;;
        issue-comments-*.json|pull-reviews-*.json|pull-comments-*.json|discussion-comments-*.json|discussion-replies-*.json)
            hosted_items=$((hosted_items + $(jq '[.[][]?] | length' "$hosted_file")))
            hosted_pages=$((hosted_pages + $(jq 'length' "$hosted_file")))
            ;;
    esac
done

# The final repository/ref fetch closes the TOCTOU window after every local
# and hosted scan. Only the exact public branch/tag set may be attested.
github_final="$(gh api "/repos/${github_repo}" 2>/dev/null)" || { add_failure hosting_api_error; emit error 2 "$tracked" "$commits" "$blobs" "$bytes"; }
final_repository_id="$(jq -r '.id | tostring' <<<"$github_final")"
final_name_with_owner="$(jq -r '.full_name // ""' <<<"$github_final")"
[[ "$final_repository_id" == "$repository_id" && "$final_name_with_owner" == "$name_with_owner" ]] || add_failure repository_identity_drift
remote_refs_final="$(gh api --paginate --slurp "/repos/${github_repo}/git/matching-refs/" 2>/dev/null)" || { add_failure hosting_api_error; emit error 2 "$tracked" "$commits" "$blobs" "$bytes"; }
remote_public_refs_hash_final="$(jq -r '.[][] | select(.ref | startswith("refs/heads/") or startswith("refs/tags/")) | "\(.ref)=\(.object.sha)"' <<<"$remote_refs_final" | LC_ALL=C sort | hash_stream)" || { add_failure hosting_api_error; emit error 2 "$tracked" "$commits" "$blobs" "$bytes"; }
[[ "$remote_public_refs_hash_final" == "$remote_public_refs_hash" && "$remote_public_refs_hash_final" == "$public_refs_hash" ]] || add_failure public_ref_drift
attested_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

if [[ -n "$failures" ]]; then emit fail 1 "$tracked" "$commits" "$blobs" "$bytes"; fi
emit pass 0 "$tracked" "$commits" "$blobs" "$bytes"
