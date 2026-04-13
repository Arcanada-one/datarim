---
name: visual-maps
description: Mermaid workflow diagrams — pipeline routing by complexity, stage process flows, agent-skill-command relationships. Load on demand for navigation and orientation.
model: sonnet
---

# Visual Maps — Workflow Diagrams

> **When to load:** When an agent needs orientation in the pipeline, wants to understand routing, or needs to visualize component relationships. Do NOT load for simple tasks where the next step is obvious.

---

## Pipeline Routing by Complexity

```mermaid
graph TD
    Init["/dr-init<br>Assess Complexity"] --> L1{"L1?"}
    Init --> L2{"L2?"}
    Init --> L3{"L3?"}
    Init --> L4{"L4?"}

    L1 -->|"Quick Fix"| Do1["/dr-do"]
    Do1 --> Reflect1["/dr-reflect"]
    Reflect1 --> Archive1["/dr-archive"]

    L2 -->|"Enhancement"| PRD2["[/dr-prd]"]
    PRD2 --> Plan2["/dr-plan"]
    Plan2 --> Do2["/dr-do"]
    Do2 --> QA2["[/dr-qa]"]
    QA2 --> Reflect2["/dr-reflect"]
    Reflect2 --> Archive2["/dr-archive"]

    L3 -->|"Feature"| PRD3["/dr-prd"]
    PRD3 --> Plan3["/dr-plan"]
    Plan3 --> Design3["/dr-design"]
    Design3 --> Do3["/dr-do"]
    Do3 --> QA3["/dr-qa"]
    QA3 --> Compliance3["[/dr-compliance]"]
    Compliance3 --> Reflect3["/dr-reflect"]
    Reflect3 --> Archive3["/dr-archive"]

    L4 -->|"Major"| PRD4["/dr-prd"]
    PRD4 --> Plan4["/dr-plan"]
    Plan4 --> Design4["/dr-design"]
    Design4 --> Do4["/dr-do<br>(phased)"]
    Do4 --> QA4["/dr-qa"]
    QA4 --> Comp4["/dr-compliance"]
    Comp4 --> Reflect4["/dr-reflect"]
    Reflect4 --> Archive4["/dr-archive"]

    style Init fill:#4da6ff,stroke:#0066cc,color:white
    style L1 fill:#10b981,stroke:#059669,color:white
    style L2 fill:#f59e0b,stroke:#d97706,color:white
    style L3 fill:#f97316,stroke:#ea580c,color:white
    style L4 fill:#ef4444,stroke:#dc2626,color:white
```

Brackets `[]` = optional at that level.

---

## Stage Process Flows

### /dr-init
```mermaid
graph LR
    A["Read task"] --> B["Check backlog"]
    B --> C["Assess complexity"]
    C --> D{"datarim/ exists?"}
    D -->|No| E["Create datarim/"]
    D -->|Yes| F["Update tasks.md"]
    E --> F
    F --> G["Route by level"]
```

### /dr-prd
```mermaid
graph LR
    A["Read context"] --> B["Discovery interview"]
    B --> C["Generate 3+ approaches"]
    C --> D["User consultation"]
    D --> E["Write PRD"]
```

### /dr-plan
```mermaid
graph LR
    A["Read PRD + context"] --> B{"L3-4?"}
    B -->|Yes| C["Strategist gate"]
    B -->|No| D["Component breakdown"]
    C --> D
    D --> E["Interface + security design"]
    E --> F["Implementation steps"]
    F --> G["Write tasks.md"]
```

### /dr-design
```mermaid
graph LR
    A["Identify design type"] --> B["Define problem"]
    B --> C["Explore 3+ options"]
    C --> D["Analyze tradeoffs"]
    D --> E{"L3-4?"}
    E -->|Yes| F["Consilium panel"]
    E -->|No| G["Make decision"]
    F --> G
    G --> H["Write creative doc"]
```

### /dr-do
```mermaid
graph LR
    A["Read plan"] --> B{"L3-4 code?"}
    B -->|Yes| C["Pre-flight check"]
    B -->|No| D["Implement iteratively"]
    C --> D
    D --> E["Test"]
    E --> F["Update progress"]
```

### /dr-qa
```mermaid
graph LR
    A["Layer 1: PRD alignment"] --> B["Layer 2: Design conformance"]
    B --> C["Layer 3: Plan completeness"]
    C --> D["Layer 4: Code/content quality"]
    D --> E{"Verdict"}
    E -->|PASS| F["/dr-compliance or /dr-reflect"]
    E -->|FAIL| G["Back to /dr-do"]
```

