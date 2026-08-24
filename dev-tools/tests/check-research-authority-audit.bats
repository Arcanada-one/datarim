#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
    SCRIPT="${RESEARCH_AUDIT_SCRIPT:-${REPO_ROOT}/dev-tools/check-research-authority-audit.py}"
    ROOT="${BATS_TEST_TMPDIR}/fixture"
    KNOWLEDGE="${ROOT}/knowledge"
    INSIGHTS="${ROOT}/INSIGHTS.md"
    MANIFEST="${ROOT}/authority-audit.json"
    COMMENT_JSON="${ROOT}/comment-101.json"
    CACHE="${ROOT}/external-cache"
    mkdir -p "${KNOWLEDGE}/research/sources/review" \
        "${KNOWLEDGE}/graph/data/local" "${KNOWLEDGE}/resolver/data/authority" \
        "${KNOWLEDGE}/reports" "$CACHE"

    printf '%s\n' '## R1-01 · Alpha heading' \
        >"${KNOWLEDGE}/research/sources/review/r1.md"
    printf '%s\n' '**R2-01 · Beta' 'heading**, with punctuation after the bold span.' \
        >"${KNOWLEDGE}/research/sources/review/r2.md"
    printf '%s\n' '| Finding | Decision | Subtask |' \
        '| R1-01 Alpha | **Taken** | TALO-0033 |' \
        >"${KNOWLEDGE}/research/sources/review/r1-map.md"
    printf '%s\n' \
        '{"content_digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","logical_id":"candidate-role","revision_id":"candidate-role@r1"}' \
        >"${KNOWLEDGE}/graph/data/local/candidate-role@r1.json"
    printf '%s\n' \
        '{"contract":{"contract_digest":"sha256:1111111111111111111111111111111111111111111111111111111111111111","body":{"resolution_receipt_digest":"sha256:2222222222222222222222222222222222222222222222222222222222222222"}},"issuance_envelope":{"envelope_digest":"sha256:3333333333333333333333333333333333333333333333333333333333333333"}}' \
        >"${KNOWLEDGE}/reports/planning.json"
    printf '%s\n' \
        '[{"authority_class":"operator","authority_id":"operator","event_id":"evt-approve-r1","event_type":"approve","issued_at":"2026-08-24T00:00:00Z","kind":"AuthorityEvent","schema_version":"talomnia-ontology/v1","subject":{"content_digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","id":"candidate-role@r1","subject_kind":"revision"}}]' \
        >"${KNOWLEDGE}/resolver/data/authority/events.json"
    git -C "$KNOWLEDGE" init -q
    git -C "$KNOWLEDGE" config user.name test
    git -C "$KNOWLEDGE" config user.email test@example.invalid
    git -C "$KNOWLEDGE" add .
    GIT_AUTHOR_DATE='2026-08-24T00:00:00Z' GIT_COMMITTER_DATE='2026-08-24T00:00:00Z' \
        git -C "$KNOWLEDGE" commit -q -m fixture

    printf '%s\n' \
        '# Research' \
        '## Source register' \
        '| ID | Authority and URL | Applicability | Selection |' \
        '|---|---|---|---|' \
        '| S20 | Reference — https://example.test/reference | Test | **Selected:** use it. **Rejected:** mutable-only identity. |' \
        'Mapping comment: https://github.com/example/reference/issues/42#issuecomment-101' \
        '#### Revision 1 item coverage' \
        '| Item | Verbatim item heading | Pinned disposition and delivery mapping | KC research selection |' \
        '|---|---|---|---|' \
        '| R1-01 | Alpha heading | Taken -> `TALO-0033` | Direct: selected |' \
        '#### Revision 2 item coverage' \
        '| Item | Verbatim item heading | Pinned disposition and delivery mapping | KC research selection |' \
        '|---|---|---|---|' \
        '| R2-01 | Beta heading | Standing constraint -> all subtasks | Cross-functional: selected |' \
        'Derived: sha256:1111111111111111111111111111111111111111111111111111111111111111 sha256:2222222222222222222222222222222222222222222222222222222222222222 sha256:3333333333333333333333333333333333333333333333333333333333333333 candidate-role candidate-role@r1 sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
        '### Approved Talomnia candidates' \
        '| Disposition | Kind; path | Exact revision and digest | Lifecycle; relevant relations |' \
        '|---|---|---|---|' \
        '| **Reuse** | Role; `graph/data/local/candidate-role@r1.json` | `candidate-role@r1`; `sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` | approved |' \
        >"$INSIGHTS"

    jq -n --arg body $'| Finding | Decision | Lands in |\n|---|---|---|\n| R2-01 beta | **Taken** | (all subtasks) |\n' \
        '{id:101,html_url:"https://github.com/example/reference/issues/42#issuecomment-101",issue_url:"https://api.github.com/repos/example/reference/issues/42",body:$body}' >"$COMMENT_JSON"
    COMMENT_DIGEST="$(jq -j .body "$COMMENT_JSON" | sha256sum | cut -d' ' -f1)"
    printf '%s\n' 'Pinned external body' >"${CACHE}/S20.body"
    EXTERNAL_DIGEST="$(sha256sum "${CACHE}/S20.body" | cut -d' ' -f1)"
    EXTERNAL_BLOB="$(git hash-object "${CACHE}/S20.body")"
    R1_BLOB="$(git -C "$KNOWLEDGE" rev-parse 'HEAD:research/sources/review/r1.md')"
    R2_BLOB="$(git -C "$KNOWLEDGE" rev-parse 'HEAD:research/sources/review/r2.md')"
    MAP_BLOB="$(git -C "$KNOWLEDGE" rev-parse 'HEAD:research/sources/review/r1-map.md')"
    SNAPSHOT="$(git -C "$KNOWLEDGE" rev-parse HEAD)"
    ITEM_DIGEST="$(printf '%s' $'R1-01\037Alpha heading\037Taken -> `TALO-0033`\037Direct: selected\nR2-01\037Beta heading\037Standing constraint -> all subtasks\037Cross-functional: selected' | sha256sum | cut -d' ' -f1)"

    jq -n \
        --arg snapshot "$SNAPSHOT" --arg r1_blob "$R1_BLOB" --arg r2_blob "$R2_BLOB" \
        --arg map_blob "$MAP_BLOB" --arg item_digest "$ITEM_DIGEST" \
        --arg comment_digest "$COMMENT_DIGEST" --arg external_digest "$EXTERNAL_DIGEST" \
        --arg external_blob "$EXTERNAL_BLOB" '{
          schema_version:"datarim.research-authority-audit/v1",
          task_id:"TALO-TEST",
          declared_language:"en",
          knowledge_snapshot:$snapshot,
          authority_events_path:"resolver/data/authority/events.json",
          comment_body_digest_algorithm:"github-json-body-utf8-no-extra-lf/1",
          reviews:[
            {id:"R1",source_path:"research/sources/review/r1.md",git_blob:$r1_blob,expected_items:1,
             mapping_source_path:"research/sources/review/r1-map.md",mapping_source_git_blob:$map_blob},
            {id:"R2",source_path:"research/sources/review/r2.md",git_blob:$r2_blob,expected_items:1,mapping_comment_id:101}
          ],
          comments:[{id:101,repository:"example/reference",issue_number:42,navigation_url:"https://github.com/example/reference/issues/42#issuecomment-101",body_sha256:$comment_digest}],
          item_table:{expected_rows:2,canonicalization:"cells-trimmed-unit-separator-rows-lf-no-final-lf/1",sha256:$item_digest},
          candidates:[{path:"graph/data/local/candidate-role@r1.json",revision_id:"candidate-role@r1",content_digest:"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}],
          derived_records:[
            {id:"planning",record_type:"planning-envelope",evidence_path:"reports/planning.json",assertions:[
              {json_pointer:"/contract/contract_digest",equals:"sha256:1111111111111111111111111111111111111111111111111111111111111111"},
              {json_pointer:"/contract/body/resolution_receipt_digest",equals:"sha256:2222222222222222222222222222222222222222222222222222222222222222"},
              {json_pointer:"/issuance_envelope/envelope_digest",equals:"sha256:3333333333333333333333333333333333333333333333333333333333333333"}
            ]},
            {id:"candidate-role@r1",record_type:"approved-artifact",evidence_path:"graph/data/local/candidate-role@r1.json",assertions:[
              {json_pointer:"/logical_id",equals:"candidate-role"},
              {json_pointer:"/revision_id",equals:"candidate-role@r1"},
              {json_pointer:"/content_digest",equals:"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
            ],authority_required:"approve",authority_revision_id:"candidate-role@r1",authority_content_digest:"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
          ],
          external_pins:[{source_id:"S20",navigation_url:"https://example.test/reference",accessed_at:"2026-08-24",repository:"example/reference",commit:"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",path:"docs/reference.md",git_blob:$external_blob,content_sha256:$external_digest,immutable_url:"https://github.com/example/reference/blob/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/docs/reference.md",cache_file:"S20.body"}]
        }' >"$MANIFEST"
}

run_validator() {
    run python3 "$SCRIPT" --expected-task-id TALO-TEST \
        --manifest "$MANIFEST" --insights "$INSIGHTS" \
        --knowledge-root "$KNOWLEDGE" --comment-json "101=${COMMENT_JSON}" \
        --external-cache-dir "$CACHE"
}

assert_not_met() {
    local expected="$1"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'research_authority_audit=NOT_MET'* ]] \
        && [[ "$output" == *"$expected"* ]]
}

