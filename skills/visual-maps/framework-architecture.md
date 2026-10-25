# Framework Architecture — Generated Map

> **GENERATED FILE. DO NOT EDIT.** Source: repository inventory + `dev-tools/command-graph.yaml` + explicit references in commands/agents. Regenerate with `python3 dev-tools/framework-graph.py --write`.

Inventory: **30 commands · 19 agents · 84 skills · 52 template assets**.

## Command → Agent graph

```mermaid
graph LR
    C_dr_prd["/dr-prd"] -.->|"L2+ research; product-discovery guidance only when the plugin is enabled and the task selector is present"| A_researcher["researcher"]
    C_dr_plan["/dr-plan"] -.->|"L3-4 or reductive/ambiguous scope; product-discovery fields only when the plugin is enabled and task selector is present"| A_strategist["strategist"]
    C_dr_addskill["/dr-addskill"] --> A_skill_creator["skill-creator"]
    C_dr_compliance["/dr-compliance"] --> A_compliance["compliance"]
    C_dr_design["/dr-design"] --> A_architect["architect"]
    C_dr_do["/dr-do"] --> A_developer["developer"]
    C_dr_do["/dr-do"] --> A_peer_reviewer["peer-reviewer"]
    C_dr_do["/dr-do"] --> A_researcher["researcher"]
    C_dr_doctor["/dr-doctor"] --> A_planner["planner"]
    C_dr_dream["/dr-dream"] --> A_librarian["librarian"]
    C_dr_edit["/dr-edit"] --> A_editor["editor"]
    C_dr_init["/dr-init"] --> A_planner["planner"]
    C_dr_optimize["/dr-optimize"] --> A_optimizer["optimizer"]
    C_dr_orchestrate["/dr-orchestrate"] --> A_dr_orchestrate_resolver["dr-orchestrate-resolver"]
    C_dr_plan["/dr-plan"] --> A_peer_reviewer["peer-reviewer"]
    C_dr_plugin["/dr-plugin"] --> A_developer["developer"]
    C_dr_prd["/dr-prd"] --> A_peer_reviewer["peer-reviewer"]
    C_dr_publish["/dr-publish"] --> A_writer["writer"]
    C_dr_qa["/dr-qa"] --> A_reviewer["reviewer"]
    C_dr_quick["/dr-quick"] --> A_developer["developer"]
    C_dr_verify["/dr-verify"] --> A_peer_reviewer["peer-reviewer"]
    C_dr_write["/dr-write"] --> A_writer["writer"]
```

## Agent → Skill graph

