# Visual Maps — Stage Process Flows

## /dr-init

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

## /dr-prd

```mermaid
graph LR
    A["Read context"] --> R{"L2+?"}
    R -->|Yes| B["Research (Phase 1.3)"]
    R -->|No| C["Discovery interview"]
    B --> C
    C --> D["Generate 3+ approaches"]
    D --> E["User consultation"]
    E --> F["Write PRD"]
```

## /dr-plan

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

## /dr-design

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

## /dr-do

```mermaid
graph LR
    A["Read plan"] --> B{"L3-4 code?"}
    B -->|Yes| C["Pre-flight check"]
    B -->|No| D["Implement iteratively"]
    C --> D
    D --> E["Test"]
    E -->|"gap?"| G["Researcher subagent"]
    G --> D
    E -->|"pass"| F["Update progress"]
```

## /dr-qa

```mermaid
graph LR
    A["Layer 1: PRD alignment"] --> B["Layer 2: Design conformance"]
    B --> C["Layer 3: Plan completeness"]
    C --> D["Layer 4: Code/content quality"]
    D --> E{"Verdict"}
    E -->|"PASS L3-4"| F["/dr-compliance"]
    E -->|"PASS L1-2"| F2["/dr-archive"]
    E -->|"FAIL L1"| G1["Back to /dr-prd"]
    E -->|"FAIL L2"| G2["Back to /dr-design"]
    E -->|"FAIL L3"| G3["Back to /dr-plan"]
    E -->|"FAIL L4"| G4["Back to /dr-do"]
```

## /dr-compliance

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

## /dr-archive

Reflection runs as **Step 0.5** (mandatory, non-skippable) inside `/dr-archive` via the `reflecting` skill. Archive cannot proceed if reflection fails or Class A proposals are rejected.

```mermaid
graph TD
    A["Step 0: Pre-archive clean-git check"] --> B["Step 0.5: REFLECT (reflecting skill)"]
    B --> B1["Review vs plan"]
    B1 --> B2["Lessons learned"]
    B2 --> B3["Evolution proposals (Class A/B gate)"]
    B3 --> B4["Health check"]
    B4 --> B5["Follow-up task list"]
    B5 --> C{"Cancel or Complete?"}
    C -->|Complete| D["Step 1: Determine area + create archive doc"]
    C -->|Cancel| H["Skip archive doc"]
    D --> E{"From backlog?"}
    H --> E
    E -->|Yes| F["Step 3: Move task ID entry to backlog-archive"]
    E -->|No| G["Skip backlog update"]
    F --> K["Step 4: Add follow-up tasks to backlog"]
    G --> K
    K --> L["Steps 5-7: Update archived-tasks table + reset activeContext/tasks.md"]
```