@test "exact review, mapping, candidate authority, comment bytes and immutable source pins are MET" {
    run_validator
    [ "$status" -eq 0 ] \
        && [[ "$output" == *'research_authority_audit=MET items=2 candidates=1 external_pins=1'* ]]
}

@test "audit task identity is code-owned" {
    jq '.task_id="UNRELATED-9999"' "$MANIFEST" >"${MANIFEST}.new"
    mv "${MANIFEST}.new" "$MANIFEST"
    run_validator
    assert_not_met 'task_id_mismatch:expected=TALO-TEST:actual=UNRELATED-9999'
}

@test "caller identity rejects a fully coupled known-profile bundle swap" {
    run python3 "$SCRIPT" --expected-task-id TALO-0001 \
        --manifest "$MANIFEST" --insights "$INSIGHTS" --knowledge-root "$KNOWLEDGE" \
        --comment-json "101=${COMMENT_JSON}" --external-cache-dir "$CACHE"
    assert_not_met 'task_id_mismatch:expected=TALO-0001:actual=TALO-TEST'
}

@test "omitted item is rejected with its review attribution" {
    sed -i '/| R2-01 |/d' "$INSIGHTS"
    run_validator
    assert_not_met 'item_count_mismatch:R2:expected=1:actual=0'
}