```mermaid
graph LR
    A_researcher["researcher"] --> F_plugins_product_discovery_skills_hypothesis_validation_researcher_product_discovery_md["plugins/product-discovery/skills/hypothesis-validation/researcher.product-discovery.md"]
    A_researcher["researcher"] --> PLUGIN_product_discovery["product-discovery"]
    A_researcher["researcher"] --> S_product_discovery_hypothesis_validation["product-discovery/hypothesis-validation"]
    A_strategist["strategist"] --> F_plugins_product_discovery_skills_decision_record_strategist_product_discovery_md["plugins/product-discovery/skills/decision-record/strategist.product-discovery.md"]
    A_strategist["strategist"] --> PLUGIN_product_discovery["product-discovery"]
    A_strategist["strategist"] --> S_product_discovery_decision_record["product-discovery/decision-record"]
    A_strategist["strategist"] --> S_product_discovery_hypothesis_validation["product-discovery/hypothesis-validation"]
    A_architect["architect"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_architect["architect"] --> S_cta_format["cta-format"]
    A_architect["architect"] --> S_datarim_system["datarim-system"]
    A_architect["architect"] --> S_immutability["immutability"]
    A_architect["architect"] --> S_performance["performance"]
    A_architect["architect"] --> S_security["security"]
    A_architect["architect"] --> S_tech_stack["tech-stack"]
    A_code_simplifier["code-simplifier"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_code_simplifier["code-simplifier"] --> S_security["security"]
    A_compliance["compliance"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_compliance["compliance"] --> S_compliance["compliance"]
    A_compliance["compliance"] --> S_cta_format["cta-format"]
    A_compliance["compliance"] --> S_immutability["immutability"]
    A_compliance["compliance"] --> S_security["security"]
    A_developer["developer"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_developer["developer"] --> S_ai_quality["ai-quality"]
    A_developer["developer"] --> S_cta_format["cta-format"]
    A_developer["developer"] --> S_datarim_system["datarim-system"]
    A_developer["developer"] --> S_immutability["immutability"]
    A_developer["developer"] --> S_security["security"]
    A_developer["developer"] --> S_testing["testing"]
    A_devops["devops"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_devops["devops"] --> S_datarim_system["datarim-system"]
    A_devops["devops"] --> S_infra_automation["infra-automation"]
    A_devops["devops"] --> S_security["security"]
    A_devops["devops"] --> S_tech_stack["tech-stack"]
    A_devops["devops"] --> S_testing["testing"]
    A_dr_orchestrate_resolver["dr-orchestrate-resolver"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_editor["editor"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_editor["editor"] --> S_datarim_system["datarim-system"]
    A_editor["editor"] --> S_factcheck["factcheck"]
    A_editor["editor"] --> S_humanize["humanize"]
    A_editor["editor"] --> S_image_prompting["image-prompting"]
    A_editor["editor"] --> S_immutability["immutability"]
    A_librarian["librarian"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_librarian["librarian"] --> S_datarim_system["datarim-system"]
    A_librarian["librarian"] --> S_dream["dream"]
    A_optimizer["optimizer"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_optimizer["optimizer"] --> S_datarim_system["datarim-system"]
    A_optimizer["optimizer"] --> S_evolution["evolution"]
    A_peer_reviewer["peer-reviewer"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_peer_reviewer["peer-reviewer"] --> S_security["security"]
    A_peer_reviewer["peer-reviewer"] --> S_self_verification["self-verification"]
    A_planner["planner"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_planner["planner"] --> S_ai_quality["ai-quality"]
    A_planner["planner"] --> S_cta_format["cta-format"]
    A_planner["planner"] --> S_datarim_system["datarim-system"]
    A_planner["planner"] --> S_immutability["immutability"]
    A_planner["planner"] --> S_tech_stack["tech-stack"]
    A_researcher["researcher"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_researcher["researcher"] --> S_datarim_system["datarim-system"]
    A_researcher["researcher"] --> S_research_workflow["research-workflow"]
    A_researcher["researcher"] --> S_security["security"]
    A_researcher["researcher"] --> S_tech_stack["tech-stack"]
    A_reviewer["reviewer"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_reviewer["reviewer"] --> S_cta_format["cta-format"]
    A_reviewer["reviewer"] --> S_datarim_system["datarim-system"]
    A_reviewer["reviewer"] --> S_immutability["immutability"]
    A_reviewer["reviewer"] --> S_security["security"]
    A_reviewer["reviewer"] --> S_testing["testing"]
    A_security["security"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_security["security"] --> S_compliance["compliance"]
    A_security["security"] --> S_datarim_system["datarim-system"]
    A_security["security"] --> S_security["security"]
    A_skill_creator["skill-creator"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_skill_creator["skill-creator"] --> S_datarim_system["datarim-system"]
    A_skill_creator["skill-creator"] --> S_evolution["evolution"]
    A_skill_creator["skill-creator"] --> S_writing["writing"]
    A_sre["sre"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_sre["sre"] --> S_datarim_system["datarim-system"]
    A_sre["sre"] --> S_infra_automation["infra-automation"]
    A_sre["sre"] --> S_performance["performance"]
    A_sre["sre"] --> S_security["security"]
    A_strategist["strategist"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_strategist["strategist"] --> S_datarim_system["datarim-system"]
    A_tester["tester"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_tester["tester"] --> S_datarim_system["datarim-system"]
    A_tester["tester"] --> S_frontend_ui["frontend-ui"]
    A_tester["tester"] --> S_immutability["immutability"]
    A_tester["tester"] --> S_security["security"]
    A_tester["tester"] --> S_testing["testing"]
    A_writer["writer"] --> S_human_outcome_reporting["human-outcome-reporting"]
    A_writer["writer"] --> S_datarim_system["datarim-system"]
    A_writer["writer"] --> S_factcheck["factcheck"]
    A_writer["writer"] --> S_humanize["humanize"]
    A_writer["writer"] --> S_image_prompting["image-prompting"]
    A_writer["writer"] --> S_immutability["immutability"]
    A_writer["writer"] --> S_publishing["publishing"]
```

## Complete inventory

### Commands

`/dr-addskill`, `/dr-archive`, `/dr-auto`, `/dr-compliance`, `/dr-continue`, `/dr-design`, `/dr-do`, `/dr-doctor`, `/dr-dream`, `/dr-edit`, `/dr-explain`, `/dr-finalize`, `/dr-help`, `/dr-init`, `/dr-next`, `/dr-optimize`, `/dr-orchestrate`, `/dr-plan`, `/dr-plugin`, `/dr-prd`, `/dr-publish`, `/dr-qa`, `/dr-quick`, `/dr-save`, `/dr-status`, `/dr-verify`, `/dr-wizard`, `/dr-write`, `/factcheck`, `/humanize`

