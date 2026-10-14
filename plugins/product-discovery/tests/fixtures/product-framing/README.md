# Product-framing synthetic fixtures

Every input and output here is synthetic. These files are deterministic checker inputs and expected outcome notes for a reviewer running the installed skill; they are not interview records, customer evidence, or proof that a language model followed the skill.

| Fixture | Expected framing result | Structural check |
| --- | --- | --- |
| `positive-demand` | Continue inquiry; produce an OpportunityBrief and a next discriminating action; do not stop. | Pass |
| `no-demand` | Recommend Stop with rationale and counterevidence recorded. | Pass |
| `contradictory-sources` | Preserve both supplied statements and mark the conflict unresolved; do not infer demand. | Pass |
| `unavailable-source` | Record unavailable as unavailable, not as a search with no match. | Pass |
| `multilingual-ru-en` | Preserve the mixed-language input as declared; produce the brief in English. | Pass |
| `roleplayed-as-observed` | Reject the claim as independently observed, even with a raw script reference. | Fail with `E_ROLEPLAY_AS_OBSERVED` |

The checker validates artifact structure, required fields, references, and typed claim rules. It does not decide whether the skill actually selected the expected outcome; that remains a separate reviewer observation.
