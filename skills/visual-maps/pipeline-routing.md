# Visual Maps — Pipeline Routing by Complexity

```mermaid
graph TD
    Init["/dr-init<br>Assess Complexity"] --> L1{"L1?"}
    Init --> L2{"L2?"}
    Init --> L3{"L3?"}
    Init --> L4{"L4?"}

    L1 -->|"Quick Fix"| Do1["/dr-do"]
    Do1 --> Archive1["/dr-archive<br>(Step 0.5: reflect)"]

    L2 -->|"Enhancement"| PRD2["[/dr-prd<br>(incl. research)]"]
    PRD2 --> Plan2["/dr-plan"]
    Plan2 --> Do2["/dr-do"]
    Do2 --> QA2["[/dr-qa]"]
    QA2 --> Archive2["/dr-archive<br>(Step 0.5: reflect)"]

    L3 -->|"Feature"| PRD3["/dr-prd<br>(incl. research)"]
    PRD3 --> Plan3["/dr-plan"]
    Plan3 --> Design3["/dr-design"]
    Design3 --> Do3["/dr-do"]
    Do3 --> QA3["/dr-qa"]
    QA3 --> Compliance3["/dr-compliance"]
    Compliance3 --> Archive3["/dr-archive<br>(Step 0.5: reflect)"]

    L4 -->|"Major"| PRD4["/dr-prd<br>(incl. research)"]
    PRD4 --> Plan4["/dr-plan"]
    Plan4 --> Design4["/dr-design"]
    Design4 --> Do4["/dr-do<br>(phased)"]
    Do4 --> QA4["/dr-qa"]
    QA4 --> Comp4["/dr-compliance"]
    Comp4 --> Archive4["/dr-archive<br>(Step 0.5: reflect)"]

    classDef operatorOnly fill:#7c2d12,stroke:#ff6b35,stroke-width:3px,color:white
    class Init,Archive1,Archive2,Archive3,Archive4 operatorOnly

    style L1 fill:#10b981,stroke:#059669,color:white
    style L2 fill:#f59e0b,stroke:#d97706,color:white
    style L3 fill:#f97316,stroke:#ea580c,color:white
    style L4 fill:#ef4444,stroke:#dc2626,color:white
```

Brackets `[]` indicate stages that are conditional at that complexity level. `/dr-archive` always runs **Step 0.5 reflection** internally (non-skippable, mandatory since v1.10.0); this is not shown as a separate pipeline node because it cannot be skipped.

**Node colour legend:** the dark-orange-outlined nodes (`/dr-init`, `/dr-archive`) are **operator-only** commands — their frontmatter carries `disable-model-invocation: true` and they are intentionally invisible to the Skill tool. Agents must surface them as slash-CTAs for the operator and MUST NOT attempt to invoke them via Skill or via a subagent dispatched to do the work manually. See `skills/cta-format.md` § Operator-only commands.

## CTA Decision Points (v1.16.0)

Every transition between stages MUST emit a canonical CTA block per `$HOME/.claude/skills/cta-format.md`. Diagram representation:

<!-- gate:history-allowed -->
```mermaid
graph LR
    Stage["Stage finished<br>(e.g. /dr-plan)"] --> CTA["CTA block<br>(cta-format.md)"]
    CTA -->|"primary CTA"| NextStage["Next stage<br>(e.g. /dr-design TUNE-0032)"]
    CTA -->|"alternative"| Alt["Alternative<br>(e.g. /dr-do TUNE-0032)"]
    CTA -->|"escape"| Status["/dr-status"]

    style CTA fill:#fbbf24,stroke:#d97706,color:#1f2937
    style NextStage fill:#10b981,stroke:#059669,color:white
```
<!-- /gate:history-allowed -->

The CTA block always includes:
1. Resolved task ID
2. ≤5 numbered options (sweet spot 3)
3. Exactly one `**рекомендуется**` primary marker
4. `---` HR wrapping (top + bottom)
5. `**Другие активные задачи:**` Variant B menu when >1 active tasks

### Failure Routing Decision Point

When `/dr-qa` returns BLOCKED or `/dr-compliance` returns NON-COMPLIANT, the FAIL-Routing CTA variant routes back to the earliest failed layer:

```mermaid
graph LR
    Fail["/dr-qa BLOCKED<br>or<br>/dr-compliance NON-COMPLIANT"] --> CtaFail["FAIL-Routing CTA<br>(cta-format.md § FAIL-Routing)"]
    CtaFail -->|"Layer 1"| L1return["/dr-prd {ID}"]
    CtaFail -->|"Layer 2"| L2return["/dr-design {ID}"]
    CtaFail -->|"Layer 3"| L3return["/dr-plan {ID}"]
    CtaFail -->|"Layer 4"| L4return["/dr-do {ID}"]
    CtaFail -->|"3 same-layer fails"| Esc["Эскалация<br>to user"]

    style CtaFail fill:#ef4444,stroke:#dc2626,color:white
    style Esc fill:#7c2d12,stroke:#451a03,color:white
```

Source: prior incident — unified CTA spec, v1.16.0.

## Artifact Flow Across the Pipeline (v2.8.0)

```mermaid
graph LR
    Init["/dr-init"] --> InitTask[("init-task<br>(verbatim brief)")]
    InitTask --> PRD["/dr-prd"]
    PRD --> Expect[("expectations<br>(operator wishlist)")]
    Expect --> Plan["/dr-plan"]
    Plan --> Do["/dr-do"]
    Do --> QA["/dr-qa"]
    QA --> Playwright[("playwright-run<br>(browser pass)")]
    Playwright --> Compliance["/dr-compliance"]
    Compliance --> Archive["/dr-archive"]

    style InitTask fill:#0ea5e9,stroke:#0369a1,color:white
    style Expect fill:#0ea5e9,stroke:#0369a1,color:white
    style Playwright fill:#0ea5e9,stroke:#0369a1,color:white
    style QA fill:#fbbf24,stroke:#d97706,color:#1f2937
```

Three artefact nodes were introduced in v2.8.0:

- **`init-task`** — `datarim/tasks/{TASK-ID}-init-task.md`. Verbatim operator brief captured at `/dr-init`; appended (never overwritten) by the operator across the lifecycle. Read mandatorily by every pipeline command.
- **`expectations`** — `datarim/tasks/{TASK-ID}-expectations.md`. Operator-readable wishlist of «what to verify after the work is done». Written at `/dr-prd` (or `/dr-plan` for L2 without PRD). Verified at `/dr-qa` and `/dr-compliance` via `dev-tools/check-expectations-checklist.sh --verify`.
- **`playwright-run`** — `datarim/qa/playwright-{TASK-ID}/run-<ISO-ts>/`. Browser pass artefacts (screenshot + trace + summary) written by `/dr-qa` Layer 4f when the task changes any frontend markup. Skipped silently for non-frontend tasks.

Solid arrows = control flow. Brackets `(())` mark the new operator-facing artefacts; the orange-outlined `/dr-qa` node is the gate that consumes all three (init-task as input, expectations as the Layer 3b verifier, playwright-run as the Layer 4f side-effect).
