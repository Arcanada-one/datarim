# Product Discovery

This opt-in plugin provides structured product-research artifacts and product-framing guidance, including the Decision Record method and its strategist scope-modes fragment. It supports research and recording a bounded decision; it does not validate market demand, accept evidence on behalf of an owner, authorize execution, spending, outreach, publishing, deployment, merge, or task closure.

For task-oriented instructions on selecting the profile and reading decision routes, see the [Product Discovery how-to](../../documentation/how-to/product-discovery-profile-and-decision-routing.md). The guide is repository documentation; it is not part of the installed skill bundle.

## Enable

From a project with Datarim installed, run `scripts/dr-plugin.sh enable /absolute/path/to/plugins/product-discovery`. The pack is disabled until explicitly enabled. Disable it with `scripts/dr-plugin.sh disable product-discovery`; workspace artifacts and history remain in place.

## Completion scope

Research work stays in the existing `do` stage. A bounded research result is accepted through the task's existing acceptance criteria and evidence bundle, with a distinct `qa` review; L3/L4 routes retain applicable `compliance` and `archive` gates. A product brief can be a delivery input only after an accepted DecisionRecord and an explicit scope advance in the authoritative task record. `stop` closes only through the existing archive gate, and `more-evidence` remains open until its acceptance criteria are revised through the existing return-to-source path. No additional stage or lifecycle is introduced.

## Runtime storage and routing

Store immutable task-bound DecisionRecord and ProductBrief revisions in `datarim/insights/decisions/{TASK-ID}/` as `decision-r{revision}.md` and `product-brief-r{revision}.md`. Create a new file for each revision and set its `supersedes` reference to the prior file digest; never rewrite a prior artifact to change its status. Record scope advances as append-only JSON objects in `## Scope Advance Records` within the authoritative `datarim/tasks/{TASK-ID}-task-description.md`. Each object contains `id`, `status`, `decision_ref` (`id`, `revision`, `digest`), `authorization_ref`, `authorized_scope`, and `parent_acceptance_contract_sha256`. The parent hash is `sha256:` plus the lowercase SHA-256 of the UTF-8 bytes beginning immediately after the `## Acceptance Criteria` heading newline and ending immediately before the next section heading, including the intervening blank line. Use `dev-tools/product-decision-route.py` as the canonical reader; it invokes the structural checker and emits a route plus a typed token. A continue route requires v2 `evidence_acceptance: accepted`, `authority_to_act.status: granted`, an accepted ProductBrief with the exact DecisionRecord digest, and a matching authorized scope advance tied to the unchanged parent contract. Missing or inconsistent state returns a typed refusal. A snapshot is a replay projection, not authority.

## Structural checker

Run `dev-tools/check-product-artifact.sh --root <bundle-root> --artifact <file>` for one artifact or `--root <bundle-root> --bundle <directory>` for cross-reference checks. Exit 0 means the declared structure and local references pass; exit 1 means an invalid artifact; exit 2 means invocation or runtime failure. Passing does not establish that claims are true or that their sources are adequate.

New Decision Records use `product-artifact/2`, which separates evidence acceptance, business outcome, strategist recommendation, and authority to act. Existing `product-artifact/1` records remain readable. A strategist `GO` is advice and never grants execution authority; a v2 `GO` record without counterevidence is structurally refused.
