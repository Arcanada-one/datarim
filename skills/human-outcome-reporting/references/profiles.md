# Report profiles and communication moments

The requested product determines the profile. Command names are hints, not facts.
Use one product profile and one moment; re-explanation is an independent mode.

| Profile | Explain | Do not confuse |
| --- | --- | --- |
| feature | The user's new capability, verified scenarios, availability | Changed files with a working feature |
| bugfix | Original symptom, observed cause, reproduction and regression checks | A plausible cause with a demonstrated cause |
| refactor | Preserved behavior, changed structure, compatibility and checks | Cleaner code with measured performance |
| research | Question, dated sources, findings, uncertainty, recommendation | An inference with a source-supported fact |
| review | Findings, severity, evidence and consequence | Finding a defect with fixing it |
| planning | Proposed work, dependencies, acceptance and decisions needed | An approved plan with implementation |
| operations | Environment, observed before/after state, recovery and unresolved risk | A successful local script with production health |
| documentation | Audience, information added, consistency and examples checked | Written instructions with their execution |
| security | Boundary, threat, evidence, exposure and mitigations | No finding with proof of absence |
| release | Built, tested, published and accessible states separately | Packaging with publication or human acceptance |
| utility | Direct answer and relevant limitation | A lookup with a fabricated project lifecycle |

Progress: report a meaningful change tied to an open condition, plus the next step.
Do not repeat the whole report after every tool call. Update when a milestone is
verified, a blocker changes the plan, or a long operation needs explanation.

Final: state the scope actually completed, every mandatory condition, limitations,
availability and what remains. The primary agent aggregates child facts once.

Blocked, cancelled or budget-limited: explain what was obtained, what was not,
the concrete obstacle, and the action needed. Do not imply background continuation.

Handoff: give the next reader enough context to act. Store machine routing and
record identifiers separately; do not replace the human explanation with a path.

Answer: answer each question in order. No mandatory headings for a simple lookup.

The full report has no arbitrary word ceiling. A brief view explicitly identifies
itself as abbreviated and never hides negative, conflicting or unverified results.
An installation question, exact JSON protocol, translation or code-only artifact
retains its original format. Do not inject a report into that payload.
