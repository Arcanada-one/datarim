# Reference — Information-Oriented Documentation

Reference-документация относится к information-oriented типу документации. Она предназначена для точного фактического поиска: читатель уже знает, что ищет, и нуждается в достоверных, лаконичных и полных сведениях. Содержимое строится по структурированному принципу — таблицы, списки, сигнатуры, схемы — без пояснений и учебных примеров. Основная цель: дать быстрый доступ к конкретному параметру, типу, значению или ключу в максимально сжатой форме.

## When to write here

- API документация: endpoint, method, request/response schema
- CLI commands: флаги, аргументы, сигнатуры, exit codes
- Configuration schema: ключи, допустимые значения, defaults
- Glossary: термины, сокращения, определения
- Data type catalogue: enum values, field types, constraints
- System map: architecture diagram, port mapping, service registry

## When NOT to write here

- Передаёт первое знакомство и end-to-end ориентиры → перенесите в **tutorials/**
- Предлагает рецепт для решения конкретной задачи → используйте **how-to/**
- Объясняет мотивацию выбора или архитектурные решения → напишите **explanation/**

## Naming convention

- Все файлы используют kebab-case, расширение `.md`
- Имя должно быть описательным и предметно-ориентированным: `api-endpoints.md`, `config-schema.md`, `glossary.md`