### /dr-compliance
```mermaid
graph LR
    A["Detect task type"] --> B{"Type?"}
    B -->|Code| C["Lint, tests, coverage, CI/CD"]
    B -->|Docs| D["Completeness, consistency, refs"]
    B -->|Research| E["Methods, citations, coherence"]
    B -->|Content| F["Factcheck, humanize, SEO"]
    B -->|Legal| G["Jurisdiction, terms, numbering"]
    B -->|Infra| H["Config, secrets, rollback"]
    C & D & E & F & G & H --> I["Write report"]
```

### /dr-reflect
```mermaid
graph LR
    A["Review vs plan"] --> B["What went well"]
    B --> C["Challenges"]
    C --> D["Lessons learned"]
    D --> E["Evolution proposals"]
    E --> F["Health check"]
```

### /dr-archive
```mermaid
graph TD
    A["Read activeContext + tasks.md"] --> B{"Cancel or Complete?"}
    B -->|Complete| C["Create archive doc"]
    B -->|Cancel| H["Skip archive doc"]
    C --> D{"From backlog?"}
    H --> D
    D -->|Yes| E["Move task ID entry to backlog-archive"]
    D -->|No| F["Skip backlog update"]
    E --> G["Add follow-up tasks to backlog"]
    F --> G
    G --> I["Reset activeContext + tasks.md"]
```

---

## Content Command Flows

### /dr-write
```mermaid
graph LR
    A["Read task + context"] --> B["Research sources"]
    B --> C["Create outline"]
    C --> D["Draft section by section"]
    D --> E["Self-review"]
    E --> F["Mark for editorial"]
```

### /dr-edit
```mermaid
graph LR
    A["Read content"] --> B["Extract claims"]
    B --> C["Fact-check (CoVe)"]
    C --> D["AI pattern scan"]
    D --> E["Style + structure pass"]
    E --> F["Report changes"]
```

### /factcheck (standalone)
```mermaid
graph LR
    A["Read text"] --> B["Extract claims"]
    B --> C["Classify importance"]
    C --> D["Verify via sources"]
    D --> E["Verdicts + corrections"]
```

### /humanize (standalone)
```mermaid
graph LR
    A["Read text"] --> B["Pass 1: Vocabulary + formatting"]
    B --> C["Pass 2: Structure + rhythm"]
    C --> D["Pass 3: Anti-AI audit"]
```

---

## Framework Management Flows

### /dr-addskill
```mermaid
graph LR
    A["Understand request"] --> B["Research best practices"]
    B --> C["Audit existing framework"]
    C --> D["Determine scope"]
    D --> E["Design + generate"]
    E --> F["Present for approval"]
```

### /dr-optimize
```mermaid
graph LR
    A["Full audit"] --> B["Build dependency graph"]
    B --> C["Detect issues"]
    C --> D["Generate proposals"]
    D --> E["Present for approval"]
    E --> F["Apply + sync docs"]
```

### /dr-dream
```mermaid
graph LR
    A{"Mode?"} -->|Full| B["Ingest new items"]
    A -->|Lint| C["Health check"]
    A -->|Index| D["Rebuild index"]
    B --> C
    C --> E["Consolidate + cross-ref"]
    D --> F["Update index.md"]
    E --> F
```

---

## Utility Command Flows

### /dr-status
```mermaid
graph LR
    A["Read activeContext"] --> B["Read tasks.md"]
    B --> C["Read backlog.md"]
    C --> D["Display summary"]
```

### /dr-continue
```mermaid
graph LR
    A["Read activeContext"] --> B["Determine current phase"]
    B --> C["Route to stage command"]
```

---

## Command — Agent Relationships