@test "duplicate item ID is rejected" {
    printf '%s\n' '| R1-01 | Alpha heading | Taken -> `TALO-0033` | Direct: selected |' >>"$INSIGHTS"
    run_validator
    assert_not_met 'duplicate_item_id:R1-01'
}

@test "verbatim source heading mutation is rejected" {
    sed -i 's/Alpha heading/Changed heading/' "$INSIGHTS"
    run_validator
    assert_not_met 'verbatim_heading_mismatch:R1-01'
}

@test "mapping mutation preserving all IDs and headings is rejected" {
    sed -i 's/TALO-0033/TALO-9999/' "$INSIGHTS"
    local mutant_digest
    mutant_digest="$(printf '%s' $'R1-01\037Alpha heading\037Taken -> `TALO-9999`\037Direct: selected\nR2-01\037Beta heading\037Standing constraint -> all subtasks\037Cross-functional: selected' | sha256sum | cut -d' ' -f1)"
    jq --arg digest "$mutant_digest" '.item_table.sha256=$digest' "$MANIFEST" >"${MANIFEST}.new"
    mv "${MANIFEST}.new" "$MANIFEST"
    run_validator
    assert_not_met 'delivery_mapping_mismatch:R1-01'
}

@test "unauthorized extra delivery target is rejected after digest reseal" {
    sed -i 's/Taken -> `TALO-0033`/Taken -> `TALO-0033`, `TALO-9999`/' "$INSIGHTS"
    local mutant_digest
    mutant_digest="$(printf '%s' $'R1-01\037Alpha heading\037Taken -> `TALO-0033`, `TALO-9999`\037Direct: selected\nR2-01\037Beta heading\037Standing constraint -> all subtasks\037Cross-functional: selected' | sha256sum | cut -d' ' -f1)"
    jq --arg digest "$mutant_digest" '.item_table.sha256=$digest |
      .authorized_mapping_additions={"R1-01":["TALO-9999"]}' \
        "$MANIFEST" >"${MANIFEST}.new"
    mv "${MANIFEST}.new" "$MANIFEST"
    run_validator
    assert_not_met 'delivery_mapping_mismatch:R1-01'
}

