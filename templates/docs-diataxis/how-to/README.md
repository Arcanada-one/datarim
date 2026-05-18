# How-to Guides — Problem-Solving Documentation

How-to guides are task-oriented документация, где читатель точно знает, какую проблему хочет решить. Содержание — это точные инструкции для достижения конкретной цели: последовательность шагов, конфигурации, команды. Интент — дать рабочее решение известной проблемы без лишних объяснений. Читатель приходит с вопросом «как сделать X?» и ожидает прямой ответ.

## When to write here

- Deployment recipes — развертывание сервиса, настройка окружения, запуск в production
- Testing/CI configuration steps — настройка пайплайнов, добавление тестовых сценариев, интеграция линтеров
- Troubleshooting fixes for typical errors — решения для частых ошибок, логов, stack trace
- Debugging procedures — методики отладки, включение verbose mode, анализ дампов

## When NOT to write here

- → First-time learning experience for beginners → `tutorials/`
- → API/CLI/config lookup → `reference/`
- → Conceptual background or why-decisions → `explanation/`

## Naming convention

- Kebab-case `.md` filename: descriptive task-titled, e.g., `deploy-to-production.md`, `fix-database-connection.md`