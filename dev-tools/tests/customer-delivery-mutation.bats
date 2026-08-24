#!/usr/bin/env bats

setup() {
    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    SCRIPT="${REPO_ROOT}/dev-tools/check-customer-delivery.sh"
    FUNCTIONAL_TEST="${BATS_TEST_DIRNAME}/check-customer-delivery.bats"
    VALIDATOR_PYTHON="${CUSTOMER_DELIVERY_PYTHON:-/usr/bin/python3}"
    PYTHON="${CUSTOMER_DELIVERY_TEST_PYTHON:-$VALIDATOR_PYTHON}"
    export CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON"
    if [[ "$(/usr/bin/uname -s)" == Darwin ]]; then
        [[ "${CUSTOMER_TEST_PYTHON_RUNTIME:-}" == /* \
            && "${CUSTOMER_TEST_PYTHON_SITE:-}" == /* ]] \
            || { echo "ERROR: Darwin mutation fixtures require explicit runtime and site" >&2; return 1; }
        export CUSTOMER_TEST_PYTHON_RUNTIME CUSTOMER_TEST_PYTHON_SITE
    fi
    [[ "$PYTHON" == /* && -x "$PYTHON" && ! -d "$PYTHON" \
        && "$VALIDATOR_PYTHON" == /* && -x "$VALIDATOR_PYTHON" && ! -d "$VALIDATOR_PYTHON" ]] \
        || { echo "ERROR: test and validator Python paths must be absolute executables" >&2; return 1; }
    [ -f "$SCRIPT" ] || { echo "ERROR: validator missing: $SCRIPT" >&2; return 1; }
    [ -f "$FUNCTIONAL_TEST" ] || { echo "ERROR: functional tests missing: $FUNCTIONAL_TEST" >&2; return 1; }
}

assert_baseline_green() {
    local filter="$1"
    if [ "$status" -ne 0 ]; then
        printf 'HARNESS_INVALID:baseline_failed filter=%s status=%s output=%s\n' \
            "$filter" "$status" "$output"
        return 1
    fi
}

expected_red_lines() {
    "$PYTHON" - "$FUNCTIONAL_TEST" "$1" <<'PY'
import re
import sys
path, name = sys.argv[1:]
lines = open(path, encoding="utf-8").read().splitlines()
header = f'@test "{name}" {{'
try:
    start = lines.index(header)
except ValueError as error:
    raise SystemExit(f"expected RED target missing: {name}") from error
end = next((index for index in range(start + 1, len(lines)) if lines[index].startswith('@test "')), len(lines))
status_lines = [
    index for index in range(start + 1, end)
    if re.match(r'^\s*(?:if )?\[ "\$(?:status|result)" ', lines[index])
]
if not status_lines:
    raise SystemExit(f"expected RED assertion missing: {name}")
allowed = []
for assertion_start in status_lines:
    allowed.append(assertion_start + 1)
    cursor = assertion_start + 1
    while cursor < end and lines[cursor - 1].rstrip().endswith("\\"):
        allowed.append(cursor + 1)
        cursor += 1
allowed.extend(
    index + 1 for index in range(start + 1, end)
    if lines[index].strip() == "return 1"
)
print(",".join(str(value) for value in allowed))
PY
}

assert_attributed_mutant_kill() {
    local marker="$1" filter="$2" expected_lines="$3"
    local nested_status="$4" nested_output="$5" reported line matched=0
    if [ "$nested_status" -eq 0 ]; then
        printf 'SURVIVED_MUTANT:%s output=%s\n' "$marker" "$nested_output"
        return 1
    fi
    if [ "$nested_status" -eq 124 ] \
        || [[ "$nested_output" == *"setup_file failed"* ]] \
        || [[ "$nested_output" == *"syntax error"* ]] \
        || [[ "$nested_output" == *"BATS_TEST_TIMEOUT"* ]] \
        || [[ "$nested_output" == *"HARNESS_INVALID:"* ]] \
        || [ "$(printf '%s\n' "$nested_output" | awk '$0 == "1..1" { count++ } END { print count+0 }')" -ne 1 ] \
        || [ "$(printf '%s\n' "$nested_output" | awk -v target="not ok 1 ${filter}" '$0 == target { count++ } END { print count+0 }')" -ne 1 ]; then
        printf 'HARNESS_INVALID:%s:execution-contract output=%s\n' \
            "$marker" "$nested_output"
        return 1
    fi
    reported="$(printf '%s\n' "$nested_output" | sed -n 's/^# (in test file .* line \([0-9][0-9]*\))$/\1/p')"
    IFS=',' read -r -a expected_array <<<"$expected_lines"
    while IFS= read -r line; do
        for expected in "${expected_array[@]}"; do
            if [ "$line" = "$expected" ]; then
                matched=1
            fi
        done
    done <<<"$reported"
    if [ "$matched" -ne 1 ]; then
        printf 'HARNESS_INVALID:%s:wrong-assertion:expected=%s:reported=%s\n' \
            "$marker" "$expected_lines" "$reported"
        return 1
    fi
    "$PYTHON" -c \
        'import hashlib,sys; print(f"RED_SENTINEL:{sys.argv[1]}:{hashlib.sha256(sys.argv[2].encode()).hexdigest()}")' \
        "$marker" "${marker}|${filter}|${expected_lines}"
}

@test "every U4 production validation branch is killed by its focused regression" {
    local pair edge filter framework mutant expected_lines
    local -a pairs=(
        'requirement|receipt source quote digests exactly bind every linked source quote'
        'selected_knowledge|receipt selected knowledge exactly equals the accepted selection'
        'implementation_delta|implementation delta task is bound to selected implementation task'
        'red_green|implementation starts no later than RED evidence'
        'merged_revision|merged revision must be one of the accepted implementation revisions'
        'deployed_revision|production deployment SHA and digest must equal the merged accepted revision'
        'live_evidence|live production identity exactly equals accepted product identity'
        'customer_disposition|customer disposition must agree with the accepted requirement disposition'
        'nonblank|authorized disposition reseal cannot make whitespace U4 evidence MET'
    )

    for pair in "${pairs[@]}"; do
        edge="${pair%%|*}"
        filter="${pair#*|}"
        expected_lines="$(expected_red_lines "$filter")" || return 1

        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_baseline_green "$filter" || return 1

        framework="${BATS_TEST_TMPDIR}/framework-${edge}"
        mutant="${framework}/dev-tools/check-customer-delivery.sh"
        mkdir -p "${framework}/dev-tools" "${framework}/config"
        cp "$SCRIPT" "$mutant" || return 1
        cp "${REPO_ROOT}/config/customer-requirement.schema.json" \
            "${REPO_ROOT}/config/customer-delivery-receipt.schema.json" \
            "${REPO_ROOT}/config/review-evolution.schema.json" \
            "${framework}/config/" || return 1
        "$PYTHON" - "$mutant" "$edge" <<'PY' || return 1
import sys

path, edge = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    lines = handle.readlines()
marker = f"# U4_RULE:{edge}"
matches = [index for index, line in enumerate(lines) if marker in line]
if len(matches) != 1:
    raise SystemExit(f"real production mutation seam missing or ambiguous for {edge}")
del lines[matches[0]]
with open(path, "w", encoding="utf-8") as handle:
    handle.writelines(lines)
PY
        chmod +x "$mutant"

        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
            bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_attributed_mutant_kill "$edge" "$filter" "$expected_lines" \
            "$status" "$output" || return 1
        printf 'mutant=%s killed_by=%s\n' "$edge" "$filter"
    done
}

@test "every security-critical production branch is killed by its focused regression" {
    local pair marker filter framework mutant expected_lines mutation_index=0
    local shard="${CUSTOMER_DELIVERY_SECURITY_SHARD:-all}"
    local security_range="${CUSTOMER_DELIVERY_SECURITY_RANGE:-}"
    local -a pairs=(
        'invariant_dispatch|semantic implementation dispatch cannot lose a registered rule'
        'registry_locator|trusted registry locator owner anchor structure and receipt reference are pinned'
        'registry_owner|trusted registry locator owner anchor structure and receipt reference are pinned'
        'registry_anchor|trusted registry locator owner anchor structure and receipt reference are pinned'
        'registry_structure|trusted registry locator owner anchor structure and receipt reference are pinned'
        'registry_duplicate|trusted registry duplicates conflicts and invalid validity windows fail closed'
        'registry_conflict|trusted registry duplicates conflicts and invalid validity windows fail closed'
        'registry_window|trusted registry duplicates conflicts and invalid validity windows fail closed'
        'registry_order|trusted registry entry order is authenticated before key lookup'
        'registry_digest|trusted registry canonical digest is verified before key lookup'
        'registry_signature|trusted registry signature is verified against the pinned root'
        'registry_receipt_ref|trusted registry locator owner anchor structure and receipt reference are pinned'
        'key_known|approval key identity role and existence are authorized before signature acceptance'
        'key_authority|approval key identity role and existence are authorized before signature acceptance'
        'key_role|approval key identity role and existence are authorized before signature acceptance'
        'key_active|authenticated leaf registry status and approval windows fail closed'
        'key_valid_from|authenticated leaf registry status and approval windows fail closed'
        'key_window|authenticated leaf registry status and approval windows fail closed'
        'artifact_signature|source and assertion signatures use raw digest Ed25519 framing'
        'source_tier_role|source tier role authorization and assertion authority identity are structural'
        'source_digest|source JCS digest and approval payload commitments are independently enforced'
        'source_approved_digest|source and assertion approval digests and assertion JCS are independently enforced'
        'source_approval_digest|source JCS digest and approval payload commitments are independently enforced'
        'assertion_digest|source and assertion approval digests and assertion JCS are independently enforced'
        'assertion_source_binding|source tier role authorization and assertion authority identity are structural'
        'assertion_approved_digest|source and assertion approval digests and assertion JCS are independently enforced'
        'assertion_approval_digest|source and assertion approval digests and assertion JCS are independently enforced'
        'source_prework_scope|authenticated source pre-work assignments are exact per requirement'
        'assertion_prework_binding|authenticated assertion pre-work assignment must equal its signed source assignment'
        'prework_epic_derivation|authenticated pre-work epic must be canonical for its task prefix'
        'acceptance_prework_binding|acceptance task must equal the authenticated pre-work assignment'
        'prework_knowledge_binding|post-work knowledge and start-time reseal cannot rewrite signed pre-work authority'
        'prework_started_at_binding|post-work knowledge and start-time reseal cannot rewrite signed pre-work authority'
        'receipt_prework_task_binding|post-work task epic and review reseal cannot reattribute signed pre-work authority'
        'receipt_prework_parent_binding|receipt task and requirement-set parent links are exact'
        'review_prework_task_binding|authenticated review task parent must equal the signed pre-work task'
        'source_history|source records are append-only against available Git history'
        'source_history_repo_required|bound repository whose Git probe fails is unavailable'
        'source_history_document_required|MET requires the requirement source itself in authoritative Git history'
        'source_history_shallow_rejected|shallow Git history cannot authorize customer delivery'
        'source_history_grafts_rejected|Git grafts cannot rewrite authoritative customer history'
        'source_history_alternates_rejected|Git object alternates cannot supply authoritative customer history'
        'source_history_parse_closed|historical malformed source record fails closed without traceback'
        'source_history_total_deadline|source history subprocesses share one total deadline'
        'source_history_commit_budget|source history commit scan is capped and fails closed'
        'source_history_output_budget|source history blob output is capped and fails closed'
        'source_history_stdout_stream_cap|source history stdout cap terminates producer before oversized output completes'
        'source_history_stderr_stream_cap|source history stderr cap terminates producer before oversized diagnostics complete'
        'unicode_document|nested YAML lone surrogate is deterministic JSON NOT_MET without traceback'
        'unicode_schema|trusted-registry lone surrogate is deterministic JSON ERROR without traceback'
        'unicode_top_boundary|top Unicode boundary returns deterministic JSON when scalar precheck is faulted'
        'coverage_digest|terminal disposition commits the full pre-disposition coverage chain'
        'disposition_digest|terminal disposition canonical and approval payload digests are independently bound'
        'disposition_approved_digest|terminal disposition canonical and approval payload digests are independently bound'
        'disposition_approval_digest|terminal disposition canonical and approval payload digests are independently bound'
        'registry_review_ref|originating review registry reference is pinned to the bundled registry'
        'review_digest|originating review digest binds every canonical review field'
        'review_approved_digest|originating review approved digest equals its canonical review digest'
        'review_approval_digest|originating review approval payload digest is canonical'
        'review_signature|originating review signature verifies over raw approval payload digest'
        'review_key_known|originating review rejects an unknown authority key'
        'review_key_authority|originating review authority identity equals its trusted key binding'
        'review_key_role|originating review authority role is allowed by its trusted key binding'
        'review_key_active|originating review rejects a revoked approval key'
        'review_key_valid_from|originating review rejects a not-yet-valid approval key'
        'review_key_window|originating review rejects an expired approval key'
        'review_observed_at|originating review observation cannot postdate review completion'
        'review_state_open|authenticated OPEN originating review blocks closure'
        'review_state_changes|authenticated CHANGES_REQUESTED originating review blocks closure'
        'review_requirement_binding|originating review requirement identity is cross-bound'
        'review_receipt_binding|originating review receipt identity is cross-bound'
        'task_cli_binding|signed delivery bundle cannot replay under another CLI task identity'
        'review_requirement_set_binding|signed requirement set cannot replay under a substituted outer set'
        'epic_receipt_binding|signed canonical epic identity rejects coordinated receipt and review parent replay'
        'epic_review_binding|authenticated review epic parent must equal the signed canonical epic'
        'input_bytes|oversized canonical input is rejected before YAML parsing'
        'cardinality_requirements|requirement cardinality is bounded before schema validation'
        'cardinality_records|source record cardinality is bounded before schema validation'
        'cardinality_evidence|evidence cardinality is bounded before schema validation'
        'cardinality_signatures|signature cardinality is bounded before schema validation'
        'validation_subprocess_output|OpenSSL version output is bounded before allocation'
        'validation_process_group_reap|OpenSSL deadline terminates stubborn descendant pipe holders'
    )

    for pair in "${pairs[@]}"; do
        ((mutation_index += 1))
        if [[ -n "$security_range" ]]; then
            [[ "$security_range" =~ ^([1-9][0-9]*)-([1-9][0-9]*)$ ]] \
                || { echo "ERROR: invalid CUSTOMER_DELIVERY_SECURITY_RANGE" >&2; return 2; }
            if ((mutation_index < BASH_REMATCH[1] || mutation_index > BASH_REMATCH[2])); then
                continue
            fi
        fi
        if [[ "$shard" == first && "$mutation_index" -gt 37 ]]; then
            continue
        fi
        if [[ "$shard" == second && "$mutation_index" -le 37 ]]; then
            continue
        fi
        if [[ "$shard" =~ ^q([1-4])$ ]]; then
            local quarter="${BASH_REMATCH[1]}"
            local lower=$(( (quarter - 1) * 21 + 1 ))
            local upper=$(( quarter * 21 ))
            if ((mutation_index < lower || mutation_index > upper)); then
                continue
            fi
        fi
        marker="${pair%%|*}"
        filter="${pair#*|}"
        expected_lines="$(expected_red_lines "$filter")" || return 1

        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_baseline_green "$filter" || return 1

        framework="${BATS_TEST_TMPDIR}/security-framework-${marker}"
        mutant="${framework}/dev-tools/check-customer-delivery.sh"
        mkdir -p "${framework}/dev-tools" "${framework}/config"
        cp "$SCRIPT" "$mutant" || return 1
        cp "${REPO_ROOT}/config/customer-requirement.schema.json" \
            "${REPO_ROOT}/config/customer-delivery-receipt.schema.json" \
            "${REPO_ROOT}/config/review-evolution.schema.json" \
            "${framework}/config/" || return 1
        "$PYTHON" - "$mutant" "$marker" <<'PY' || return 1
import sys

path, marker = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    lines = handle.readlines()
needle = f"# SECURITY_RULE:{marker}"
matches = [index for index, line in enumerate(lines) if line.rstrip().endswith(needle)]
if len(matches) != 1:
    raise SystemExit(f"real production security seam missing or ambiguous for {marker}")
index = matches[0]
indent = lines[index][:-len(lines[index].lstrip())]
lines[index] = f"{indent}pass  # MUTATED:{marker}\n"
with open(path, "w", encoding="utf-8") as handle:
    handle.writelines(lines)
PY
        chmod +x "$mutant"

        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
            bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_attributed_mutant_kill "$marker" "$filter" "$expected_lines" \
            "$status" "$output" || return 1
        printf 'mutant=%s killed_by=%s\n' "$marker" "$filter"
    done
}

@test "ambient PATH crypto resolution mutant is killed by invalid-signature regression" {
    local framework mutant filter expected_lines
    filter='ambient PATH OpenSSL shim cannot authenticate an invalid disposition signature'
    expected_lines="$(expected_red_lines "$filter")" || return 1

    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
    assert_baseline_green "$filter" || return 1

    framework="${BATS_TEST_TMPDIR}/security-framework-ambient-openssl"
    mutant="${framework}/dev-tools/check-customer-delivery.sh"
    mkdir -p "${framework}/dev-tools" "${framework}/config"
    cp "$SCRIPT" "$mutant" || return 1
    cp "${REPO_ROOT}/config/customer-requirement.schema.json" \
        "${REPO_ROOT}/config/customer-delivery-receipt.schema.json" \
        "${REPO_ROOT}/config/review-evolution.schema.json" \
        "${framework}/config/" || return 1
    "$PYTHON" - "$mutant" <<'PY' || return 1
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    source = handle.read()
pin = 'PINNED_OPENSSL = sys.argv[12]'
validator = "def validate_crypto_verifier():\n"
if source.count(pin) != 1 or source.count(validator) != 1:
    raise SystemExit("AMBIENT_OPENSSL_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
source = source.replace(
    pin,
    'PINNED_OPENSSL = __import__("shutil").which("openssl")',
).replace(
    validator,
    validator + "    return True  # MUTATED:ambient_openssl_resolution\n",
)
with open(path, "w", encoding="utf-8") as handle:
    handle.write(source)
PY
    chmod +x "$mutant"

    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
        bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
    assert_attributed_mutant_kill ambient_openssl "$filter" "$expected_lines" \
        "$status" "$output"
}

@test "runtime pin response and Git child defenses are independently killed" {
    local pair kind filter framework mutant expected_lines
    local -a pairs=(
        'python_runtime|interpreter wrapper cannot impersonate the pinned Python runtime'
        'python_inode|perfect probe dependency and MET forgery cannot impersonate a trusted CPython inode'
        'python_runtime_metadata|forged writable trusted runtime metadata fails closed'
        'python_routing_env|ambient Python and Apple developer routing cannot redirect the trusted runtime'
        'python_cwd_isolation|current directory cannot shadow trusted Python dependencies'
        'wrapper_response|empty validator response cannot be accepted as MET'
        'git_no_replace_objects|Git replacement objects cannot hide an in-place source mutation'
        'git_finally_cleanup|global validation alarm reaps late source history child process group'
    )
    for pair in "${pairs[@]}"; do
        kind="${pair%%|*}"
        filter="${pair#*|}"
        expected_lines="$(expected_red_lines "$filter")" || return 1
        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_baseline_green "$filter" || return 1

        framework="${BATS_TEST_TMPDIR}/runtime-framework-${kind}"
        mutant="${framework}/dev-tools/check-customer-delivery.sh"
        mkdir -p "${framework}/dev-tools" "${framework}/config"
        cp "$SCRIPT" "$mutant" || return 1
        cp "${REPO_ROOT}/config/customer-requirement.schema.json" \
            "${REPO_ROOT}/config/customer-delivery-receipt.schema.json" \
            "${REPO_ROOT}/config/review-evolution.schema.json" \
            "${framework}/config/" || return 1
        "$PYTHON" - "$mutant" "$kind" <<'PY' || return 1
import sys

path, kind = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    source = handle.read()
if kind == "python_runtime":
    start_token = 'if [[ "$python_trusted" != true ]]; then  # SECURITY_RULE:python_inode_trust\n'
    end_token = 'umask 077\n'
    if source.count(start_token) != 1 or source.count(end_token) != 1:
        raise SystemExit("PYTHON_RUNTIME_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    start = source.index(start_token)
    end = source.index(end_token, start)
    replacement = '''trusted_python_anchor="$python_bin"
run_trusted_python() {
    "$python_bin" "$@"
}
'''
    source = source[:start] + replacement + source[end:]
elif kind == "python_inode":
    start_token = 'if [[ "$python_trusted" != true ]]; then  # SECURITY_RULE:python_inode_trust\n'
    end_token = 'umask 077\n'
    if source.count(start_token) != 1 or source.count(end_token) != 1:
        raise SystemExit("PYTHON_INODE_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    start = source.index(start_token)
    end = source.index(end_token, start)
    replacement = '''trusted_python_anchor="$python_bin"
run_trusted_python() {
    "$python_bin" "$@"
}
'''
    source = source[:start] + replacement + source[end:]
elif kind == "python_runtime_metadata":
    start_token = 'if [[ -z "$trusted_runtime_metadata" || "$trusted_runtime_uid" != 0 \\\n'
    end_token = 'then  # SECURITY_RULE:python_runtime_metadata_trust'
    if source.count(start_token) != 1 or source.count(end_token) != 1:
        raise SystemExit("PYTHON_RUNTIME_METADATA_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    start = source.index(start_token)
    end = source.index(end_token, start) + len(end_token)
    source = source[:start] + 'if false; then  # MUTATED:python_runtime_metadata_trust' + source[end:]
elif kind == "python_routing_env":
    scrub = '\nunset DEVELOPER_DIR TOOLCHAINS __PYVENV_LAUNCHER__ PYTHONEXECUTABLE PYTHONHOME PYTHONPATH\n\nsecure_root_path()'
    darwin = '''trusted_runtime_path="$(/usr/bin/env -i LC_ALL=C PATH=/usr/bin:/bin \\
        DEVELOPER_DIR="$trusted_developer_root" \\
        "$trusted_python_anchor" -I -c 'import sys; print(sys.executable)' 2>/dev/null || true)"'''
    linux = '''trusted_runtime_path="$(/usr/bin/env -i LC_ALL=C PATH=/usr/bin:/bin \\
        "$trusted_python_anchor" -I -c 'import sys; print(sys.executable)' 2>/dev/null || true)"'''
    if source.count(scrub) != 1 or source.count(darwin) != 1 or source.count(linux) != 1:
        raise SystemExit("PYTHON_ROUTING_ENV_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    source = source.replace(scrub, '\n: # MUTATED:python_routing_environment\n\nsecure_root_path()', 1)
    source = source.replace(
        darwin,
        '''trusted_runtime_path="$("$trusted_python_anchor" -I -c 'import sys; print(sys.executable)' 2>/dev/null || true)"''',
    ).replace(
        linux,
        '''trusted_runtime_path="$("$trusted_python_anchor" -I -c 'import sys; print(sys.executable)' 2>/dev/null || true)"''',
    )
elif kind == "python_cwd_isolation":
    darwin = '''python_isolation_args=(-I -S)'''
    linux = '''python_isolation_args=(-I)'''
    cwd = '''/bin/bash -p -c 'cd / && exec -a "$1" "$2" "${@:3}"' bash'''
    darwin_guard = '''[[ "${1:-}" == -I && "${2:-}" == -S \\
            && ("${3:-}" == -c || "${3:-}" == -) ]] || return 126
        mode="$3"
        shift 3'''
    darwin_child = '''child_args=(-I -S -c'''
    darwin_fchdir = '''os.fchdir(site_fd)
cwd_metadata = os.stat(".")'''
    if (source.count(darwin) != 1 or source.count(linux) != 1
            or source.count(cwd) != 2 or source.count(darwin_guard) != 1
            or source.count(darwin_child) != 2 or source.count(darwin_fchdir) != 1):
        raise SystemExit("PYTHON_CWD_ISOLATION_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    source = source.replace(darwin, 'python_isolation_args=(-S)  # MUTATED:darwin_cwd_isolation', 1)
    source = source.replace(linux, 'python_isolation_args=(-s)  # MUTATED:linux_isolation', 1)
    source = source.replace(
        darwin_guard,
        '''[[ "${1:-}" == -S && ("${2:-}" == -c || "${2:-}" == -) ]] || return 126
        mode="$2"
        shift 2''',
        1,
    )
    source = source.replace(darwin_child, 'child_args=(-S -c', 2)
    source = source.replace(
        darwin_fchdir,
        'True  # MUTATED:darwin_fchdir_binding\ncwd_metadata = os.stat(".")',
        1,
    )
    source = source.replace(
        cwd,
        '''/bin/bash -p -c 'exec -a "$1" "$2" "${@:3}"' bash''',
        1,
    )
elif kind == "wrapper_response":
    old = 'if [[ "$response_valid" != true ]]; then'
    if source.count(old) != 1:
        raise SystemExit("WRAPPER_RESPONSE_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    source = source.replace(old, 'if false; then')
elif kind == "git_no_replace_objects":
    old = '        "GIT_NO_REPLACE_OBJECTS": "1",\n'
    if source.count(old) != 1:
        raise SystemExit("GIT_NO_REPLACE_OBJECTS_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    source = source.replace(old, "")
elif kind == "git_finally_cleanup":
    function_start = source.index("def _validate_source_history():\n")
    function_end = source.index("\ndef validate_source_history():\n", function_start)
    function_source = source[function_start:function_end]
    cleanup = '''            if process is not None:
                release_completed_process(process)
'''
    mutant = '''            if process is not None:
                pass  # MUTATED:source_history_finally_cleanup
'''
    if function_source.count(cleanup) != 1:
        raise SystemExit("GIT_FINALLY_CLEANUP_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    function_source = function_source.replace(cleanup, mutant, 1)
    source = source[:function_start] + function_source + source[function_end:]
else:
    raise SystemExit(f"unknown mutant: {kind}")
with open(path, "w", encoding="utf-8") as handle:
    handle.write(source)
PY
        chmod +x "$mutant"

        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
            bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        if [[ "$kind" == git_finally_cleanup ]]; then
            [[ "$output" == *"source_history_unwind_cleanup=active:"* ]] || return 1
        fi
        assert_attributed_mutant_kill "$kind" "$filter" "$expected_lines" \
            "$status" "$output" \
            || { printf 'invalid_or_survived_mutant=%s status=%s output=%s\n' "$kind" "$status" "$output"; return 1; }
        printf 'mutant=%s killed_by=%s\n' "$kind" "$filter"
    done
}

run_darwin_dependency_site_mutants() {
    [[ "$(/usr/bin/uname -s)" == Darwin ]] || skip 'Darwin-only dependency-site mutations'
    local pair kind filter framework mutant expected_lines
    for pair in "$@"; do
        kind="${pair%%|*}"
        filter="${pair#*|}"
        expected_lines="$(expected_red_lines "$filter")" || return 1
        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
            CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON" \
            CUSTOMER_TEST_PYTHON_RUNTIME="$CUSTOMER_TEST_PYTHON_RUNTIME" \
            CUSTOMER_TEST_PYTHON_SITE="$CUSTOMER_TEST_PYTHON_SITE" \
            bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_baseline_green "$filter" || return 1

        framework="${BATS_TEST_TMPDIR}/site-authority-${kind}"
        mutant="${framework}/dev-tools/check-customer-delivery.sh"
        mkdir -p "${framework}/dev-tools" "${framework}/config"
        cp "$SCRIPT" "$mutant" || return 1
        cp "${REPO_ROOT}/config/customer-requirement.schema.json" \
            "${REPO_ROOT}/config/customer-delivery-receipt.schema.json" \
            "${REPO_ROOT}/config/review-evolution.schema.json" \
            "${framework}/config/" || return 1
        "$PYTHON" - "$mutant" "$kind" <<'PY' || return 1
import sys

path, kind = sys.argv[1:]
source = open(path, encoding="utf-8").read()
if kind == "python_pth_authority":
    initial = '''    for pth_file in "$trusted_python_site"/*.pth; do
        if [[ -e "$pth_file" || -L "$pth_file" ]]; then
            emit_config_error 'untrusted_python_runtime'
            exit 2
        fi
    done
'''
    identity = '''        for pth_file in "$trusted_python_site"/*.pth; do
            [[ ! -e "$pth_file" && ! -L "$pth_file" ]] || return 1
        done
'''
    bootstrap = 'assert not any(name.endswith(".pth") for name in os.listdir(site_fd))'
    if source.count(initial) != 1 or source.count(identity) != 1 or source.count(bootstrap) != 1:
        raise SystemExit("PYTHON_PTH_AUTHORITY_SEAM_MISSING_OR_AMBIGUOUS")
    source = source.replace(initial, '    : # MUTATED:python_pth_initial_authority\n', 1)
    source = source.replace(identity, '        : # MUTATED:python_pth_identity_authority\n', 1)
    source = source.replace(bootstrap, 'True  # MUTATED:python_pth_bootstrap_authority', 1)
    old = new = None
elif kind == "python_site_symlink":
    old = 'assert not entry.is_symlink()'
    new = 'True  # MUTATED:python_site_symlink'
elif kind == "python_distinfo_type":
    start_token = 'def authenticated_dist_version(site_fd, distribution, expected_version):  # SECURITY_RULE:python_distinfo_type\n'
    end_token = 'sys.path.insert(0, ".")\n'
    if source.count(start_token) != 1 or source.count(end_token) != 1:
        raise SystemExit("PYTHON_DISTINFO_TYPE_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    start = source.index(start_token)
    end = source.index(end_token, start)
    source = source[:start] + (
        'def authenticated_dist_version(site_fd, distribution, expected_version):  # MUTATED:python_distinfo_type\n'
        '    return expected_version\n\n'
    ) + source[end:]
    old = new = None
elif kind == "python_distinfo_nofollow":
    scan = 'assert not entry.is_symlink()'
    old = 'flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC'
    new = 'flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC  # MUTATED:distinfo_nofollow'
    if source.count(scan) != 1:
        raise SystemExit("PYTHON_DISTINFO_NOFOLLOW_SCAN_SEAM_MISSING")
    source = source.replace(scan, 'True  # MUTATED:distinfo_symlink_scan', 1)
elif kind == "python_distinfo_fchdir":
    old = '        os.fchdir(dist_fd)\n'
    new = '        os.fchdir(site_fd)  # MUTATED:distinfo_fchdir\n'
elif kind == "python_distinfo_metadata":
    old = '        or versions[0] != expected_version\n'
    new = '        or False  # MUTATED:python_distinfo_metadata\n'
elif kind == "python_metadata_nofollow":
    scan = 'assert not entry.is_symlink()'
    old = 'metadata_flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC'
    new = 'metadata_flags = os.O_RDONLY | os.O_CLOEXEC  # MUTATED:metadata_nofollow'
    if source.count(scan) != 1:
        raise SystemExit("PYTHON_METADATA_NOFOLLOW_SCAN_SEAM_MISSING")
    source = source.replace(scan, 'True  # MUTATED:metadata_symlink_scan', 1)
elif kind == "python_metadata_size":
    size_cap = '                or metadata_before.st_size > 1048576\n'
    identity = '''                or (
                    metadata_before.st_dev,
                    metadata_before.st_ino,
                    metadata_before.st_size,
                ) != (
                    metadata_entry.st_dev,
                    metadata_entry.st_ino,
                    metadata_entry.st_size,
                )
'''
    if source.count(size_cap) != 1 or source.count(identity) != 1:
        raise SystemExit("PYTHON_METADATA_SIZE_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    source = source.replace(
        size_cap,
        '                or False  # MUTATED:metadata_size_cap\n',
        1,
    )
    source = source.replace(
        identity,
        '''                or (
                    metadata_before.st_dev,
                    metadata_before.st_ino,
                ) != (
                    metadata_entry.st_dev,
                    metadata_entry.st_ino,
                )  # MUTATED:metadata_size_identity
''',
        1,
    )
    old = new = None
elif kind == "python_metadata_name":
    old = '        or normalized_distribution(names[0]) != normalized_distribution(distribution)\n'
    new = '        or False  # MUTATED:metadata_name\n'
elif kind == "python_metadata_duplicate":
    old = '        len(names) != 1\n        or len(versions) != 1\n'
    new = '        False  # MUTATED:metadata_duplicate\n'
elif kind == "python_metadata_preopen_identity":
    old = '''                or (
                    metadata_before.st_dev,
                    metadata_before.st_ino,
                    metadata_before.st_size,
                ) != (
                    metadata_entry.st_dev,
                    metadata_entry.st_ino,
                    metadata_entry.st_size,
                )
'''
    new = '                or False  # MUTATED:metadata_preopen_identity\n'
elif kind == "python_metadata_nonblock":
    old = '        metadata_flags |= os.O_NONBLOCK\n'
    new = '        metadata_flags |= 0  # MUTATED:metadata_nonblock\n'
elif kind == "python_metadata_identity":
    old = '''                or (
                    metadata_path_after.st_dev,
                    metadata_path_after.st_ino,
                    metadata_path_after.st_size,
                ) != (
                    metadata_before.st_dev,
                    metadata_before.st_ino,
                    metadata_before.st_size,
                )
'''
    new = '                or False  # MUTATED:metadata_path_identity\n'
else:
    raise SystemExit(kind)
if old is not None:
    if source.count(old) != 1:
        raise SystemExit(f"SITE_AUTHORITY_MUTATION_SEAM_MISSING_OR_AMBIGUOUS:{kind}")
    source = source.replace(old, new, 1)
open(path, "w", encoding="utf-8").write(source)
PY
        chmod +x "$mutant"
        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
            CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON" \
            CUSTOMER_TEST_PYTHON_RUNTIME="$CUSTOMER_TEST_PYTHON_RUNTIME" \
            CUSTOMER_TEST_PYTHON_SITE="$CUSTOMER_TEST_PYTHON_SITE" \
            CUSTOMER_DELIVERY_EXPECT_MUTATION_MARKER="MUTATED:${kind#python_}" \
            CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
            bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_attributed_mutant_kill "$kind" "$filter" "$expected_lines" \
            "$status" "$output" || return 1
        printf 'mutant=%s killed_by=%s\n' "$kind" "$filter"
    done
}

@test "Darwin executable pth authority mutant is independently killed" {
    run_darwin_dependency_site_mutants \
        'python_pth_authority|Darwin trusted site bootstrap rejects executable pth authority'
}

@test "Darwin dependency-site symlink mutant is independently killed" {
    run_darwin_dependency_site_mutants \
        'python_site_symlink|Darwin trusted site bootstrap rejects symlinked dependency content'
}

@test "Darwin dist-info type mutant is independently killed" {
    run_darwin_dependency_site_mutants \
        'python_distinfo_type|Darwin trusted site bootstrap rejects regular-file dist-info forgery'
}

@test "Darwin dist-info nofollow mutant is independently killed" {
    run_darwin_dependency_site_mutants \
        'python_distinfo_nofollow|Darwin trusted site bootstrap rejects symlinked dist-info'
}

@test "Darwin dist-info working-directory mutant is independently killed" {
    run_darwin_dependency_site_mutants \
        'python_distinfo_fchdir|complete canonical delivery chain is MET'
}

@test "Darwin dependency metadata content mutants are independently killed" {
    run_darwin_dependency_site_mutants \
        'python_distinfo_metadata|Darwin trusted site bootstrap authenticates dist-info metadata' \
        'python_metadata_nofollow|Darwin trusted site bootstrap rejects METADATA symlink swap after lstat' \
        'python_metadata_size|Darwin trusted site bootstrap rejects oversized METADATA change after lstat' \
        'python_metadata_name|Darwin trusted site bootstrap rejects METADATA boundary forgeries'
}

@test "Darwin dependency metadata identity and bounded-open mutants are independently killed" {
    run_darwin_dependency_site_mutants \
        'python_metadata_duplicate|Darwin trusted site bootstrap rejects METADATA boundary forgeries' \
        'python_metadata_preopen_identity|Darwin trusted site bootstrap detects METADATA replacement before open' \
        'python_metadata_nonblock|Darwin METADATA open remains nonblocking across a FIFO replacement race' \
        'python_metadata_identity|Darwin trusted site bootstrap detects METADATA identity change after read'
}


@test "ambient realpath authority mutants are independently killed" {
    local pair kind filter framework mutant expected_lines
    local -a pairs=(
        'function|exported realpath function cannot bypass intermediate symlink confinement'
        'path|PATH realpath shim cannot bypass intermediate symlink confinement'
    )

    for pair in "${pairs[@]}"; do
        kind="${pair%%|*}"
        filter="${pair#*|}"
        expected_lines="$(expected_red_lines "$filter")" || return 1
        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_baseline_green "$filter" || return 1

        framework="${BATS_TEST_TMPDIR}/realpath-framework-${kind}"
        mutant="${framework}/dev-tools/check-customer-delivery.sh"
        mkdir -p "${framework}/dev-tools" "${framework}/config"
        cp "$SCRIPT" "$mutant" || return 1
        cp "${REPO_ROOT}/config/customer-requirement.schema.json" \
            "${REPO_ROOT}/config/customer-delivery-receipt.schema.json" \
            "${REPO_ROOT}/config/review-evolution.schema.json" \
            "${framework}/config/" || return 1
        "$PYTHON" - "$mutant" "$kind" <<'PY' || return 1
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    source = handle.read()
old = '''    resolved_dir="$(cd -P -- "${candidate%/*}" && pwd -P)" || {
        emit_config_error "path_escape:${label}"
        return 2
    }
    resolved="${resolved_dir}/${candidate##*/}"'''
replacement = '''    resolved="$(realpath -e -- "$candidate")" || {
        emit_config_error "path_escape:${label}"
        return 2
    }'''
if source.count(old) != 1:
    raise SystemExit("CONFINEMENT_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
source = source.replace(old, replacement)
if sys.argv[2] == "function":
    privileged_shebang = "#!/bin/bash -p"
    old_unset = "unset -f cat dirname jq mktemp realpath rm stat tail wc"
    if source.count(privileged_shebang) != 1 or source.count(old_unset) != 1:
        raise SystemExit("REALPATH_FUNCTION_SANITIZATION_SEAM_MISSING_OR_AMBIGUOUS")
    source = source.replace(privileged_shebang, "#!/usr/bin/env bash").replace(
        old_unset, "unset -f cat dirname jq mktemp rm stat tail wc"
    )
with open(path, "w", encoding="utf-8") as handle:
    handle.write(source)
PY
        chmod +x "$mutant"

        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
            bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_attributed_mutant_kill "realpath_${kind}" "$filter" "$expected_lines" \
            "$status" "$output" || return 1
        printf 'mutant=realpath_%s killed_by=%s\n' "$kind" "$filter"
    done
}


@test "platform stat interpreter OpenSSL and global deadline mutants are behaviorally killed" {
    local pair kind filter framework mutant platform architecture expected_lines
    platform="$(uname -s)"
    architecture="$(uname -m)"
    local -a pairs=(
        'platform_stat|complete canonical delivery chain is MET'
        'platform_interpreter|complete canonical delivery chain is MET'
        'platform_openssl|complete canonical delivery chain is MET'
        'total_deadline|all validation subprocesses share one total deadline'
    )
    if [[ "$platform" == Darwin ]]; then
        pairs+=( 'platform_git|complete canonical delivery chain is MET' )
    fi

    for pair in "${pairs[@]}"; do
        kind="${pair%%|*}"
        filter="${pair#*|}"
        expected_lines="$(expected_red_lines "$filter")" || return 1
        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_baseline_green "$filter" || return 1

        framework="${BATS_TEST_TMPDIR}/portable-bounds-framework-${kind}"
        mutant="${framework}/dev-tools/check-customer-delivery.sh"
        mkdir -p "${framework}/dev-tools" "${framework}/config"
        cp "$SCRIPT" "$mutant" || return 1
        cp "${REPO_ROOT}/config/customer-requirement.schema.json" \
            "${REPO_ROOT}/config/customer-delivery-receipt.schema.json" \
            "${REPO_ROOT}/config/review-evolution.schema.json" \
            "${framework}/config/" || return 1
        "$PYTHON" - "$mutant" "$kind" "$platform" "$architecture" <<'PY' || return 1
import sys

path, kind, platform, architecture = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    source = handle.read()
if kind == "platform_stat":
    if platform == "Linux":
        old = "/usr/bin/stat -L -c '%d|%i|%u|%a|%F' \"$1\" 2>/dev/null"
        replacement = "/usr/bin/stat -L -f '%d|%i|%u|%Lp|%HT' \"$1\" 2>/dev/null"
    elif platform == "Darwin":
        old = "/usr/bin/stat -L -f '%d|%i|%u|%Lp|%HT' \"$1\" 2>/dev/null"
        replacement = "/usr/bin/stat -L -c '%d|%i|%u|%a|%F' \"$1\" 2>/dev/null"
    else:
        raise SystemExit(f"unsupported mutation platform: {platform}")
    if source.count(old) != 1:
        raise SystemExit("PLATFORM_STAT_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    source = source.replace(old, replacement)
elif kind == "platform_interpreter":
    old = "python_min_minor=11" if platform == "Linux" else "python_min_minor=9"
    if source.count(old) != 1:
        raise SystemExit("PLATFORM_INTERPRETER_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    source = source.replace(old, "python_min_minor=99")
elif kind == "platform_openssl":
    if platform == "Linux":
        old = "pinned_openssl='/usr/bin/openssl'"
    elif platform == "Darwin" and architecture == "arm64":
        old = "pinned_openssl='/opt/homebrew/opt/openssl@3/bin/openssl'"
    elif platform == "Darwin" and architecture == "x86_64":
        old = "pinned_openssl='/usr/local/opt/openssl@3/bin/openssl'"
    else:
        raise SystemExit(f"unsupported mutation platform: {platform}/{architecture}")
    if source.count(old) != 1:
        raise SystemExit("PLATFORM_OPENSSL_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    source = source.replace(old, "pinned_openssl='/nonexistent/customer-delivery-openssl'", 1)
elif kind == "platform_git":
    old = 'PINNED_DARWIN_GIT = "/Library/Developer/CommandLineTools/usr/bin/git"'
    if platform != "Darwin" or source.count(old) != 1:
        raise SystemExit("PLATFORM_GIT_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    source = source.replace(
        old,
        'PINNED_DARWIN_GIT = "/nonexistent/customer-delivery-git"',
        1,
    )
elif kind == "total_deadline":
    deadline = "VALIDATION_DEADLINE = time.monotonic() + VALIDATION_TOTAL_TIMEOUT_SECONDS"
    alarm = "signal.setitimer(signal.ITIMER_REAL, VALIDATION_TOTAL_TIMEOUT_SECONDS)"
    if source.count(deadline) != 1 or source.count(alarm) != 1:
        raise SystemExit("TOTAL_DEADLINE_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    source = source.replace(
        deadline, "VALIDATION_DEADLINE = time.monotonic() + 3600"
    ).replace(alarm, "signal.setitimer(signal.ITIMER_REAL, 3600)")
else:
    raise SystemExit(f"unknown mutant: {kind}")
with open(path, "w", encoding="utf-8") as handle:
    handle.write(source)
PY
        chmod +x "$mutant"

        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
            bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_attributed_mutant_kill "$kind" "$filter" "$expected_lines" \
            "$status" "$output" || return 1
        printf 'mutant=%s platform=%s/%s killed_by=%s\n' \
            "$kind" "$platform" "$architecture" "$filter"
    done
}

@test "descriptor openat nofollow and identity mutants are behaviorally killed" {
    local pair kind filter framework mutant expected_lines
    local -a pairs=(
        'openat|pre-open path replacement cannot redirect a canonical snapshot'
        'repository_nofollow|repository binding refuses a symlink swapped into the canonical gitdir'
        'snapshot_nofollow|pre-open path replacement cannot redirect a canonical snapshot'
        'identity|post-open identity change invalidates the captured snapshot'
    )
    for pair in "${pairs[@]}"; do
        kind="${pair%%|*}"
        filter="${pair#*|}"
        expected_lines="$(expected_red_lines "$filter")" || return 1
        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_baseline_green "$filter" || return 1
        framework="${BATS_TEST_TMPDIR}/descriptor-framework-${kind}"
        mutant="${framework}/dev-tools/check-customer-delivery.sh"
        mkdir -p "${framework}/dev-tools" "${framework}/config"
        cp "$SCRIPT" "$mutant" || return 1
        cp "${REPO_ROOT}/config/customer-requirement.schema.json" \
            "${REPO_ROOT}/config/customer-delivery-receipt.schema.json" \
            "${REPO_ROOT}/config/review-evolution.schema.json" \
            "${framework}/config/" || return 1
        "$PYTHON" - "$mutant" "$kind" <<'PY' || return 1
import sys
path, kind = sys.argv[1:]
source = open(path, encoding="utf-8").read()
if kind == "openat":
    old = """        document_bytes = read_confined_snapshot(
            DOCUMENT_PATHS[name], ROOT, name
        )"""
    new = '        document_bytes = open(DOCUMENT_PATHS[name], "rb").read()'
elif kind == "repository_nofollow":
    old = '''def bind_authoritative_repository():
    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC
    nofollow = getattr(os, "O_NOFOLLOW", 0)'''
    new = '''def bind_authoritative_repository():
    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC
    nofollow = 0'''
elif kind == "snapshot_nofollow":
    old = '''def read_confined_snapshot(path, boundary, label):
    relative = os.path.relpath(path, boundary)'''
    new = '''def read_confined_snapshot(path, boundary, label):
    nofollow = 0
    relative = os.path.relpath(path, boundary)'''
    snapshot_assignment = '    nofollow = getattr(os, "O_NOFOLLOW", 0)\n'
    snapshot_start = source.index('def read_confined_snapshot(path, boundary, label):\n')
    snapshot_end = source.index('\ndef ', snapshot_start + 1)
    snapshot = source[snapshot_start:snapshot_end]
    if snapshot.count(snapshot_assignment) != 1:
        raise SystemExit("SNAPSHOT_NOFOLLOW_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    source = source[:snapshot_start] + snapshot.replace(
        snapshot_assignment, "", 1
    ) + source[snapshot_end:]
elif kind == "identity":
    old = '        if identity_before != identity_after:'
    new = '        if False:'
else:
    raise SystemExit(kind)
assert source.count(old) == 1
open(path, "w", encoding="utf-8").write(source.replace(old, new))
PY
        chmod +x "$mutant"
        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
            bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_attributed_mutant_kill "$kind" "$filter" "$expected_lines" \
            "$status" "$output" || return 1
    done
}

@test "repository root gitdir identity and descriptor mutants are independently killed" {
    local pair kind filter framework mutant expected_lines
    local -a pairs=(
        'root_identity|authoritative root replacement after document snapshots cannot redirect source history'
        'gitdir_identity|authoritative gitdir replacement after document snapshots cannot redirect source history'
        'gitdir_descriptor|git child uses the bound gitdir when the path is transiently replaced'
        'git_control_identity|transient Git graft and alternates controls invalidate the bound repository'
    )
    for pair in "${pairs[@]}"; do
        kind="${pair%%|*}"
        filter="${pair#*|}"
        expected_lines="$(expected_red_lines "$filter")" || return 1
        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_baseline_green "$filter" || return 1
        framework="${BATS_TEST_TMPDIR}/repository-binding-${kind}"
        mutant="${framework}/dev-tools/check-customer-delivery.sh"
        mkdir -p "${framework}/dev-tools" "${framework}/config"
        cp "$SCRIPT" "$mutant" || return 1
        cp "${REPO_ROOT}/config/customer-requirement.schema.json" \
            "${REPO_ROOT}/config/customer-delivery-receipt.schema.json" \
            "${REPO_ROOT}/config/review-evolution.schema.json" \
            "${framework}/config/" || return 1
        "$PYTHON" - "$mutant" "$kind" <<'PY' || return 1
import sys
path, kind = sys.argv[1:]
source = open(path, encoding="utf-8").read()
if kind == "root_identity":
    old = 'or repository_entry_identity(os.stat(ROOT, follow_symlinks=False))\n            != binding["root_identity"]'
    new = 'or False'
elif kind == "gitdir_identity":
    old = '        if dotgit_path_identity != binding["dotgit_identity"]:'
    new = '        if False:'
elif kind == "gitdir_descriptor":
    replacements = {
        '        f"--git-dir={git_dir_argument}",': '        f"--git-dir={ROOT}/.git",',
        '    git_prefix = [\n': '    git_env["GIT_OBJECT_DIRECTORY"] = os.path.join(ROOT, ".git", "objects")\n    git_env["GIT_COMMON_DIR"] = os.path.join(ROOT, ".git")\n    git_prefix = [\n',
        '                os.fchdir(git_cwd_fd)': '                os.chdir(ROOT)',
    }
    if any(source.count(old) != 1 for old in replacements):
        raise SystemExit("GITDIR_DESCRIPTOR_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    for old, new in replacements.items():
        source = source.replace(old, new, 1)
    old = new = None
elif kind == "git_control_identity":
    old = '''def repository_control_identity(metadata):  # MUTATION_SEAM:source_history_control_identity
    return repository_entry_identity(metadata, content_stable=True)
'''
    new = '''def repository_control_identity(metadata):  # MUTATED:source_history_control_identity
    return repository_entry_identity(metadata)
'''
else:
    raise SystemExit(kind)
if old is not None:
    assert source.count(old) == 1
    source = source.replace(old, new)
open(path, "w", encoding="utf-8").write(source)
PY
        chmod +x "$mutant"
        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
            bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_attributed_mutant_kill "$kind" "$filter" "$expected_lines" \
            "$status" "$output" || return 1
    done
}

run_review_inventory_mutants() {
    local pair kind filter framework mutant expected_lines
    for pair in "$@"; do
        kind="${pair%%|*}"
        filter="${pair#*|}"
        expected_lines="$(expected_red_lines "$filter")" || return 1
        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_baseline_green "$filter" || return 1
        framework="${BATS_TEST_TMPDIR}/review-inventory-${kind}"
        mutant="${framework}/dev-tools/check-customer-delivery.sh"
        mkdir -p "${framework}/dev-tools" "${framework}/config"
        cp "$SCRIPT" "$mutant" || return 1
        cp "${REPO_ROOT}/config/customer-requirement.schema.json" \
            "${REPO_ROOT}/config/customer-delivery-receipt.schema.json" \
            "${REPO_ROOT}/config/review-evolution.schema.json" \
            "${framework}/config/" || return 1
        "$PYTHON" - "$mutant" "$kind" <<'PY' || return 1
import sys
path, kind = sys.argv[1:]
source = open(path, encoding="utf-8").read()
if kind == "set_exact":
    old = '        add(f"originating_review_inventory_pair_missing:{review_id}:{requirement_id}")  # SECURITY_RULE:review_inventory_exact'
    new = '        pass  # MUTATED:review_inventory_exact'
elif kind == "closure":
    old = '        validate_originating_review_state(record)  # SECURITY_RULE:review_inventory_closure'
    new = '        pass  # SECURITY_RULE:review_inventory_closure'
elif kind == "authentication":
    old = '        validate_originating_review_commitment(record)'
    new = '        pass'
elif kind == "pair_extra":
    old = '        add(f"originating_review_inventory_pair_extra:{review_id}:{requirement_id}")  # SECURITY_RULE:review_inventory_exact'
    new = '        pass  # MUTATED:review_inventory_pair_extra'
elif kind == "id_uniqueness":
    old = '            add(f"originating_review_id_duplicate:{review_id}")'
    new = '            pass  # MUTATED:review_id_uniqueness'
elif kind == "manifest_signature":
    old = '        add("originating_review_inventory_manifest_signature_invalid")  # SECURITY_RULE:review_manifest_signature'
    new = '        pass  # MUTATED:review_manifest_signature'
else:
    raise SystemExit(kind)
assert source.count(old) == 1
open(path, "w", encoding="utf-8").write(source.replace(old, new))
PY
        chmod +x "$mutant"
        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
            bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_attributed_mutant_kill "$kind" "$filter" "$expected_lines" \
            "$status" "$output" || return 1
    done
}

run_process_lifecycle_mutant() {
    local mode="$1"
    local filter='OpenSSL deadline terminates stubborn descendant pipe holders'
    local functional_mutant validator_mutant guard mutant expected_fragment
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON" \
        CUSTOMER_DELIVERY_LIFECYCLE_ONLY="$mode" \
        bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
    assert_baseline_green "$filter" || return 1

    functional_mutant="${BATS_TEST_TMPDIR}/process-lifecycle-${mode}-mutant.bats"
    validator_mutant="${BATS_TEST_TMPDIR}/check-customer-delivery-process-lifecycle-${mode}.sh"
    cp "$FUNCTIONAL_TEST" "$functional_mutant" || return 1
    cp "$SCRIPT" "$validator_mutant" || return 1
    case "$mode" in
        cleanup-alarm)
            guard=$'    previous_mask = signal.pthread_sigmask(\n        signal.SIG_BLOCK, {signal.SIGALRM}\n    )  # SECURITY_RULE:cleanup_signal_mask'
            mutant='    previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, set())  # MUTATED:cleanup_signal_mask'
            expected_fragment='cleanup_alarm_orphan=active:'
            ;;
        reused-pid)
            guard='        and process.supervisor.returncode is None'
            mutant='        and True  # MUTATED:durable_process_group_owner'
            expected_fragment='reused_pid_group_signalled='
            ;;
        *) return 1 ;;
    esac
    "$PYTHON" - "$functional_mutant" "$validator_mutant" "$REPO_ROOT" "$guard" "$mutant" <<'PY' || return 1
import sys

test_path, validator_path, repo_root, guard, mutant = sys.argv[1:]
test_source = open(test_path, encoding="utf-8").read()
validator_source = open(validator_path, encoding="utf-8").read()
root_old = '    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."\n'
root_new = f"    REPO_ROOT={repo_root!r}\n"
if test_source.count(root_old) != 1 or validator_source.count(guard) != 1:
    raise SystemExit("PROCESS_LIFECYCLE_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
open(test_path, "w", encoding="utf-8").write(test_source.replace(root_old, root_new, 1))
open(validator_path, "w", encoding="utf-8").write(validator_source.replace(guard, mutant, 1))
PY
    chmod +x "$validator_mutant"
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON" \
        CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$validator_mutant" \
        CUSTOMER_DELIVERY_LIFECYCLE_ONLY="$mode" \
        bats --filter "^${filter}$" "$functional_mutant"
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"${expected_fragment}"* ]] \
        && [ "$(printf '%s\n' "$output" | awk -v target="not ok 1 ${filter}" '$0 == target { count++ } END { print count+0 }')" -eq 1 ] \
        && [[ "$output" != *"setup_file failed"* ]] \
        && [[ "$output" != *"BATS_TEST_TIMEOUT"* ]] \
        || { printf 'process_lifecycle_mutant_not_attributed=%s status=%s output=%s\n' \
            "$mode" "$status" "$output"; return 1; }
    "$PYTHON" -c \
        'import hashlib,sys; print(f"RED_SENTINEL:{sys.argv[1]}:{hashlib.sha256(sys.argv[2].encode()).hexdigest()}")' \
        "process_lifecycle_${mode}" "${filter}|${expected_fragment}"
}

run_completed_descendant_callsite_mutant() {
    local callsite="$1"
    local filter='OpenSSL deadline terminates stubborn descendant pipe holders'
    local functional_mutant validator_mutant
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON" \
        CUSTOMER_DELIVERY_COMPLETED_PARENT_ONLY="$callsite" \
        bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
    assert_baseline_green "$filter" || return 1

    functional_mutant="${BATS_TEST_TMPDIR}/completed-descendant-${callsite}-mutant.bats"
    validator_mutant="${BATS_TEST_TMPDIR}/check-customer-delivery-completed-descendant-${callsite}.sh"
    cp "$FUNCTIONAL_TEST" "$functional_mutant" || return 1
    cp "$SCRIPT" "$validator_mutant" || return 1
    "$PYTHON" - "$functional_mutant" "$validator_mutant" "$REPO_ROOT" "$callsite" <<'PY' || return 1
import sys

test_path, validator_path, repo_root, callsite = sys.argv[1:]
test_source = open(test_path, encoding="utf-8").read()
root_old = '    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."\n'
root_new = f"    REPO_ROOT={repo_root!r}\n"
validator_source = open(validator_path, encoding="utf-8").read()
seams = {
    "silent": (
        "def run_silent_process(arguments):\n",
        "\ndef run_bounded_process(",
        '''        returncode = wait_process_status(process)
        terminate_registered_process(process)
''',
    ),
    "bounded": (
        "def run_bounded_process(",
        "\nsignal.signal(",
        '''        returncode = wait_process_status(process)
        terminate_registered_process(process)
''',
    ),
    "source_history": (
        "def _validate_source_history():\n",
        "\ndef validate_source_history():\n",
        '''            returncode = wait_process_status(process, deadline)
            terminate_registered_process(process)
''',
    ),
}
if callsite not in seams:
    raise SystemExit("COMPLETED_DESCENDANT_CALLSITE_INVALID")
start_token, end_token, guard = seams[callsite]
start = validator_source.index(start_token)
end = validator_source.index(end_token, start)
function_source = validator_source[start:end]
indent = "            " if callsite == "source_history" else "        "
mutant = guard.splitlines(keepends=True)[0] + (
    f"{indent}os.kill(process.pid, signal.SIGKILL)\n"
    f"{indent}process.supervisor.wait(timeout=0.4)\n"
    f"{indent}close_process_streams(process)\n"
    f"{indent}release_active_process(process)  # MUTATED:completed_descendant_{callsite}\n"
)
if test_source.count(root_old) != 1 or function_source.count(guard) != 1:
    raise SystemExit(f"COMPLETED_DESCENDANT_MUTATION_SEAM_MISSING_OR_AMBIGUOUS:{callsite}")
function_source = function_source.replace(guard, mutant, 1)
validator_source = validator_source[:start] + function_source + validator_source[end:]
open(test_path, "w", encoding="utf-8").write(test_source.replace(root_old, root_new, 1))
open(validator_path, "w", encoding="utf-8").write(validator_source)
PY
    chmod +x "$validator_mutant"
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON" \
        CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$validator_mutant" \
        CUSTOMER_DELIVERY_COMPLETED_PARENT_ONLY="$callsite" \
        bats --filter "^${filter}$" "$functional_mutant"
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"completed_parent_descendant_survived=${callsite} pid="* ]] \
        && [ "$(printf '%s\n' "$output" | awk -v target="not ok 1 ${filter}" '$0 == target { count++ } END { print count+0 }')" -eq 1 ] \
        && [[ "$output" != *"setup_file failed"* ]] \
        && [[ "$output" != *"BATS_TEST_TIMEOUT"* ]] \
        || { printf 'completed_descendant_mutant_not_attributed=%s status=%s output=%s\n' \
            "$callsite" "$status" "$output"; return 1; }
    "$PYTHON" -c \
        'import hashlib,sys; print(f"RED_SENTINEL:{sys.argv[1]}:{hashlib.sha256(sys.argv[2].encode()).hexdigest()}")' \
        "completed_descendant_${callsite}" "${filter}|completed_parent_descendant_survived=${callsite}"
}