### Agents

`architect`, `code-simplifier`, `compliance`, `developer`, `devops`, `dr-orchestrate-resolver`, `editor`, `librarian`, `optimizer`, `peer-reviewer`, `planner`, `researcher`, `reviewer`, `security`, `skill-creator`, `sre`, `strategist`, `tester`, `writer`

### Skills

`adversarial-review`, `ai-quality`, `artifact-context`, `autonomous-mode`, `brainstorming`, `code-contracts`, `compliance`, `consilium`, `context-window-self-clearing`, `cron-agent-patterns`, `cta-format`, `customer-delivery`, `datarim-doctor`, `datarim-system`, `diataxis-docs`, `discovery`, `dispatching-parallel-agents`, `dr-init-id-collision-window`, `dr-next-snapshot-replay`, `dream`, `dx-review`, `edge-case-hunter`, `evolution`, `executing-plans`, `expectations-checklist`, `factcheck`, `file-sync-config`, `finishing-a-development-branch`, `fleet`, `fleet/l1-basic`, `fleet/l2-structured`, `fleet/l3-analyst`, `fleet/l4-expert`, `fleet/l5-autonomous`, `frontend-ui`, `health-controller-stub-detector`, `human-outcome-reporting`, `human-summary`, `humanize`, `image-prompting`, `immutability`, `infra-automation`, `init-task-persistence`, `network-exposure-baseline`, `nginx-version-compat`, `performance`, `plan-path-validator`, `playwright-qa`, `post-deploy-env-diff`, `prod-readiness-probe`, `product-discovery/decision-record`, `product-discovery/hypothesis-validation`, `product-discovery/product-framing`, `project-init`, `publishing`, `receiving-code-review`, `reflecting`, `release-verify`, `requesting-code-review`, `research-workflow`, `rotation-runbook`, `seam-vs-integration-boundary`, `security`, `security-baseline`, `self-verification`, `session-handoff-replay`, `session-handoff-writer`, `stage-snapshot-writer`, `structure-review`, `structured-outputs-integration-gate`, `subagent-driven-development`, `systematic-debugging`, `tech-stack`, `test-env-verification`, `testing`, `using-git-worktrees`, `utilities`, `v-ac-axis-split`, `v-ac-feasibility`, `verification-before-completion`, `visual-maps`, `wizard`, `writing`, `writing-plans`

## Optional plugin packages

| Plugin | Default state | Categories | Assets | Availability |
|--------|---------------|------------|--------|--------------|
| `controller-continuation` | disabled | commands | 1 | conditional on enabling `controller-continuation` |
| `dr-jev-control` | disabled | productivity, scripts | 20 | conditional on enabling `dr-jev-control` |
| `dr-orchestrate` | disabled | rules, scripts | 46 | conditional on enabling `dr-orchestrate` |
| `product-discovery` | disabled | skills, templates | 19 | conditional on enabling `product-discovery` and selecting the product-discovery profile |
| `tdd-enforcement` | active | none | 0 | conditional on enabling `tdd-enforcement` |

## Template dependencies

