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