@test "review inventory exact-set mutant is independently killed" {
    run_review_inventory_mutants \
        'set_exact|two-requirement epic cannot close with its second originating review missing'
}

@test "review inventory closure mutant is independently killed" {
    run_review_inventory_mutants \
        'closure|two-requirement epic cannot close with its second originating review OPEN'
}

@test "review inventory authentication mutant is independently killed" {
    run_review_inventory_mutants \
        'authentication|every originating review inventory record is authenticated'
}

@test "review inventory extra duplicate and manifest mutants are independently killed" {
    run_review_inventory_mutants \
        'pair_extra|signed review inventory rejects an extra review pair' \
        'id_uniqueness|signed review inventory rejects a duplicate review identity' \
        'manifest_signature|signed review inventory manifest signature is independently verified'
}

@test "mutation kill attribution rejects setup syntax timeout and wrong-assertion failures" {
    local filter='focused contract' expected=42 deadline_mutant deadline_filter
    local terminal_mask_mutant terminal_mask_validator terminal_mask_filter
    local post_popen_mutant post_popen_control post_popen_readiness_control post_popen_stale_mutant post_popen_filter
    local completed_descendant_validator completed_descendant_mutant
    local callsite marker_kind marker_value marker_hex sentinel_kind
    local diagnostic_mutant diagnostic_filter pid_width_mutant
    run assert_attributed_mutant_kill valid "$filter" "$expected" 1 \
        $'1..1\nnot ok 1 focused contract\n# (in test file fixture.bats, line 42)\n# assertion failed'
    [ "$status" -eq 0 ] && [[ "$output" == RED_SENTINEL:valid:* ]] || return 1

    run assert_attributed_mutant_kill setup "$filter" "$expected" 1 \
        $'1..1\nnot ok 1 focused contract\n# setup_file failed'
    [ "$status" -ne 0 ] && [[ "$output" == *"HARNESS_INVALID:setup"* ]] || return 1

    run assert_attributed_mutant_kill syntax "$filter" "$expected" 2 \
        $'1..1\nnot ok 1 focused contract\n# syntax error\n# (in test file fixture.bats, line 42)'
    [ "$status" -ne 0 ] && [[ "$output" == *"HARNESS_INVALID:syntax"* ]] || return 1

    run assert_attributed_mutant_kill timeout "$filter" "$expected" 124 \
        $'1..1\nnot ok 1 focused contract\n# (in test file fixture.bats, line 42)'
    [ "$status" -ne 0 ] && [[ "$output" == *"HARNESS_INVALID:timeout"* ]] || return 1

    run assert_attributed_mutant_kill marker "$filter" "$expected" 1 \
        $'1..1\nnot ok 1 focused contract\nHARNESS_INVALID:missing_mutation_marker:marker\n# (in test file fixture.bats, line 42)'
    [ "$status" -ne 0 ] && [[ "$output" == *"HARNESS_INVALID:marker"* ]] || return 1

    run assert_attributed_mutant_kill wrong "$filter" "$expected" 1 \
        $'1..1\nnot ok 1 focused contract\n# (in test file fixture.bats, line 43)\n# wrong assertion failed'
    [ "$status" -ne 0 ] && [[ "$output" == *"HARNESS_INVALID:wrong:wrong-assertion"* ]] \
        || return 1

    deadline_mutant="${BATS_TEST_TMPDIR}/deadline-post-stall.bats"
    deadline_filter='source history subprocesses share one total deadline'
    cp "$FUNCTIONAL_TEST" "$deadline_mutant" || return 1
    "$PYTHON" - "$deadline_mutant" "$REPO_ROOT" <<'PY' || return 1
import sys

path, repo_root = sys.argv[1:]
source = open(path, encoding="utf-8").read()
stall_old = "    time.sleep(0)  # TEST_DEADLINE_STALL_MUTATION\n"
stall_new = "    time.sleep(8)  # MUTATED:post_deadline_stall\n"
root_old = '    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."\n'
root_new = f"    REPO_ROOT={repo_root!r}\n"
if source.count(stall_old) != 1 or source.count(root_old) != 1:
    raise SystemExit("POST_DEADLINE_STALL_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
source = source.replace(stall_old, stall_new, 1).replace(root_old, root_new, 1)
open(path, "w", encoding="utf-8").write(source)
PY
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON" \
        bats --filter "^${deadline_filter}$" "$deadline_mutant"
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"not ok 1 ${deadline_filter}"* ]] \
        && [[ "$output" == *"history_deadline_output="* ]] \
        && [[ "$output" != *"setup_file failed"* ]] \
        && [[ "$output" != *"BATS_TEST_TIMEOUT"* ]] \
        || { printf 'post_deadline_mutant_status=%s output=%s\n' "$status" "$output"; return 1; }

    terminal_mask_mutant="${BATS_TEST_TMPDIR}/terminal-mask.bats"
    terminal_mask_validator="${BATS_TEST_TMPDIR}/check-customer-delivery-terminal-mask.sh"
    terminal_mask_filter='OpenSSL version output is bounded before allocation'
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON" \
        bats --filter "^${terminal_mask_filter}$" "$FUNCTIONAL_TEST"
    assert_baseline_green "$terminal_mask_filter" || return 1
    cp "$FUNCTIONAL_TEST" "$terminal_mask_mutant" || return 1
    cp "$SCRIPT" "$terminal_mask_validator" || return 1
    "$PYTHON" - "$terminal_mask_mutant" "$terminal_mask_validator" "$REPO_ROOT" <<'PY' || return 1