| Consumer | Template |
|----------|----------|
| `plugins/product-discovery/skills/decision-record/strategist.product-discovery.md` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/product-discovery/product-brief.md` |
| `plugins/product-discovery/skills/hypothesis-validation/experiment-design.md` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/product-discovery/experiment-protocol.md` |
| `plugins/product-discovery/skills/product-framing/claim-quality.md` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/product-discovery/source-evidence-ledger.md` |
| `skill:product-discovery/decision-record` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/product-discovery/decision-record.md` |
| `skill:product-discovery/hypothesis-validation` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/product-discovery/experiment-protocol.md` |
| `skill:product-discovery/hypothesis-validation` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/product-discovery/hypothesis-card.md` |
| `skill:product-discovery/product-framing` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/product-discovery/opportunity-brief.md` |
| `agent:researcher` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/insights-template.md` |
| `command:dr-archive` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/archive-template.md` |
| `command:dr-compliance` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/compliance-report-template.md` |
| `command:dr-init` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/backlog-template.md` |
| `command:dr-init` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/expectations-template.md` |
| `command:dr-init` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/task-template.md` |
| `command:dr-plan` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/infra-cost-reduction-checklist.md` |
| `command:dr-plan` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/integration-checklist.md` |
| `command:dr-plan` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/security-deps-upgrade-plan.md` |
| `command:dr-plugin` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/enabled-plugins.md.template` |
| `command:dr-plugin` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/plugin.yaml.template` |
| `command:dr-prd` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/insights-template.md` |
| `command:dr-prd` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/prd-template.md` |
| `command:dr-quick` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/task-template.md` |
| `fragment:skills/datarim-system/command-and-archive-rules.md` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/project-agents-md.md` |
| `fragment:skills/datarim-system/command-and-archive-rules.md` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/project-docs-stubs.md` |
| `fragment:skills/datarim-system/task-identity-and-context.md` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/activeContext-template.md` |
| `fragment:skills/evolution/stack-agnostic-gate.md` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/docker-smoke-checklist.md` |
| `fragment:skills/human-outcome-reporting/references/datarim.md` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/human-outcome-report-template.md` |
| `fragment:skills/testing/test-value-card.md` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/test-value-card.md` |
| `fragment:skills/utilities/shell-conventions.md` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/shell-helper-template.sh` |
| `skill:compliance` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/compliance-report-template.md` |
| `skill:compliance` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/coverage-deferral-clause.md` |
| `skill:cta-format` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/cta-template.md` |
| `skill:file-sync-config` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/cli-conflict-resolver-prompt.md` |
| `skill:human-summary` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/archive-template.md` |
| `skill:human-summary` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/compliance-report-template.md` |
| `skill:infra-automation` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/infra-artifact-checklist.md` |
| `skill:infra-automation` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/infra-cost-reduction-checklist.md` |
| `skill:init-task-persistence` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/archive-template.md` |
| `skill:project-init` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/backlog-template.md` |
| `skill:project-init` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/documentation-diataxis/explanation/README.md` |
| `skill:project-init` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/documentation-diataxis/how-to/README.md` |
| `skill:project-init` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/documentation-diataxis/reference/README.md` |
| `skill:project-init` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/documentation-diataxis/tutorials/README.md` |
| `skill:project-init` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/project-agents-md.md` |
| `skill:project-init` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/project-docs-stubs.md` |
| `skill:reflecting` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/reflection-template.md` |
| `skill:research-workflow` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/insights-template.md` |
| `skill:security` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/cutover-runbook-template.md` |
| `skill:security` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/security-deps-upgrade-plan.md` |
| `skill:security-baseline` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/cloudflare-nginx-setup.sh` |
| `skill:security-baseline` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/compliance-report-template.md` |
| `skill:security-baseline` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/security-deps-upgrade-plan.md` |
| `skill:security-baseline` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/security-workflow.yml` |
| `skill:testing` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/docker-smoke-checklist.md` |
| `skill:utilities` | `${DATARIM_RUNTIME:-$HOME/.claude}/templates/shell-helper-template.sh` |

### Template assets

`${DATARIM_RUNTIME:-$HOME/.claude}/templates/SECURITY.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/acceptance-contract.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/accepted-risk.yml`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/activeContext-template.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/archive-template.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/backlog-template.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/build-rs-version.rs`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/classifier-script-template.sh`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/cli-conflict-resolver-prompt.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/cloudflare-nginx-setup.sh`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/compliance-report-template.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/coverage-deferral-clause.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/cta-template.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/customer-delivery-receipt-template.yaml`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/customer-requirements-template.yaml`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/cutover-runbook-template.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/datarim-config.yaml`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/deploy-script.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/docker-smoke-checklist.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/documentation-diataxis/explanation/README.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/documentation-diataxis/how-to/README.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/documentation-diataxis/reference/README.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/documentation-diataxis/tutorials/README.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/enabled-plugins.md.template`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/expectations-template.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/human-outcome-report-template.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/infra-artifact-checklist.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/infra-cost-reduction-checklist.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/insights-template.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/integration-checklist.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/legacy-hardware-probe-checklist.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/module.yaml`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/plugin.yaml.template`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/product-discovery/decision-record.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/product-discovery/experiment-protocol.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/product-discovery/hypothesis-card.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/product-discovery/opportunity-brief.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/product-discovery/product-brief.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/product-discovery/source-evidence-ledger.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/prd-template.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/probe-self-hosted-runner-workflow.yml`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/project-agents-md.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/project-docs-stubs.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/qa-charter.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/reflection-template.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/review-evolution-template.yaml`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/security-deps-upgrade-plan.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/security-workflow.yml`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/shell-helper-template.sh`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/task-template.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/test-value-card.md`, `${DATARIM_RUNTIME:-$HOME/.claude}/templates/version-consistency-fanout-checklist.md`