@test "bad source path and blob are rejected independently" {
    jq '.reviews[0].source_path="research/sources/review/missing.md" | .reviews[1].git_blob="0000000000000000000000000000000000000000"' "$MANIFEST" >"${MANIFEST}.new"
    mv "${MANIFEST}.new" "$MANIFEST"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'source_path_missing:R1'* ]] \
        && [[ "$output" == *'source_blob_mismatch:R2'* ]]
}

@test "candidate path revision and digest mutations are attributable" {
    jq '.candidates += [
      {"path":"graph/data/local/missing.json","revision_id":"missing@r1","content_digest":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
      {"path":"graph/data/local/candidate-role@r1.json","revision_id":"wrong@r1","content_digest":"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}
    ]' "$MANIFEST" >"${MANIFEST}.new"
    mv "${MANIFEST}.new" "$MANIFEST"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'candidate_path_missing:missing@r1'* ]] \
        && [[ "$output" == *'candidate_revision_mismatch:wrong@r1'* ]] \
        && [[ "$output" == *'candidate_digest_mismatch:wrong@r1'* ]]
}

@test "closed candidate set rejects omissions and extras independently" {
    local manifest_base
    manifest_base="${ROOT}/authority-audit.base.json"
    cp "$MANIFEST" "$manifest_base"

    jq 'del(.candidates[0])' "$manifest_base" >"$MANIFEST"
    run_validator
    assert_not_met 'candidate_set_mismatch:missing=candidate-role@r1'

    jq '.candidates += [{path:"graph/data/local/extra@r1.json",revision_id:"extra@r1",content_digest:"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]' \
        "$manifest_base" >"$MANIFEST"
    run_validator
    assert_not_met 'candidate_set_mismatch:extra=extra@r1'

    jq '.logical_id="wrong-logical-id"' \
        "${KNOWLEDGE}/graph/data/local/candidate-role@r1.json" >"${ROOT}/candidate.new"
    mv "${ROOT}/candidate.new" "${KNOWLEDGE}/graph/data/local/candidate-role@r1.json"
    git -C "$KNOWLEDGE" add .
    GIT_AUTHOR_DATE='2026-08-24T00:02:00Z' GIT_COMMITTER_DATE='2026-08-24T00:02:00Z' \
        git -C "$KNOWLEDGE" commit -q -m wrong-logical-id
    jq --arg snapshot "$(git -C "$KNOWLEDGE" rev-parse HEAD)" \
        '.knowledge_snapshot=$snapshot' "$manifest_base" >"$MANIFEST"
    run_validator
    assert_not_met 'candidate_logical_id_mismatch:candidate-role@r1'
}

