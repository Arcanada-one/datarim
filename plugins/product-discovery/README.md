# Product Discovery

This opt-in plugin provides six structured product-research artifacts and a bundle of product-framing guidance. It supports research and recording a bounded decision; it does not validate market demand, authorize execution, spending, outreach, publishing, deployment, merge, or task closure.

## Enable

From a project with Datarim installed, run `scripts/dr-plugin.sh enable /absolute/path/to/plugins/product-discovery`. The pack is disabled until explicitly enabled. Disable it with `scripts/dr-plugin.sh disable product-discovery`; workspace artifacts and history remain in place.

## Completion scope

Research work stays in the existing `do` stage. A bounded research result is accepted through the task's existing acceptance criteria and evidence bundle, with a distinct `qa` review; L3/L4 routes retain applicable `compliance` and `archive` gates. A product brief can be a delivery input only after an accepted DecisionRecord and an explicit scope advance in the authoritative task record. `stop` closes only through the existing archive gate, and `more-evidence` remains open until its acceptance criteria are revised through the existing return-to-source path. No additional stage or lifecycle is introduced.

## Structural checker

Run `dev-tools/check-product-artifact.sh --root <bundle-root> --artifact <file>` for one artifact or `--root <bundle-root> --bundle <directory>` for cross-reference checks. Exit 0 means the declared structure and local references pass; exit 1 means an invalid artifact; exit 2 means invocation or runtime failure. Passing does not establish that claims are true or that their sources are adequate.
