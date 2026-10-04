# Research basis for human-readable outcome reporting

## Problem

An agent can write fluent prose while overstating completion, hiding unverified criteria or assuming access to an earlier conversation. The solution combines plain-language presentation with explicit links between original need, conditions, plan, results and evidence. These are separate dimensions: a language heuristic cannot establish delivery or reader comprehension.

## Sources and adopted ideas

- [Agent Skills specification](https://agentskills.io/specification): a portable SKILL.md entry with optional references and scripts, with progressive context loading.
- [Diátaxis](https://diataxis.fr/): separate tutorials, how-to guides, references and explanation. Installation is a how-to; the data model is reference material.
- [Google technical writing](https://developers.google.com/tech-writing): lead with useful meaning, use concrete verbs, explain unfamiliar vocabulary and adapt depth to the reader.
- [GOV.UK content design](https://www.gov.uk/guidance/content-design/writing-for-gov-uk): start from user need and make content understandable without unnecessary jargon.
- [Semantic Versioning](https://semver.org/): report exact artifact versions and distinguish compatibility from behavior evidence.

The operator's original research export remains an external historical source. This release adopts one reporting authority, retains human-summary as a presentation adapter, and adds read-only re-explanation and scoped terminology. It does not adopt an external glossary as governing instructions.

## Evaluation limits

Unit tests establish behavior for declared structured inputs. Client files establish delivery and discovery candidates. Native model runs establish observed instruction-following in the named scenarios and versions only. Blind novice-role agent review is a proxy for understandable prose, not a human-reader study. No number from one evaluation category should be reported as another.
