# Deterministic presentation languages

`scripts/hr.py render` localizes fixed report headings, status labels and generated
safety explanations. It preserves the submitted requirement, outcome, question,
answer and evidence prose. This is presentation localization, not automatic
translation or evidence of reader comprehension.

The shipped catalogs are `en`, `ru`, `fr`, `ar` and `ja` in `locales/`. English is
the reply default when no preference is configured. `--language TAG` overrides
the shared preference resolver for this invocation; `--project ROOT` selects the
project whose language preferences are read. Arbitrary safe language tags are
accepted. A regional tag uses its primary catalog, such as `fr-CA` using `fr`.

If the primary catalog is unavailable, fixed labels use English. The report
includes a visible notice naming the requested tag and explaining that source
prose remains untranslated. It also includes an HTML metadata comment with
`requested`, `catalog`, `direction` and preference `source`. The direction is for
the selected catalog, so an English fallback has `direction=ltr`. Arabic labels
use native Unicode text and `direction=rtl` metadata; the renderer inserts no
invisible direction controls. The displaying application owns layout and bidi
rendering. No live application layout or language-model translation is implied.

Rendering to standard output uses `language.replies`, even if the caller redirects
output to a file. For a document that must use `language.artifacts`, the caller
must pass that resolved tag explicitly through `--language` or the `language=` API
keyword. There is no custom-catalog command-line option.

Catalogs are bounded UTF-8 JSON objects with the exact English key set and matching
named placeholders. Duplicate keys, unsafe controls, missing keys and changed
placeholders fail closed. To extend the shipped catalogs, add a reviewed source
JSON file and exercise it through `scripts/presentation.py`; do not pass catalog
text as agent instructions. Catalog selection never changes report input schemas,
protocol enum values, source bindings, evidence verification or acceptance gates.

`lint` preserves stable finding codes and severities while localizing diagnostic
messages. Spacing checks remain advisory heuristics. They detect existing Russian
joins and joins in several other scripts that normally use word spacing. They do
not flag count joins in Chinese or Japanese, and literal paths, code and opaque
identifiers retain their exemptions. These checks are not a universal grammar
validator or a substitute for semantic review.