@test "latest non-approve authority event is rejected" {
    jq '. += [{"authority_class":"operator","authority_id":"operator","event_id":"evt-revoke-r1","event_type":"revoke","issued_at":"2026-08-24T01:00:00Z","kind":"AuthorityEvent","schema_version":"talomnia-ontology/v1","subject":{"content_digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","id":"candidate-role@r1","subject_kind":"revision"}}]' \
        "${KNOWLEDGE}/resolver/data/authority/events.json" >"${ROOT}/events.new"
    mv "${ROOT}/events.new" "${KNOWLEDGE}/resolver/data/authority/events.json"
    git -C "$KNOWLEDGE" add .
    GIT_AUTHOR_DATE='2026-08-24T01:00:00Z' GIT_COMMITTER_DATE='2026-08-24T01:00:00Z' \
        git -C "$KNOWLEDGE" commit -q -m revoke
    jq --arg snapshot "$(git -C "$KNOWLEDGE" rev-parse HEAD)" '.knowledge_snapshot=$snapshot' \
        "$MANIFEST" >"${MANIFEST}.new"
    mv "${MANIFEST}.new" "$MANIFEST"
    run_validator
    assert_not_met 'candidate_latest_authority_not_approve:candidate-role@r1:revoke'
    jq '.[0:1]' "${KNOWLEDGE}/resolver/data/authority/events.json" >"${ROOT}/events.dirty"
    mv "${ROOT}/events.dirty" "${KNOWLEDGE}/resolver/data/authority/events.json"
    run_validator
    assert_not_met 'candidate_latest_authority_not_approve:candidate-role@r1:revoke'
}

@test "dirty source and candidate bytes cannot alter exact snapshot verdict" {
    printf '%s\n' '## R1-01 · Dirty replacement' \
        >"${KNOWLEDGE}/research/sources/review/r1.md"
    printf '%s\n' \
        '{"content_digest":"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","revision_id":"dirty@r9"}' \
        >"${KNOWLEDGE}/graph/data/local/candidate-role@r1.json"
    run_validator
    [ "$status" -eq 0 ] \
        && [[ "$output" == *'research_authority_audit=MET items=2 candidates=1 external_pins=1'* ]]
}

@test "oversized Git blob is rejected before content extraction" {
    local manifest_base tree_oid oversized_path oversized_oid fake_bin real_git extraction_marker
    manifest_base="${ROOT}/authority-audit.base.json"
    cp "$MANIFEST" "$manifest_base"
    tree_oid="$(git -C "$KNOWLEDGE" rev-parse 'HEAD:research/sources/review')"
    jq --arg blob "$tree_oid" \
        '.reviews[0].source_path="research/sources/review" | .reviews[0].git_blob=$blob' \
        "$manifest_base" >"$MANIFEST"
    run_validator
    assert_not_met 'git_object_type_invalid:R1'

    oversized_path="research/sources/review/oversized.bin"
    dd if=/dev/zero of="${KNOWLEDGE}/${oversized_path}" bs=1048576 count=17 status=none
    git -C "$KNOWLEDGE" add "$oversized_path"
    GIT_AUTHOR_DATE='2026-08-24T00:01:00Z' GIT_COMMITTER_DATE='2026-08-24T00:01:00Z' \
        git -C "$KNOWLEDGE" commit -q -m oversized
    oversized_oid="$(git -C "$KNOWLEDGE" rev-parse "HEAD:${oversized_path}")"
    jq --arg snapshot "$(git -C "$KNOWLEDGE" rev-parse HEAD)" \
        --arg path "$oversized_path" --arg blob "$oversized_oid" \
        '.knowledge_snapshot=$snapshot | .reviews[0].source_path=$path | .reviews[0].git_blob=$blob' \
        "$manifest_base" >"${MANIFEST}.new"
    mv "${MANIFEST}.new" "$MANIFEST"

    fake_bin="${ROOT}/oversize-git-bin"
    extraction_marker="${ROOT}/oversize-extracted"
    real_git="$(command -v git)"
    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        "case \" \$* \" in *\" cat-file blob ${oversized_oid} \"*) : >\"${extraction_marker}\"; exit 99;; esac" \
        "exec \"${real_git}\" \"\$@\"" \
        >"${fake_bin}/git"
    chmod +x "${fake_bin}/git"
    run env PATH="${fake_bin}:${PATH}" python3 "$SCRIPT" \
        --expected-task-id TALO-TEST \
        --manifest "$MANIFEST" --insights "$INSIGHTS" --knowledge-root "$KNOWLEDGE" \
        --comment-json "101=${COMMENT_JSON}" --external-cache-dir "$CACHE"
    assert_not_met 'git_object_too_large:R1'
    [ ! -e "$extraction_marker" ]
}

