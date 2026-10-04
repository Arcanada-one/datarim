# Try separate reply and document languages

This lesson uses an already installed Datarim project, or a standalone reporting
skill. You will resolve French replies with English documents without changing
your persistent preferences. Use Python 3.9+ for the language helper.

## Resolve the two choices

In the project directory:

```bash
python3 .datarim-runtime/skills/human-outcome-reporting/scripts/language.py resolve --project "$PWD" --replies fr --artifacts en
```

Find `replies: fr` and `artifacts: en` in the JSON output. The `sources` fields
identify the explicit overrides. This command only reads configuration; it does
not create a task or install a framework.

For standalone Codex, use
`~/.agents/skills/human-outcome-reporting/scripts/language.py` instead. Other
clients use the helper in their installed reporting skill directory.

## Ask for a reply and a document

Start a fresh native client session in the selected directory. Ask:

> Reply in French. Draft a short English plan for organizing sample notes. Do
> not modify files or run a task. Explain which checks have not been performed.

The conversation should be French and the proposed plan English. The explanation
must not claim that files were changed or checks passed. Inspect what the client
actually returned; the resolver's JSON alone does not prove it followed the
instruction. Keep any verbatim source text and code unchanged.

## Make it your default when wanted

Once you choose your own languages, use the
[configuration guide](../how-to/configure-languages.md) to save a user preference
or project document policy. The [reference](../reference/language-preferences.md)
explains why personal replies can win over shared reply defaults while project
document language wins over personal artifact defaults.

Fixed renderer labels have separate catalog coverage and disclose English
fallback when a catalog is missing. This small observation tests only your
current session; it does not establish behavior for another client or account.