import sys

test_path, validator_path, repo_root = sys.argv[1:]
test_source = open(test_path, encoding="utf-8").read()
root_old = '    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."\n'
root_new = f"    REPO_ROOT={repo_root!r}\n"
guard = "    signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGALRM})  # SECURITY_RULE:terminal_signal_mask\n"
if test_source.count(root_old) != 1:
    raise SystemExit("TERMINAL_MASK_TEST_ROOT_SEAM_MISSING_OR_AMBIGUOUS")
validator_source = open(validator_path, encoding="utf-8").read()
if validator_source.count(guard) != 1:
    raise SystemExit("TERMINAL_MASK_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
open(test_path, "w", encoding="utf-8").write(test_source.replace(root_old, root_new, 1))
open(validator_path, "w", encoding="utf-8").write(
    validator_source.replace(guard, "    pass  # MUTATED:terminal_signal_mask\n", 1)
)
PY
    chmod +x "$terminal_mask_validator"
    expected="$(expected_red_lines "$terminal_mask_filter")" || return 1
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON" \
        CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$terminal_mask_validator" \
        bats --filter "^${terminal_mask_filter}$" "$terminal_mask_mutant"
    [[ "$output" == *"crypto_output="* ]] || return 1
    assert_attributed_mutant_kill terminal_signal_mask "$terminal_mask_filter" \
        "$expected" "$status" "$output" || return 1

    post_popen_filter='OpenSSL deadline terminates stubborn descendant pipe holders'
    for callsite in silent bounded source_history masked; do
        post_popen_mutant="${BATS_TEST_TMPDIR}/post-popen-${callsite}.bats"
        cp "$FUNCTIONAL_TEST" "$post_popen_mutant" || return 1
        "$PYTHON" - "$post_popen_mutant" "$REPO_ROOT" "$callsite" <<'PY' || return 1
import sys

path, repo_root, callsite = sys.argv[1:]
source = open(path, encoding="utf-8").read()
root_old = '    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."\n'
root_new = f"    REPO_ROOT={repo_root!r}\n"
if callsite == "masked":
    guard = ('        remaining_validation_time()  # SECURITY_RULE:popen_post_unmask_deadline\n'
             '        globals()["VALIDATION_DEADLINE"] = time.monotonic() + 20\n')
    mutant = ('        pass  # MUTATED:popen_post_unmask_deadline\n'
              '        globals()["VALIDATION_DEADLINE"] = time.monotonic() + 20\n')
else:
    guard = 'if mode == "signal":\n'
    mutant = f'if mode == "signal" and callsite != {callsite!r}:  # MUTATED:post_popen_{callsite}\n'
if source.count(root_old) != 1 or source.count(guard) != 1:
    raise SystemExit(f"POST_POPEN_MUTATION_SEAM_MISSING_OR_AMBIGUOUS:{callsite}")
source = source.replace(root_old, root_new, 1).replace(guard, mutant, 1)
open(path, "w", encoding="utf-8").write(source)
PY
        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
            CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON" \
            CUSTOMER_DELIVERY_POST_POPEN_ONLY="$callsite" \
            bats --filter "^${post_popen_filter}$" "$post_popen_mutant"
        if [[ "$callsite" == masked ]]; then
            [[ "$output" == *"masked_popen_deadline_failure="* ]] || return 1
        else
            [[ "$output" == *"post_popen_signal_failure=${callsite}"* ]] || return 1
        fi
        [ "$status" -ne 0 ] \
            && [ "$(printf '%s\n' "$output" | awk -v target="not ok 1 ${post_popen_filter}" '$0 == target { count++ } END { print count+0 }')" -eq 1 ] \
            && [[ "$output" != *"setup_file failed"* ]] \
            && [[ "$output" != *"BATS_TEST_TIMEOUT"* ]] \
            || { printf 'post_popen_mutant_not_attributed=%s status=%s output=%s\n' \
                "$callsite" "$status" "$output"; return 1; }
        "$PYTHON" -c \
            'import hashlib,sys; print(f"RED_SENTINEL:{sys.argv[1]}:{hashlib.sha256(sys.argv[2].encode()).hexdigest()}")' \
            "post_popen_${callsite}" "${callsite}|${post_popen_filter}"
    done

    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON" \
        CUSTOMER_DELIVERY_POST_POPEN_ONLY=silent \
        bats --filter "^${post_popen_filter}$" "$FUNCTIONAL_TEST"
    assert_baseline_green "$post_popen_filter" || return 1

    post_popen_readiness_control="${BATS_TEST_TMPDIR}/post-popen-readiness-control.bats"
    cp "$FUNCTIONAL_TEST" "$post_popen_readiness_control" || return 1
    "$PYTHON" - "$post_popen_readiness_control" "$REPO_ROOT" <<'PY' || return 1
import sys

path, repo_root = sys.argv[1:]
source = open(path, encoding="utf-8").read()
root_old = '    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."\n'
root_new = f"    REPO_ROOT={repo_root!r}\n"
startup = '''    handle.write('if [ "${1:-}" = version ]; then\\n')
    handle.write("  (trap '' TERM; sleep 30) &\\n")
'''
delayed_startup = '''    handle.write('if [ "${1:-}" = version ]; then\\n')
    handle.write("  sleep 1.1\\n")  # TEST_FIXTURE_READINESS_DELAY
    handle.write("  (trap '' TERM; sleep 30) &\\n")
'''
run_anchor = '''    force_test_logical_deadline_shutdown_race "$pid_file" || return 1
    rebind_test_openssl "$shim" || return 1
    run_test_framework_json
'''
stale_run = '''    force_test_logical_deadline_shutdown_race "$pid_file" || return 1
    rebind_test_openssl "$shim" || return 1
    printf '%s\\n' 99999999 > "$pid_file"  # TEST_STALE_PID_MARKER
    run_test_framework_json
    [ "$(<"$pid_file")" != 99999999 ] \\
        || { printf 'stale_pid_marker_accepted=99999999\\n'; return 1; }
'''
if (
    source.count(root_old) != 1
    or source.count(startup) != 1
    or source.count(run_anchor) != 1
):
    raise SystemExit("POST_POPEN_READINESS_CONTROL_SEAM_MISSING_OR_AMBIGUOUS")
source = (
    source.replace(root_old, root_new, 1)
    .replace(startup, delayed_startup, 1)
    .replace(run_anchor, stale_run, 1)
)
open(path, "w", encoding="utf-8").write(source)
PY
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON" \
        CUSTOMER_DELIVERY_POST_POPEN_ONLY=silent \
        bats --filter "^${post_popen_filter}$" "$post_popen_readiness_control"
    assert_baseline_green "$post_popen_filter" || return 1

    post_popen_stale_mutant="${BATS_TEST_TMPDIR}/post-popen-stale-marker-mutant.bats"
    cp "$post_popen_readiness_control" "$post_popen_stale_mutant" || return 1
    "$PYTHON" - "$post_popen_stale_mutant" <<'PY' || return 1
import sys

path = sys.argv[1]
source = open(path, encoding="utf-8").read()
guard = '''                        and fixture_pid != process.pid
                        and os.getpgid(fixture_pid) == process.pid
                        and os.getsid(fixture_pid) == process.pid
'''
mutant = '''                        and True  # MUTATED:stale_pid_group_binding
'''
if source.count(guard) != 1:
    raise SystemExit("POST_POPEN_STALE_MARKER_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
open(path, "w", encoding="utf-8").write(source.replace(guard, mutant, 1))
PY
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON" \
        CUSTOMER_DELIVERY_POST_POPEN_ONLY=silent \
        bats --filter "^${post_popen_filter}$" "$post_popen_stale_mutant"
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"stale_pid_marker_accepted=99999999"* ]] \
        && [ "$(printf '%s\n' "$output" | awk -v target="not ok 1 ${post_popen_filter}" '$0 == target { count++ } END { print count+0 }')" -eq 1 ] \
        && [[ "$output" != *"setup_file failed"* ]] \
        && [[ "$output" != *"BATS_TEST_TIMEOUT"* ]] \
        || { printf 'post_popen_stale_marker_mutant_not_attributed=status=%s output=%s\n' \
            "$status" "$output"; return 1; }
    "$PYTHON" -c \
        'import hashlib,sys; print(f"RED_SENTINEL:{sys.argv[1]}:{hashlib.sha256(sys.argv[2].encode()).hexdigest()}")' \
        post_popen_stale_marker "${post_popen_filter}|99999999"
}