@test "structured derived pointers reject swapped K and R identities" {
    jq '.contract.contract_digest as $k |
      .contract.body.resolution_receipt_digest as $r |
      .contract.contract_digest=$r |
      .contract.body.resolution_receipt_digest=$k' \
        "${KNOWLEDGE}/reports/planning.json" >"${ROOT}/planning.new"
    mv "${ROOT}/planning.new" "${KNOWLEDGE}/reports/planning.json"
    git -C "$KNOWLEDGE" add .
    GIT_AUTHOR_DATE='2026-08-24T02:00:00Z' GIT_COMMITTER_DATE='2026-08-24T02:00:00Z' \
        git -C "$KNOWLEDGE" commit -q -m swap-derived
    jq --arg snapshot "$(git -C "$KNOWLEDGE" rev-parse HEAD)" '.knowledge_snapshot=$snapshot' \
        "$MANIFEST" >"${MANIFEST}.new"
    mv "${MANIFEST}.new" "$MANIFEST"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'derived_record_pointer_mismatch:planning:/contract/contract_digest'* ]] \
        && [[ "$output" == *'derived_record_pointer_mismatch:planning:/contract/body/resolution_receipt_digest'* ]]
}

@test "closed derived record set rejects omission and assertion weakening" {
    local manifest_base
    manifest_base="${ROOT}/authority-audit.base.json"
    cp "$MANIFEST" "$manifest_base"

    jq 'del(.derived_records[0])' "$manifest_base" >"$MANIFEST"
    run_validator
    assert_not_met 'derived_record_set_mismatch:missing=planning'

    jq '.derived_records += [(.derived_records[0] | .id="extra-derived")]' \
        "$manifest_base" >"$MANIFEST"
    run_validator
    assert_not_met 'derived_record_set_mismatch:extra=extra-derived'

    jq '.derived_records[0].record_type="unknown" | del(.derived_records[0].assertions[0])' \
        "$manifest_base" >"$MANIFEST"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'derived_record_type_mismatch:planning'* ]] \
        && [[ "$output" == *'derived_record_assertion_set_mismatch:planning'* ]]
}

@test "narrative artifact logical identity is structured and authority-bound" {
    jq '.logical_id="wrong-role"' "${KNOWLEDGE}/graph/data/local/candidate-role@r1.json" \
        >"${ROOT}/candidate.new"
    mv "${ROOT}/candidate.new" "${KNOWLEDGE}/graph/data/local/candidate-role@r1.json"
    git -C "$KNOWLEDGE" add .
    GIT_AUTHOR_DATE='2026-08-24T02:10:00Z' GIT_COMMITTER_DATE='2026-08-24T02:10:00Z' \
        git -C "$KNOWLEDGE" commit -q -m wrong-logical-id
    jq --arg snapshot "$(git -C "$KNOWLEDGE" rev-parse HEAD)" '.knowledge_snapshot=$snapshot' \
        "$MANIFEST" >"${MANIFEST}.new"
    mv "${MANIFEST}.new" "$MANIFEST"
    run_validator
    assert_not_met 'derived_record_pointer_mismatch:candidate-role@r1:/logical_id'
}

