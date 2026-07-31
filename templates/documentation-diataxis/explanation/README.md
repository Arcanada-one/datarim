# Explanation — Understanding-Oriented Documentation

Documentation in the *Explanation* category exists to build a deep understanding of the system. It is an analytical, reflective genre in which the reader is looking for mental models and contextual depth rather than step-by-step instructions. Its purpose is to answer the question "why": why a component is designed this way and not another, which principles underpin how it works, and how it fits into the overall architecture. The content is discursive; it allows digressions, comparisons, and historical background, helping the reader build an internal cognitive map.

## When to write here

- Architectural overview and rationale — justification of architectural decisions and of the relationships between modules.
- Design decisions with tradeoffs — a description of the design decisions taken and their compromises (time vs. memory, flexibility vs. simplicity).
- Conceptual background — the fundamental concepts needed to understand the domain (for example, event sourcing, eventual consistency).
- Comparisons of alternatives — a comparison of approaches, libraries, or patterns with an explanation of the choice made.
- Evolution and history of a component — how and why a component changed over time, and which lessons were learned.

## When NOT to write here

- → First-time learning end-to-end: put it in the *tutorials/* category.
- → Task recipe (how to carry out a specific task): put it in the *how-to/* category.
- → Factual lookup (API reference, configuration keys): put it in the *reference/* category.
- → Debugging or troubleshooting of specific errors: use *how-to/* or a separate *troubleshooting* section.

## Naming convention

- Files are named in kebab-case with a `.md` extension, describing the key concept (for example, `event-sourcing-rationale.md`, `caching-strategy-tradeoffs.md`).