```mermaid
graph TD
    subgraph "Pipeline Commands"
        init["/dr-init"]
        prd["/dr-prd"]
        plan["/dr-plan"]
        design["/dr-design"]
        do["/dr-do"]
        qa["/dr-qa"]
        compliance["/dr-compliance"]
        reflect["/dr-reflect"]
        archive["/dr-archive"]
    end

    subgraph "Content Commands"
        write["/dr-write"]
        edit["/dr-edit"]
        factcheck_cmd["/factcheck"]
        humanize_cmd["/humanize"]
    end

    subgraph "Management Commands"
        addskill["/dr-addskill"]
        optimize["/dr-optimize"]
        dream_cmd["/dr-dream"]
    end

    subgraph "Utility Commands"
        status["/dr-status"]
        continue_cmd["/dr-continue"]
        help["/dr-help"]
    end

    subgraph "Agents"
        planner["planner"]
        architect["architect"]
        developer["developer"]
        reviewer["reviewer"]
        comp_agent["compliance"]
        strategist["strategist"]
        writer_agent["writer"]
        editor_agent["editor"]
        skill_creator["skill-creator"]
        optimizer_agent["optimizer"]
        librarian["librarian"]
        security_agent["security"]
        sre_agent["sre"]
        devops_agent["devops"]
        code_simp["code-simplifier"]
    end

    init --> planner
    prd --> architect
    plan --> planner
    plan -.->|"L3-4"| strategist
    design --> architect
    design -.->|"L3-4"| security_agent
    design -.->|"L3-4"| sre_agent
    do --> developer
    do -.-> devops_agent
    qa --> reviewer
    qa -.-> security_agent
    compliance --> comp_agent
    compliance -.-> code_simp
    reflect --> reviewer
    archive --> planner
    write --> writer_agent
    edit --> editor_agent
    factcheck_cmd --> editor_agent
    humanize_cmd --> editor_agent
    addskill --> skill_creator
    optimize --> optimizer_agent
    dream_cmd --> librarian
```

---

## Agent — Skill Dependencies

```mermaid
graph LR
    subgraph "Agents"
        planner["planner"]
        architect["architect"]
        developer["developer"]
        reviewer["reviewer"]
        comp_agent["compliance"]
        writer_agent["writer"]
        editor_agent["editor"]
        skill_creator["skill-creator"]
        optimizer_agent["optimizer"]
        librarian["librarian"]
        strategist["strategist"]
        devops_agent["devops"]
        sre_agent["sre"]
        security_agent["security"]
    end

    subgraph "Skills"
        sys["datarim-system"]
        aiq["ai-quality"]
        sec["security"]
        test["testing"]
        perf["performance"]
        tech["tech-stack"]
        cons["consilium"]
        disc["discovery"]
        evo["evolution"]
        writ["writing"]
        drm["dream"]
        comp_sk["compliance"]
        fc["factcheck"]
        hum["humanize"]
        seo["seo-launch"]
        mkt["marketing"]
        util["utilities"]
        vmap["visual-maps"]
    end

    planner --> sys & aiq & tech
    architect --> sys & tech & perf & sec & cons
    developer --> sys & aiq & test
    reviewer --> sys & sec & test
    comp_agent --> sys & comp_sk
    writer_agent --> sys & writ & fc
    editor_agent --> sys & fc & hum & writ
    skill_creator --> sys & evo & writ
    optimizer_agent --> sys & evo
    librarian --> sys & drm
    strategist --> sys
    devops_agent --> sys & tech & sec
    sre_agent --> sys & perf & sec
    security_agent --> sys & sec & comp_sk
```

---

## Consilium Panel Compositions

```mermaid
graph TD
    subgraph "Architecture Panel"
        A1["architect"] --- A2["developer"]
        A2 --- A3["security"]
        A3 --- A4["sre"]
    end

    subgraph "Code Design Panel"
        C1["architect"] --- C2["developer"]
        C2 --- C3["reviewer"]
    end

    subgraph "Production Readiness"
        P1["sre"] --- P2["security"]
        P2 --- P3["devops"]
        P3 --- P4["reviewer"]
    end

    subgraph "Content Panel"
        W1["writer"] --- W2["editor"]
    end

    subgraph "Knowledge Panel"
        K1["librarian"] --- K2["architect"]
    end
```

---

## Quality Rules by Stage

See `ai-quality.md` § Stage-Rule Mapping for which of the 15 rules apply at each pipeline stage.

| Stage | Key Rules | Focus |
|-------|-----------|-------|
| /dr-plan | #1, #5, #6, #7, #11 | Decomposition, scope, boundaries |
| /dr-design | #6, #7, #9, #13 | Design quality, cognitive load |
| /dr-do | #2, #3, #8, #9 | TDD, method size, iteration |
| /dr-qa | #5, #10 | DoD verification, focused review |
| /dr-reflect | #8, #10 | Process verification |