@test "declared-English audit rejects Cyrillic item text" {
    sed -i 's/Direct: selected/Прямой: selected/' "$INSIGHTS"
    run_validator
    assert_not_met 'declared_english_contains_cyrillic:R1-01'
}

@test "comment digest hashes JSON body UTF-8 bytes without appending LF" {
    run_validator
    [ "$status" -eq 0 ]
    jq --arg body $'| Finding | Decision | Lands in |\n|---|---|---|\n| R2-01 beta | **Taken** | (all subtasks) |\n\n' '.body=$body' "$COMMENT_JSON" >"${COMMENT_JSON}.new"
    mv "${COMMENT_JSON}.new" "$COMMENT_JSON"
    run_validator
    assert_not_met 'comment_body_digest_mismatch:101'
}

@test "comment payload identity and canonical issue URL are bound" {
    jq '.reviews[1].mapping_comment_id=999 | .comments[0].id=999 | .comments[0].navigation_url="https://example.invalid/comment/999"' \
        "$MANIFEST" >"${MANIFEST}.new"
    mv "${MANIFEST}.new" "$MANIFEST"
    run python3 "$SCRIPT" --expected-task-id TALO-TEST \
        --manifest "$MANIFEST" --insights "$INSIGHTS" \
        --knowledge-root "$KNOWLEDGE" --comment-json "999=${COMMENT_JSON}" \
        --external-cache-dir "$CACHE"
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'comment_payload_id_mismatch:999'* ]] \
        && [[ "$output" == *'comment_navigation_url_invalid:999'* ]] \
        && [[ "$output" == *'comment_payload_html_url_mismatch:999'* ]]
}

@test "closed raw-comment set rejects omission and extra comment" {
    local manifest_base
    manifest_base="${ROOT}/authority-audit.base.json"
    cp "$MANIFEST" "$manifest_base"

    jq 'del(.comments[0])' "$manifest_base" >"$MANIFEST"
    run_validator
    assert_not_met 'comment_set_mismatch:missing=101'

    jq '.comments += [(.comments[0] | .id=102 | .navigation_url="https://github.com/example/reference/issues/42#issuecomment-102")]' \
        "$manifest_base" >"$MANIFEST"
    run_validator
    assert_not_met 'comment_set_mismatch:extra=102'
}

@test "immutable external pin validates commit blob and cached content digest" {
    jq '.external_pins[0].commit="main"' "$MANIFEST" >"${MANIFEST}.new"
    mv "${MANIFEST}.new" "$MANIFEST"
    printf '%s\n' 'mutated external body' >"${CACHE}/S20.body"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'external_pin_commit_invalid:S20'* ]] \
        && [[ "$output" == *'external_pin_blob_mismatch:S20'* ]] \
        && [[ "$output" == *'external_pin_content_digest_mismatch:S20'* ]]
}

@test "closed selected-source set rejects pin omission and extra pin" {
    local manifest_base
    manifest_base="${ROOT}/authority-audit.base.json"
    cp "$MANIFEST" "$manifest_base"

    jq 'del(.external_pins[0])' "$manifest_base" >"$MANIFEST"
    run_validator
    assert_not_met 'external_pin_set_mismatch:missing=S20'

    jq '.external_pins += [(.external_pins[0] | .source_id="S99")]' \
        "$manifest_base" >"$MANIFEST"
    run_validator
    assert_not_met 'external_pin_set_mismatch:extra=S99'
}

