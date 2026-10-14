# Product Discovery

This opt-in plugin provides structured product-research artifacts and product-framing guidance, including the Decision Record method and its strategist scope-modes fragment. It supports research and recording a bounded decision; it does not validate market demand, accept evidence on behalf of an owner, authorize execution, spending, outreach, publishing, deployment, merge, or task closure.

## Enable

From a project with Datarim installed, run `scripts/dr-plugin.sh enable /absolute/path/to/plugins/product-discovery`. The pack is disabled until explicitly enabled. Disable it with `scripts/dr-plugin.sh disable product-discovery`; workspace artifacts and history remain in place.

## Completion scope

Research work stays in the existing `do` stage. A bounded research result is accepted through the task's existing acceptance criteria and evidence bundle, with a distinct `qa` review; L3/L4 routes retain applicable `compliance` and `archive` gates. A product brief can be a delivery input only after an accepted DecisionRecord and an explicit scope advance in the authoritative task record. `stop` closes only through the existing archive gate, and `more-evidence` remains open until its acceptance criteria are revised through the existing return-to-source path. No additional stage or lifecycle is introduced.

The merged T1.1, T2.1, T2.3, and T3.3 contracts do not specify a canonical runtime storage path for the latest DecisionRecord or the scope-advance record. This PR proposes, pending reviewer confirmation, immutable revisions at `datarim/insights/decisions/{TASK-ID}/decision-r{revision}.md` and an exact `authorization_ref` plus authorized scope in the existing authoritative task record. Until confirmed, consumers must fail closed when the source or latest revision is missing or ambiguous; a snapshot is a replay projection, not authority.

## Structural checker

Run `dev-tools/check-product-artifact.sh --root <bundle-root> --artifact <file>` for one artifact or `--root <bundle-root> --bundle <directory>` for cross-reference checks. Exit 0 means the declared structure and local references pass; exit 1 means an invalid artifact; exit 2 means invocation or runtime failure. Passing does not establish that claims are true or that their sources are adequate.

New Decision Records use `product-artifact/2`, which separates evidence acceptance, business outcome, strategist recommendation, and authority to act. Existing `product-artifact/1` records remain readable. A strategist `GO` is advice and never grants execution authority; a v2 `GO` record without counterevidence is structurally refused.