@test "same-clock and Alarm diagnostic mutation attribution is fail-closed" {
    local post_popen_control post_popen_mutant post_popen_filter
    local marker_kind marker_value marker_hex sentinel_kind
    local diagnostic_mutant diagnostic_filter pid_width_mutant
    post_popen_filter='OpenSSL deadline terminates stubborn descendant pipe holders'
    post_popen_control="${BATS_TEST_TMPDIR}/post-popen-same-clock-control.bats"
    cp "$FUNCTIONAL_TEST" "$post_popen_control" || return 1
    "$PYTHON" - "$post_popen_control" "$REPO_ROOT" <<'PY' || return 1
import sys

path, repo_root = sys.argv[1:]
source = open(path, encoding="utf-8").read()
root_old = '    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."\n'
root_new = f"    REPO_ROOT={repo_root!r}\n"
if source.count(root_old) != 1:
    raise SystemExit("POST_POPEN_SAME_CLOCK_CONTROL_ROOT_SEAM_MISSING_OR_AMBIGUOUS")
source = source.replace(root_old, root_new, 1)
open(path, "w", encoding="utf-8").write(source)
PY
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON" \
        CUSTOMER_DELIVERY_POST_POPEN_ONLY=silent \
        bats --filter "^${post_popen_filter}$" "$post_popen_control"
    assert_baseline_green "$post_popen_filter" || return 1

    for marker_kind in negative zero; do
        if [[ "$marker_kind" == negative ]]; then
            marker_value='-9.654199999999807e-05'
            sentinel_kind=post_popen_same_clock
        else
            marker_value=0
            sentinel_kind=post_popen_same_clock_zero
        fi
        marker_hex="$(printf '%s' "$marker_value" | "$PYTHON" -c 'import sys; print(sys.stdin.buffer.read().hex())')" || return 1
        post_popen_mutant="${BATS_TEST_TMPDIR}/post-popen-same-clock-${marker_kind}.bats"
        cp "$FUNCTIONAL_TEST" "$post_popen_mutant" || return 1
        "$PYTHON" - "$post_popen_mutant" "$REPO_ROOT" "$marker_value" "$marker_kind" <<'PY' || return 1
import sys

path, repo_root, marker_value, marker_kind = sys.argv[1:]
source = open(path, encoding="utf-8").read()
root_old = '    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."\n'
root_new = f"    REPO_ROOT={repo_root!r}\n"
guard = '    instrument_test_validator_elapsed "$elapsed_marker" || return 1  # POST_POPEN_SAME_CLOCK\n'
mutant = (
    f"    printf '%s' {marker_value!r} > \"$elapsed_marker\""
    f"  # MUTATED:post_popen_same_clock_{marker_kind}\n"
)
if source.count(root_old) != 1 or source.count(guard) != 1:
    raise SystemExit("POST_POPEN_SAME_CLOCK_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
source = source.replace(root_old, root_new, 1).replace(guard, mutant, 1)
open(path, "w", encoding="utf-8").write(source)
PY
        run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
            CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON" \
            CUSTOMER_DELIVERY_POST_POPEN_ONLY=silent \
            bats --filter "^${post_popen_filter}$" "$post_popen_mutant"
        [ "$status" -ne 0 ] \
            && [[ "$output" == *"post_popen_elapsed_invalid=silent marker_hex=${marker_hex}"* ]] \
            && [ "$(printf '%s\n' "$output" | awk -v target="not ok 1 ${post_popen_filter}" '$0 == target { count++ } END { print count+0 }')" -eq 1 ] \
            && [[ "$output" != *"setup_file failed"* ]] \
            && [[ "$output" != *"BATS_TEST_TIMEOUT"* ]] \
            || { printf 'post_popen_same_clock_mutant_not_attributed=%s status=%s output=%s\n' \
                "$marker_kind" "$status" "$output"; return 1; }
        "$PYTHON" -c \
            'import hashlib,sys; print(f"RED_SENTINEL:{sys.argv[1]}:{hashlib.sha256(sys.argv[2].encode()).hexdigest()}")' \
            "$sentinel_kind" "${post_popen_filter}|${marker_value}"
    done

    diagnostic_mutant="${BATS_TEST_TMPDIR}/alarm-diagnostic-substring.bats"
    diagnostic_filter='OpenSSL deadline terminates stubborn descendant pipe holders'
    cp "$FUNCTIONAL_TEST" "$diagnostic_mutant" || return 1
    "$PYTHON" - "$diagnostic_mutant" "$REPO_ROOT" <<'PY' || return 1
import sys

path, repo_root = sys.argv[1:]
source = open(path, encoding="utf-8").read()
guard_start = '''        "$PYTHON" - "$VALIDATOR_DIAGNOSTIC" <<'PY' || return 1
'''
guard_end = '''PY
    fi
}

report_bounded_validator_diagnostic_hex() {'''
substring = '''        [[ "$VALIDATOR_DIAGNOSTIC" == *'check-customer-delivery.sh: line '* \\
            && "$VALIDATOR_DIAGNOSTIC" == *' Alarm clock: 14 '* ]] || return 1
'''
root_old = '    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."\n'
root_new = f"    REPO_ROOT={repo_root!r}\n"
if source.count(guard_start) != 1 or source.count(guard_end) != 1 or source.count(root_old) != 1:
    raise SystemExit("ALARM_DIAGNOSTIC_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
guard_begin = source.index(guard_start)
guard_finish = source.index(guard_end, guard_begin)
source = source[:guard_begin] + substring + source[guard_finish + len("PY\n"):]
source = source.replace(root_old, root_new, 1)
open(path, "w", encoding="utf-8").write(source)
PY
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON" \
        bats --filter "^${diagnostic_filter}$" "$diagnostic_mutant"
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"not ok 1 ${diagnostic_filter}"* ]] \
        && [[ "$output" == *'assert_bounded_validator_diagnostic_grammar || return 1'* ]] \
        && [[ "$output" != *"setup_file failed"* ]] \
        && [[ "$output" != *"BATS_TEST_TIMEOUT"* ]] \
        || { printf 'alarm_diagnostic_mutant_status=%s output=%s\n' "$status" "$output"; return 1; }

    pid_width_mutant="${BATS_TEST_TMPDIR}/alarm-diagnostic-four-digit-only.bats"
    cp "$FUNCTIONAL_TEST" "$pid_width_mutant" || return 1
    "$PYTHON" - "$pid_width_mutant" "$REPO_ROOT" <<'PY' || return 1
import sys

path, repo_root = sys.argv[1:]
source = open(path, encoding="utf-8").read()
guard = "if pid_field != pid.rjust(5):\n"
four_digit_only = "if pid_field != pid.rjust(5) or len(pid) != 4:  # MUTATED:four_digit_only\n"
root_old = '    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."\n'
root_new = f"    REPO_ROOT={repo_root!r}\n"
if source.count(guard) != 1 or source.count(root_old) != 1:
    raise SystemExit("ALARM_PID_WIDTH_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
source = source.replace(guard, four_digit_only, 1).replace(root_old, root_new, 1)
open(path, "w", encoding="utf-8").write(source)
PY
    run env CUSTOMER_DELIVERY_PYTHON="$VALIDATOR_PYTHON" \
        CUSTOMER_DELIVERY_TEST_PYTHON="$PYTHON" \
        bats --filter "^${diagnostic_filter}$" "$pid_width_mutant"
    [ "$status" -ne 0 ] \
        && [[ "$output" == *"not ok 1 ${diagnostic_filter}"* ]] \
        && [[ "$output" == *'assert_bounded_validator_diagnostic_grammar || return 1'* ]] \
        && [[ "$output" != *"setup_file failed"* ]] \
        && [[ "$output" != *"BATS_TEST_TIMEOUT"* ]] \
        || { printf 'alarm_pid_width_mutant_status=%s output=%s\n' "$status" "$output"; return 1; }
}

@test "cleanup SIGALRM mask mutant is killed before registry release" {
    run_process_lifecycle_mutant cleanup-alarm
}

@test "reaped supervisor PID ownership mutant cannot signal a reused group" {
    run_process_lifecycle_mutant reused-pid
}

@test "silent completed-parent detached descendant cleanup mutant is killed" {
    run_completed_descendant_callsite_mutant silent
}

@test "bounded completed-parent detached descendant cleanup mutant is killed" {
    run_completed_descendant_callsite_mutant bounded
}

@test "source history completed-parent detached descendant cleanup mutant is killed" {
    run_completed_descendant_callsite_mutant source_history
}
