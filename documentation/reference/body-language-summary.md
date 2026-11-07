# Body-language summary

Add `--summary-json` to `dev-tools/check-body-english.sh` to report the existing selected-scope scan as one fixed JSON object. The option does not change `--root`, `--scope`, marker handling, scope selection, deduplication, or the byte-level Cyrillic predicate.

The eight fields are `schema` (`DatarimBodyLanguageCheckSummary/v1`), `result`, `exit_code`, `diagnostic_codes`, `checked_count`, `checked_count_status`, `failed_file_count`, and `failed_file_count_status`. `PASS` is exit 0 with measured counts; `FAIL` is exit 1 with `BODY_LANGUAGE_CHECK_FAILED`. `failed_file_count` counts files whose scan fails, including a too-short allow-marker reason; it does not count matching lines. An empty selected scope of files is a measured zero-count pass.

Summary mode omits filenames, previews, reasons, root, scope text, and handled human diagnostics. The check detects a specified Cyrillic byte range; it does not establish general language, content quality, security, or admission. Existing parser, scope, root, tool, signal, and unhandled error behavior remains outside the JSON profile; supported no-flag streams and exits are preserved.
