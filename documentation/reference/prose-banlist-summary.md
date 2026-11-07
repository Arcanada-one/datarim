# Prose-banlist summary

Add `--summary-json` to `dev-tools/check-banlist-on-prose.sh` for one fixed result from its existing awk pass. The JSON result is available only for the handled scan outcomes described below.

The six fields are `schema` (`DatarimProseBanlistSummary/v1`), `result`, `exit_code`, `diagnostic_codes`, `offence_count`, and `offence_count_status`.

| Result | Exit | Diagnostic | Offence count |
|---|---:|---|---|
| `CLEAN` | 0 | `[]` | measured zero |
| `OFFENCES` | 1 | `PROSE_BANLIST_MATCH` | measured positive token-hit count |
| `NOT_APPLICABLE` | 0 | `LANGUAGE_NOT_APPLICABLE` | `null`, `NOT_MEASURED` |
| `INPUT_UNAVAILABLE` | 1 | `PROSE_BANLIST_UNAVAILABLE` or `PROSE_WHITELIST_UNAVAILABLE` | `null`, `NOT_MEASURED` |

The existing Russian-language applicability order, ASCII file-path guard, tokenizer, whitelist precedence, frontmatter handling, and literal/example gate blocks remain authoritative. Summary mode suppresses per-token lines and does not serialize a filename, line, token, path, language value, or source prose. It does not add Markdown fence parsing or change the vocabulary or default language. Invalid arguments, a missing/invalid input document, help, and unhandled tool errors remain outside the JSON guarantee.
