# How-to Guides — Problem-Solving Documentation

How-to guides are task-oriented documentation, where the reader knows exactly which problem they want to solve. The content consists of precise instructions for reaching a specific goal: a sequence of steps, configurations, commands. The intent is to give a working solution to a known problem without unnecessary explanations. The reader arrives with the question "how do I do X?" and expects a direct answer.

## When to write here

- Deployment recipes — deploying a service, configuring the environment, running it in production
- Testing/CI configuration steps — setting up pipelines, adding test scenarios, integrating linters
- Troubleshooting fixes for typical errors — solutions for common errors, logs, stack traces
- Debugging procedures — debugging techniques, enabling verbose mode, analysing dumps

## When NOT to write here

- → First-time learning experience for beginners → `tutorials/`
- → API/CLI/config lookup → `reference/`
- → Conceptual background or why-decisions → `explanation/`

## Naming convention

- Kebab-case `.md` filename: descriptive task-titled, e.g., `deploy-to-production.md`, `fix-database-connection.md`