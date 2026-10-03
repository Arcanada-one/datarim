---
id: TUNE-0574
title: Close task-ID provenance leaks across framework, site, and fleet
status: archived
completed_date: 2026-08-09
complexity: L4
type: framework
project: Datarim
related: []
archive_doc: documentation/archive/framework/archive-TUNE-0574.md
verification_outcome:
  caught_by_verify: 0
  missed_by_verify: 0
  false_positive: 0
  n_a: true
  dogfood_window: "2026-W32-task-id-gate"
---

<!-- allow-non-ascii-block: canonical Russian operator-facing archive sections required by the archive template -->

# Архив: TUNE-0574 — устранение утечек служебных номеров задач

## Начальная задача

Автономно устранить обходы правила происхождения служебных инструкций, доставить изменения в основной набор правил и открытый сайт, выпустить новую версию, выровнять действующие установки и закрыть все доказательства.

## Как решили

- **«Прочитать полный бриф и выполнить его от начала до конца без вопросов».** выполнено. Все обычные развилки решены автономно, а причины решений записаны в материалах задачи.
- **«Работать до полного выполнения определения готовности».** выполнено. Исправление, сайт, выпуск, действующие установки, повторная проверка и архив подтверждены раздельными доказательствами.
- **«Закрыть все известные обходы механизма» (уточнение брифа).** выполнено. Проверка теперь закрывается при ошибках разбора, обхода файлов, запуска сканера и сравнения изменений.
- **«Классифицировать все совпадения и оставить только примеры» (уточнение брифа).** выполнено. Исторические ссылки удалены из рабочих инструкций, а допустимые образцы оставлены только в узких корректных блоках.
- **«Сохранить доказательство ошибки старой версии» (уточнение брифа).** выполнено. Старая версия дала двадцать четыре сбоя из пятидесяти проверок, новая прошла все пятьдесят три.
- **«Усилить правило открытого сайта и доставить его через проверяемый выпуск» (уточнение брифа).** выполнено. Защищённые изменения объединены, проверены и развёрнуты; чтение результата подтвердило четыреста сорок восемь маршрутов.
- **«Доказать неизменяемую доставку основной версии» (уточнение брифа).** выполнено. Защищённое объединение, метка выпуска, пять файлов выпуска, две подписи и подтверждение сборки связаны с одной ревизией.
- **«Проверить смысловой признак на всех действующих установках» (уточнение брифа).** выполнено. Три названные поверхности установок показывают одну версию и ревизию, а отдельно защищённая копия не изменялась.
- **«Завершить полную проверку и архивирование» (уточнение брифа).** выполнено. Полный набор испытаний, независимые проверки, повторная оценка, отчёт о соответствии, рефлексия, архив и тонкие индексы согласованы.

## Артефакты задачи

- Исправлены основной сканер, его набор испытаний и десять явных вызовов в проверках хранилища.
- Согласованы `CLAUDE.md`, договор проверки, управляемые инструкции, документация и смысловой признак установленного обработчика.
- Открытый сайт получил отдельное строгое правило без исключающего блока и был развёрнут из защищённой основной ветки.
- Выпущена версия `2.65.0`; отдельная запись сохраняет основания и время выпуска.
- Итоговые доказательства находятся в `datarim/qa/qa-report-TUNE-0574.md`, `datarim/reports/compliance-report-TUNE-0574.md` и `datarim/reflection/reflection-TUNE-0574.md`.

## Следующие шаги

всё закрыто

---

## Дополнительно для аудита

### verification_outcome

<!-- gate:literal -->
- `caught_by_verify`: 0
- `missed_by_verify`: 0
- `false_positive`: 0
- `n_a`: true — ручная команда `/dr-verify` не запускалась; независимые проверки и обычные стадии качества учитываются отдельно.
- `dogfood_window`: `2026-W32-task-id-gate`
<!-- /gate:literal -->

### Acceptance Criteria

<!-- gate:literal -->
| AC | Status | Evidence |
|---|---|---|
| AC-1: widened fail-closed gate | pass | 53/53 focused tests; ten canonical target calls exit 0 |
| AC-2: governed corpus clean | pass | zero real provenance stamps outside exact history surfaces |
| AC-3: contract and Rule 8 parity | pass | implementation, contract, root rule, and CI caller list agree |
| AC-4: meaningful RED/GREEN | pass | old gate exit 1 with 24/50 failures; fixed gate exit 0 with 53/53 passes |
| AC-5: complete verification | pass | 3257 full tests, 91 cross-gate tests, body, references, portability, security, and validation checks pass |
| AC-6: site parity and deployment | pass | 448 routes; protected verification and deployment runs succeeded |
| AC-7: protected framework delivery | pass | PR 352 merged; resulting main `c0e283eb22b9b052197f93f96ab165e833b9e17f`; exact-main workflows pass |
| AC-8: release publication | pass | `v2.65.0`; run `31322665918` attempt 2; five assets; checksum, signatures, attestation, SBOM, and version pass |
| AC-9: runtime convergence | pass | three current named runtime surfaces match release head and marker; gated checkout unchanged |
<!-- /gate:literal -->

### Lessons Learned

- Проверка, которая может скрыть собственную ошибку запуска, должна иметь отдельное испытание отказа производителя данных.
- Содержимое файла и его режим исполнения являются разными свойствами доставки.
- Будущие этапы нельзя объявлять выполненными заранее; итоговая повторная проверка должна связывать каждое утверждение с уже существующим доказательством.

### Operator Handoff

Первичный журнал постановки отсутствовал в полученной основной ветке. Полный
управляющий бриф был прочитан из исходного файла, а его требования сохранены в
описании задачи, документе требований, ожиданиях, итоговых отчётах и этом архиве.
Действий оператора не требуется.

<!-- /allow-non-ascii-block -->

### Related

- Parent PRD: `datarim/prd/PRD-TUNE-0574.md`
- Plan: archived by this closure
- Reflection: `datarim/reflection/reflection-TUNE-0574.md`
- Follow-ups: none
