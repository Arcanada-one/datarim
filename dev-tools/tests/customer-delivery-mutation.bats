#!/usr/bin/env bats

setup() {
    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    SCRIPT="${REPO_ROOT}/dev-tools/check-customer-delivery.sh"
    FUNCTIONAL_TEST="${BATS_TEST_DIRNAME}/check-customer-delivery.bats"
    PYTHON="${CUSTOMER_DELIVERY_PYTHON:-/usr/bin/python3}"
    [[ "$PYTHON" == /* && -x "$PYTHON" && ! -d "$PYTHON" ]] \
        || { echo "ERROR: CUSTOMER_DELIVERY_PYTHON must be an absolute executable" >&2; return 1; }
    [ -f "$SCRIPT" ] || { echo "ERROR: validator missing: $SCRIPT" >&2; return 1; }
    [ -f "$FUNCTIONAL_TEST" ] || { echo "ERROR: functional tests missing: $FUNCTIONAL_TEST" >&2; return 1; }
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
    if re.match(r'^\s*\[ "\$status" ', lines[index])
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
    if lines[index] == "    return 1"
)
print(",".join(str(value) for value in allowed))
PY
}

assert_attributed_mutant_kill() {
    local marker="$1" filter="$2" expected_lines="$3"
    local nested_status="$4" nested_output="$5" reported line matched=0
    if [ "$nested_status" -eq 0 ]; then
        printf 'SURVIVED_MUTANT:%s\n' "$marker"
        return 1
    fi
    if [ "$nested_status" -eq 124 ] \
        || [[ "$nested_output" == *"setup_file failed"* ]] \
        || [[ "$nested_output" == *"syntax error"* ]] \
        || [[ "$nested_output" == *"BATS_TEST_TIMEOUT"* ]] \
        || [ "$(printf '%s\n' "$nested_output" | awk '$0 == "1..1" { count++ } END { print count+0 }')" -ne 1 ] \
        || [ "$(printf '%s\n' "$nested_output" | awk -v target="not ok 1 ${filter}" '$0 == target { count++ } END { print count+0 }')" -ne 1 ]; then
        printf 'HARNESS_INVALID:%s:execution-contract\n' "$marker"
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

        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        [ "$status" -eq 0 ] || return 1

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

        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
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

        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        [ "$status" -eq 0 ] || return 1

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

        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
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

    run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
    [ "$status" -eq 0 ] || return 1

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

    run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
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
        'git_process_group|source history deadline kills stubborn descendant pipe holders'
    )

    for pair in "${pairs[@]}"; do
        kind="${pair%%|*}"
        filter="${pair#*|}"
        expected_lines="$(expected_red_lines "$filter")" || return 1
        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        [ "$status" -eq 0 ] || return 1

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
    darwin = '''python_isolation_args=(-s)'''
    linux = '''python_isolation_args=(-I)'''
    cwd = '''/bin/bash -p -c 'cd / && exec -a "$1" "$2" "${@:3}"' bash'''
    if source.count(darwin) != 1 or source.count(linux) != 1 or source.count(cwd) != 1:
        raise SystemExit("PYTHON_CWD_ISOLATION_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    source = source.replace(darwin, 'python_isolation_args=(-s)  # MUTATED:darwin_cwd_isolation', 1)
    source = source.replace(linux, 'python_isolation_args=(-s)  # MUTATED:linux_isolation', 1)
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
elif kind == "git_process_group":
    term = '            os.killpg(process.pid, signal.SIGTERM)'
    kill = '            os.killpg(process.pid, signal.SIGKILL)'
    if source.count(term) != 1 or source.count(kill) != 1:
        raise SystemExit("GIT_PROCESS_GROUP_MUTATION_SEAM_MISSING_OR_AMBIGUOUS")
    source = source.replace(term, '            process.terminate()').replace(
        kill, '            process.kill()'
    )
else:
    raise SystemExit(f"unknown mutant: {kind}")
with open(path, "w", encoding="utf-8") as handle:
    handle.write(source)
PY
        chmod +x "$mutant"

        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
            bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_attributed_mutant_kill "$kind" "$filter" "$expected_lines" \
            "$status" "$output" \
            || { printf 'invalid_or_survived_mutant=%s status=%s output=%s\n' "$kind" "$status" "$output"; return 1; }
        printf 'mutant=%s killed_by=%s\n' "$kind" "$filter"
    done
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
        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        [ "$status" -eq 0 ] || return 1

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

        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
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

    for pair in "${pairs[@]}"; do
        kind="${pair%%|*}"
        filter="${pair#*|}"
        expected_lines="$(expected_red_lines "$filter")" || return 1
        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        [ "$status" -eq 0 ] || return 1

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

        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
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
        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        [ "$status" -eq 0 ] || return 1
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
        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
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
    )
    for pair in "${pairs[@]}"; do
        kind="${pair%%|*}"
        filter="${pair#*|}"
        expected_lines="$(expected_red_lines "$filter")" || return 1
        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        [ "$status" -eq 0 ] || return 1
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
    old = '        f"--git-dir={gitdir_fd_path}",'
    new = '        "-C", ROOT,'
else:
    raise SystemExit(kind)
assert source.count(old) == 1
open(path, "w", encoding="utf-8").write(source.replace(old, new))
PY
        chmod +x "$mutant"
        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
            bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_attributed_mutant_kill "$kind" "$filter" "$expected_lines" \
            "$status" "$output" || return 1
    done
}

@test "review inventory exactness closure and authentication mutants are independently killed" {
    local pair kind filter framework mutant expected_lines
    local -a pairs=(
        'set_exact|two-requirement epic cannot close with its second originating review missing'
        'closure|two-requirement epic cannot close with its second originating review OPEN'
        'authentication|every originating review inventory record is authenticated'
        'pair_extra|signed review inventory rejects an extra review pair'
        'id_uniqueness|signed review inventory rejects a duplicate review identity'
        'manifest_signature|signed review inventory manifest signature is independently verified'
    )
    for pair in "${pairs[@]}"; do
        kind="${pair%%|*}"
        filter="${pair#*|}"
        expected_lines="$(expected_red_lines "$filter")" || return 1
        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        [ "$status" -eq 0 ] || return 1
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
        run env CUSTOMER_DELIVERY_PYTHON="$PYTHON" CUSTOMER_DELIVERY_VALIDATOR_OVERRIDE="$mutant" \
            bats --filter "^${filter}$" "$FUNCTIONAL_TEST"
        assert_attributed_mutant_kill "$kind" "$filter" "$expected_lines" \
            "$status" "$output" || return 1
    done
}

@test "mutation kill attribution rejects setup syntax timeout and wrong-assertion failures" {
    local filter='focused contract' expected=42
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

    run assert_attributed_mutant_kill wrong "$filter" "$expected" 1 \
        $'1..1\nnot ok 1 focused contract\n# (in test file fixture.bats, line 43)\n# wrong assertion failed'
    [ "$status" -ne 0 ] && [[ "$output" == *"HARNESS_INVALID:wrong:wrong-assertion"* ]]
}
