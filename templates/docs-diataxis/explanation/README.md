# Explanation — Understanding-Oriented Documentation

Документация категории *Explanation* предназначена для формирования глубокого понимания системы. Это аналитический и рефлексивный жанр, где читатель ищет ментальные модели и контекстную глубину, а не пошаговые инструкции. Цель — ответить на вопрос «почему»: почему компонент спроектирован так, а не иначе, какие принципы лежат в основе его работы и как он вписывается в общую архитектуру. Содержание дискурсивно, допускает отступления, сравнения и исторический экскурс, помогая читателю выстроить внутреннюю когнитивную карту.

## When to write here

- Architectural overview and rationale — обоснование архитектурных решений и связей между модулями.
- Design decisions with tradeoffs — описание принятых проектных решений и их компромиссов (time vs. memory, flexibility vs. simplicity).
- Conceptual background — фундаментальные концепции, необходимые для понимания домена (например, event sourcing, eventual consistency).
- Comparisons of alternatives — сравнение подходов, библиотек или паттернов с объяснением выбора.
- Evolution and history of a component — как и почему компонент менялся со временем, какие уроки были извлечены.

## When NOT to write here

- → First-time learning end-to-end: помещайте в категорию *tutorials/*.
- → Task recipe (как выполнить конкретную задачу): помещайте в категорию *how-to/*.
- → Factual lookup (API reference, configuration keys): помещайте в категорию *reference/*.
- → Debugging or troubleshooting of specific errors: используйте *how-to/* или отдельный раздел *troubleshooting*.

## Naming convention

- Файлы именуются в kebab-case с расширением `.md`, описывая ключевое понятие (например, `event-sourcing-rationale.md`, `caching-strategy-tradeoffs.md`).