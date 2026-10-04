# Reference — Information-Oriented Documentation

Reference documentation belongs to the information-oriented type of documentation. It is intended for precise factual lookup: the reader already knows what they are looking for and needs trustworthy, concise, and complete information. The content is built on a structured principle — tables, lists, signatures, schemas — without explanations or teaching examples. The primary goal is to give fast access to a specific parameter, type, value, or key in the most compact form possible.

## When to write here

- API documentation: endpoint, method, request/response schema
- CLI commands: flags, arguments, signatures, exit codes
- Configuration schema: keys, permitted values, defaults
- Glossary: terms, abbreviations, definitions
- Data type catalogue: enum values, field types, constraints
- System map: architecture diagram, port mapping, service registry

## When NOT to write here

- Conveys a first encounter and end-to-end orientation → move it to **tutorials/**
- Offers a recipe for solving a specific task → use **how-to/**
- Explains the motivation behind a choice or architectural decisions → write **explanation/**

## Naming convention

- All files use kebab-case with a `.md` extension
- The name should be descriptive and subject-oriented: `api-endpoints.md`, `config-schema.md`, `glossary.md`