@test "live source gate binds repository commit and path to remote bytes" {
    local fake_bin expected_raw
    fake_bin="${ROOT}/fake-curl-bin"
    expected_raw='https://raw.githubusercontent.com/example/reference/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/docs/reference.md'
    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        'for argument do url="$argument"; done' \
        "if [ \"\$url\" != \"${expected_raw}\" ]; then exit 22; fi" \
        "printf '%s\\n' 'Pinned external body'" \
        >"${fake_bin}/curl"
    chmod +x "${fake_bin}/curl"
    run env PATH="${fake_bin}:${PATH}" python3 "$SCRIPT" \
        --expected-task-id TALO-TEST \
        --manifest "$MANIFEST" --insights "$INSIGHTS" --knowledge-root "$KNOWLEDGE" \
        --comment-json "101=${COMMENT_JSON}" --external-cache-dir "$CACHE" \
        --verify-external-remote
    [ "$status" -eq 0 ]

    jq '.external_pins[0].repository="example/nonexistent" |
      .external_pins[0].commit="cccccccccccccccccccccccccccccccccccccccc" |
      .external_pins[0].path="docs/missing.md" |
      .external_pins[0].immutable_url="https://github.com/example/nonexistent/blob/cccccccccccccccccccccccccccccccccccccccc/docs/missing.md"' \
        "$MANIFEST" >"${MANIFEST}.new"
    mv "${MANIFEST}.new" "$MANIFEST"
    run env PATH="${fake_bin}:${PATH}" python3 "$SCRIPT" \
        --expected-task-id TALO-TEST \
        --manifest "$MANIFEST" --insights "$INSIGHTS" --knowledge-root "$KNOWLEDGE" \
        --comment-json "101=${COMMENT_JSON}" --external-cache-dir "$CACHE" \
        --verify-external-remote
    assert_not_met 'external_pin_remote_fetch_failed:S20'
}

@test "external source path rejects ambiguous and unsafe Git paths" {
    local unsafe_path manifest_base
    manifest_base="${ROOT}/authority-audit.base.json"
    cp "$MANIFEST" "$manifest_base"
    for unsafe_path in '../docs/reference.md' '/docs/reference.md' 'docs:reference.md' 'docs//reference.md'; do
        jq --arg path "$unsafe_path" '.external_pins[0].path=$path' \
            "$manifest_base" >"${MANIFEST}.new"
        mv "${MANIFEST}.new" "$MANIFEST"
        run_validator
        assert_not_met 'external_pin_path_invalid:S20'
    done
}

@test "malformed git hash-object response fails closed" {
    local fake_bin real_git
    fake_bin="${ROOT}/fake-bin"
    real_git="$(command -v git)"
    mkdir -p "$fake_bin"
    printf '%s\n' \
        '#!/bin/sh' \
        'if [ "$1" = "hash-object" ]; then' \
        '  cat >/dev/null' \
        '  printf "%s\n" "not-a-git-object-id"' \
        '  exit 0' \
        'fi' \
        "exec \"${real_git}\" \"\$@\"" \
        >"${fake_bin}/git"
    chmod +x "${fake_bin}/git"
    run env PATH="${fake_bin}:${PATH}" python3 "$SCRIPT" \
        --expected-task-id TALO-TEST \
        --manifest "$MANIFEST" --insights "$INSIGHTS" --knowledge-root "$KNOWLEDGE" \
        --comment-json "101=${COMMENT_JSON}" --external-cache-dir "$CACHE"
    assert_not_met 'external_pin_blob_computation_failed:S20'
}

@test "combined legacy-style mutant cannot preserve a false green" {
    sed -i 's/TALO-0033/TALO-9999/' "$INSIGHTS"
    jq '.candidates[0].content_digest="sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"' \
        "$MANIFEST" >"${MANIFEST}.new"
    mv "${MANIFEST}.new" "$MANIFEST"
    run_validator
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'item_table_digest_mismatch'* ]] \
        && [[ "$output" == *'candidate_digest_mismatch:candidate-role@r1'* ]]
}

@test "duplicate manifest keys fail closed" {
    sed -i '1a\  "declared_language": "en",' "$MANIFEST"
    run_validator
    [ "$status" -eq 2 ] \
        && [[ "$output" == *'research_authority_audit=ERROR finding=invalid_manifest'* ]]
}
