# Reporting implementation acceptance notes

This document describes the artifact scope, not a claim that every fleet installation or live model scenario has passed. Fresh release and rollout receipts identify the actual source, runtime, environment and observed verdict.

| Requirement | Implementation | Required verification |
|-------------|----------------|-----------------------|
| Standalone and framework use | Portable skill; all-command framework policy; reversible host installer | Archive/lifecycle checks and native client runs |
| Human explanation of outcomes | 11 profiles, five moments, requirement-to-evidence mapping | Positive, partial and negative scenarios; independent reader proxy |
| Do not disguise missing delivery | Separate performed, verified, delivered and accepted states | Missing/stale/conflicting/wrong-revision evidence controls |
| Read-only re-explanation | `/dr-explain`; scoped terminology; no execution authority | Native read-only and glossary-injection scenarios |
| Compatibility | One report; human-summary four sections; no hard word cap | Stop-format and machine-output controls |
| Relationships and templates | Generated framework graph and report template | Graph freshness, edge validation and template-path gates |
| Reusable distribution | Allowlisted reproducible archives and signed release | Repeat build, ZIP/digest checks and release provenance |

The frozen evaluation plan has 14 cases. Its `not_run` baseline is a protocol fixture; dated live receipts carry observations. Structural checks do not prove semantic correctness, model compliance in all future sessions or human understanding. An unexecuted or unavailable scenario must remain unmeasured. Synthetic fixtures are never production evidence.
