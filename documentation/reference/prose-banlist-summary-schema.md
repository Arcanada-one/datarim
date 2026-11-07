# Prose-banlist summary schema

Validate a saved `DatarimProseBanlistSummary/v1` object with the local [Draft 2020-12 schema](schemas/prose-banlist-summary.v1.schema.json). This is a consumer-side structure check; it does not run the checker or establish that the result is truthful, current, secure, or produced by a particular runtime.

The schema closes the exact six-field object and its result, exit, diagnostic, and count-availability profiles. `CLEAN` and `OFFENCES` have measured counts; `NOT_APPLICABLE` and unavailable input have `null` with `NOT_MEASURED`. Unavailable banlist and whitelist inputs use distinct fixed diagnostic codes. The schema cannot prove arbitrary count arithmetic or validate the prose input.

The producer remains authoritative for the existing language applicability, tokenizer, whitelist, and scan behavior. The schema has no public identifier, remote reference, custom vocabulary, or runtime dependency. JSON Schema `integer` is mathematical; integer-valued JSON numbers such as `1.0` qualify, while booleans do not.
