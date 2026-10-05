#!/usr/bin/env bats
# Independent audit regressions: configuration never becomes instructions or a link-following write.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "repository preference errors cannot cross into trusted Cursor instructions" {
    run env PYTHONPATH="$REPO_ROOT/tests" python3 -m unittest \
        test_human_reporting_install.InstallerTests.test_repository_error_text_never_becomes_cursor_instruction_context \
        test_human_reporting_install.InstallerTests.test_deep_repository_json_keeps_valid_cursor_protocol_and_discloses_error
    [ "$status" -eq 0 ]
}

@test "configuration writes and reads remain anchored during hostile path substitution" {
    run env PYTHONPATH="$REPO_ROOT/tests" python3 -m unittest \
        test_language_preferences.LanguagePreferencesTests.test_parent_swap_cannot_redirect_atomic_write_to_external_configuration \
        test_language_preferences.LanguagePreferencesTests.test_destination_swap_cannot_read_or_copy_protected_bytes \
        test_language_preferences.LanguagePreferencesTests.test_symlink_destination_or_parent_cannot_overwrite_external_file
    [ "$status" -eq 0 ]
}

@test "private-only child preferences cannot inherit a framework ancestor" {
    run env PYTHONPATH="$REPO_ROOT/tests" python3 -m unittest \
        test_language_preferences.LanguagePreferencesTests.test_local_only_child_is_anchor_below_framework_ancestor \
        test_language_preferences.LanguagePreferencesTests.test_malformed_local_only_child_does_not_fall_back_to_ancestor
    [ "$status" -eq 0 ]
}

@test "private-only child configuration cannot write an ancestor or follow its symlink" {
    run env PYTHONPATH="$REPO_ROOT/tests" python3 -m unittest \
        test_language_preferences.LanguagePreferencesTests.test_cli_local_only_child_configure_preserves_ancestor_configuration \
        test_language_preferences.LanguagePreferencesTests.test_local_only_child_symlink_configure_refuses_without_ancestor_write \
        test_language_preferences.LanguagePreferencesTests.test_invalid_local_only_marker_refuses_ancestor_fallback_and_write
    [ "$status" -eq 0 ]
}

@test "per-turn context never promotes submitted prompt or preference errors" {
    run env PYTHONPATH="$REPO_ROOT/tests" python3 -m unittest \
        test_human_reporting_install.InstallerTests.test_prompt_context_errors_are_unresolved_without_payload_promotion \
        test_human_reporting_install.InstallerTests.test_prompt_context_refreshes_preferences_ignores_prompt_and_writes_no_bytecode
    [ "$status" -eq 0 ]
}

@test "per-turn ownership refuses malformed native groups and modified callbacks" {
    run env PYTHONPATH="$REPO_ROOT/tests" python3 -m unittest \
        test_human_reporting_install.InstallerTests.test_invalid_prompt_groups_refuse_before_settings_or_state_write \
        test_human_reporting_install.InstallerTests.test_modified_owned_prompt_callback_refuses_update_and_uninstall
    [ "$status" -eq 0 ]
}

@test "native and Cursor contexts execute current source without reading unowned bytecode" {
    run env PYTHONPATH="$REPO_ROOT/tests" python3 -m unittest \
        test_human_reporting_install.InstallerTests.test_all_context_callbacks_ignore_existing_unowned_bytecode_cache
    [ "$status" -eq 0 ]
}
