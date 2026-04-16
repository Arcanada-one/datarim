# Visual Maps — Content and Management Flows

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

### /factcheck

```mermaid
graph LR
    A["Read text"] --> B["Extract claims"]
    B --> C["Classify importance"]
    C --> D["Verify via sources"]
    D --> E["Verdicts + corrections"]
```

### /humanize

```mermaid
graph LR
    A["Read text"] --> B["Pass 1: Vocabulary + formatting"]
    B --> C["Pass 2: Structure + rhythm"]
    C --> D["Pass 3: Anti-AI audit"]
```

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
