# Claude Code + Jev + Datarim: установка и тестирование

## Что это

`dr-jev-control` — слой System One перед Claude Code. Он не заменяет Claude и не пытается использовать Jev как reasoning-модель. Jev делает быстрые типизированные решения (`Choice`, `Score`, `Noul`), а Datarim и Claude выполняют работу.

Архитектура:

```text
Task / prompt
   │
   ├─ local shortlist ─ skills / agents / commands / templates
   │
   ▼
Jev decision bundle
   ├─ Claude tier: haiku / sonnet / opus
   ├─ complexity
   ├─ needs System-2 reasoning
   ├─ Datarim skill / agent / command / template
   ├─ production risk
   ├─ validation need
   └─ parallelization hint
   │
   ▼
Claude Code + Datarim
   │
   ├─ PreToolUse Jev risk advisory
   ├─ existing Datarim deterministic safety rules
   └─ tests / QA / archive / reflection
```

## Почему это экономит токены

1. В initial launch wrapper выбирает самый дешёвый подходящий Claude tier.
2. На каждом prompt полный каталог Datarim не отправляется Jev: сначала локальный lexical shortlist, затем Jev выбирает из короткого списка.
3. Claude получает только компактную routing-рекомендацию, а не полный набор skill/agent/template текстов.
4. Jev-вопросы для model/complexity/risk/validation/components отправляются одним batched API request.
5. PostToolUse не вызывает Jev после каждого чтения/записи: это специально сделано, чтобы control plane сам не стал источником лишней стоимости и latency.

## Требования

- macOS/Linux (на Windows — WSL).
- Python 3.9+.
- Claude Code установлен и авторизован.
- TypeSafe API key с доступом к System One/Jev.
- `TYPESAFE_API_KEY` должен быть только в environment/keychain/secret manager; не добавляйте его в Datarim или git.

Проверка Claude Code:

```bash
claude doctor
```

## Быстрая установка

Из корня Datarim:

```bash
python3 plugins/dr-jev-control/scripts/install.py --scope user
export TYPESAFE_API_KEY='YOUR_KEY_HERE'
export PATH="$HOME/.local/bin:$PATH"
dr-jev doctor
```

Для zsh сохраните только ссылки на переменные/secret manager в `~/.zshrc`. Сам ключ предпочтительно получать из macOS Keychain, 1Password CLI, Vault или Custodium, а не хранить открытым текстом.

### Только для одного проекта

```bash
python3 plugins/dr-jev-control/scripts/install.py --scope project --project /path/to/project
```

Это изменяет `.claude/settings.local.json` проекта и не затрагивает пользовательский `~/.claude/settings.json`.

Installer **merge-ит** hooks и не удаляет существующие hooks. Перед первым использованием всё равно рекомендуется сделать резервную копию settings.

## Первый запуск

Посмотреть решение Jev без Claude:

```bash
dr-jev route "Fix the flaky PostgreSQL integration tests and find the root cause"
```

Запустить Claude Code с автоматическим выбором initial model tier:

```bash
dr-claude-jev "Fix the flaky PostgreSQL integration tests and find the root cause"
```

Обычная интерактивная сессия:

```bash
dr-claude-jev
```

В интерактивной сессии `UserPromptSubmit` hook делает routing каждого нового пользовательского prompt и добавляет Claude компактную рекомендацию. Важное ограничение Claude Code: hook не переключает модель уже запущенной основной сессии. Для первого prompt модель выбирает wrapper; для последующих turns рекомендация предназначена прежде всего для выбора subagent/model и Datarim-компонентов. Если нужен новый основной tier, начните новую сессию через wrapper.

Принудительно выбрать модель:

```bash
dr-claude-jev --model opus "Do the architectural migration"
```

One-shot режим:

```bash
dr-claude-jev --print "Review this module for race conditions"
```

## Какие решения принимает Jev

Один request содержит несколько независимых вопросов:

- `model_tier` — Choice: Haiku/Sonnet/Opus.
- `complexity` — Score: trivial → very complex.
- `needs_system2` — Noul.
- `production_risk` — Noul.
- `needs_validation` — Noul.
- `parallelizable` — Noul.
- `skill_choice` — Choice из локального shortlist.
- `agent_choice` — Choice из shortlist.
- `command_choice` — Choice из shortlist.
- `template_choice` — Choice из shortlist.
- `probe:skills|<name>` — по одному Noul на каждого кандидата-скилл (multi-select).

Таким образом Jev не получает задачу вида «придумай весь workflow». Он делает серию коротких System-One judgments, а policy остаётся в коде.

### Multi-skill и пороги доверия

У System-One API нет типа вопроса multi-select (`multichoice`, `multi`, `multiselect`, `tags`
возвращают HTTP 400). Поэтому «какие скиллы применимы» задаётся как N независимых `noul`-вопросов —
по одному на кандидата. Это почти бесплатно: вопросы одного запроса считаются параллельно
(замер: 1 вопрос ≈ 1.07 с, 8 вопросов ≈ 1.18 с), то есть латентность плоская, растут только токены.

Настройки в `config/jev-control.json` → `routing.component_selection`:

| Параметр | По умолчанию | Смысл |
|---|---|---|
| `apply_threshold` | 0.70 | с этого уровня компонент считается выбранным |
| `mention_threshold` | 0.45 | ниже порога применения — только упоминается, не навязывается |
| `multi_select_max` | 4 | сколько скиллов максимум применять одновременно |
| `candidate_probe_limit` | 8 | сколько кандидатов опрашивать |

Решение ниже порога **не навязывается** Claude: оно попадает в вывод с пометкой
«low confidence — advisory only». Ранее слабый выбор (по журналу — 0.36–0.64 уверенности)
подавался как решение; загруженный зря компонент тратит контекст и сбивает агента,
поэтому молчание здесь дешевле ошибки.

## Два рантайма: Claude Code и Codex

Один оркестратор управляет обоими CLI, но механизм переключения у них разный, и это не косметика.

| | Claude Code | Codex |
|---|---|---|
| Когда применяется смена тира | в **живой сессии** (`control_request` на stdin) | со **следующего хода** (`codex exec resume`) |
| Во что отображается тир | модель (`haiku`/`sonnet`/`opus`) + бюджет размышления | `model_reasoning_effort` (`low`/`medium`/`high`), плюс модель если задана |
| Сохраняется ли контекст | да, сессия не прерывается | да, `resume` восстанавливает тред |
| Учёт токенов | на каждое сообщение | один раз, в `turn.completed` |

У Codex нет канала управления живым процессом, поэтому его рычаг — resume-цепочка: каждый ход
это отдельный процесс `codex exec`, который может нести другой тир. Проверено на codex-cli
0.153.4: факт, записанный до смены effort, корректно вспоминается после — контекст действительно
переживает переключение.

Доступность моделей Codex зависит от аккаунта: на ChatGPT-аккаунте принималась только модель по
умолчанию, остальные отдавали HTTP 400. Поэтому карта тиров по умолчанию двигает **effort** и не
передаёт `-m`. Назначьте реальные модели, если они у вас есть:

```bash
export DATARIM_CODEX_MODEL_HAIKU=...
export DATARIM_CODEX_MODEL_SONNET=...
export DATARIM_CODEX_MODEL_OPUS=...
export DATARIM_JEV_RUNTIME=codex     # сделать Codex рантаймом по умолчанию
```

```bash
dr-claude-jev --runtime codex "задача"          # статический роутинг
dr-claude-jev --live --runtime codex "задача"   # динамический
dr-jev runtimes                                 # что установлено и как переключается
```

## Работа без интеграции

Все пути fail-open: отсутствие ключа, недоступный API, сломанный или отсутствующий конфиг
оставляют хост-CLI работоспособным без подсказок Jev. Проверено для каждого хука, как подпроцесса,
в каждом режиме отказа: код выхода 0, без трейсбеков.

Детерминированный порог запрета разрушительных команд вычисляется **до** чтения конфига, поэтому
отключение Jev убирает только *советующий* слой: `rm -rf /`, `git push --force`,
`git reset --hard` и `DROP DATABASE` остаются заблокированными. Это проверяется отдельным набором
тестов (`tests/test_runtimes.py::TestSafetyFloorIndependence`) во всех режимах отказа.

```bash
dr-jev off                    # для всей машины, сохраняется между сессиями
export DATARIM_JEV_DISABLE=1  # только текущая оболочка
dr-jev status                 # что именно сейчас действует
dr-jev on                     # включить обратно
```

Ядро Datarim не зависит от Jev по построению: ни одна команда `/dr-*`, ни один скилл, агент или
шаблон не ссылаются на плагин. Зависимость односторонняя.

## Динамический роутинг (`--live`)

Статический роутинг выбирает модель один раз, до начала работы. Но характер задачи меняется по
ходу: исследование, реализация, тесты и документирование требуют разной способности. Режим
`--live` это закрывает.

```bash
dr-claude-jev --live "задача"
dr-claude-jev --live --mode quality "задача"
```

### Почему это процесс, а не хук

Ни одно поле вывода хука не меняет модель сессии. Проверено на Claude Code 2.1.278: хук
`PreModelSwitch` реактивен (может разрешить/запретить уже запрошенное переключение), остальные
события возвращают только `additionalContext` / `permissionDecision`. Инициировать переключение
может `control_request` на stdin — он доступен, когда Claude запущен с
`--input-format stream-json --output-format stream-json`. Поэтому каналом владеет отдельный
процесс-супервизор:

```
задача ──> Jev (стартовый роутинг) ──> claude --model <tier>  (stream-json)
                                              │
                                        граница фазы / хода
                                              │
                                        Jev (переоценка)
                                              │
                                         SwitchGate
                                              │
                          control_request set_model / set_max_thinking_tokens
```

### Почему переключение ограничено

Смена модели сбрасывает prompt cache. Замер на 2.1.278: ход перед переключением прочитал из кэша
30 775 токенов; первый ход после — 0, и заново создал 27 614. То есть каждое переключение заново
оплачивает весь диалог. Наивный цикл «спрашивать Jev после каждого шага» потратит больше, чем
сэкономит. Настройки в `config/jev-control.json` → `live`:

| Параметр | По умолчанию | Смысл |
|---|---|---|
| `escalate_threshold` | 0.75 | уверенность для перехода вверх |
| `deescalate_threshold` | 0.85 | вниз — строже: понижение посреди проблемы дороже |
| `min_tokens_between_switches` | 25000 | не переплачивать за кэш того же контекста |
| `min_seconds_between_switches` | 90 | защита от дребезга |
| `max_switches_per_session` | 6 | жёсткий потолок расходов на re-cache |
| `turns_between_reroutes` | 2 | как часто тратить вызов Jev, если фаза не менялась |
| `model_ceiling` / `model_floor` | по режиму | live-переключение не выходит за рамки режима |

Смена фазы всегда даёт право на переоценку; в остальных случаях переоценки идут по счёту ходов.
Эскалация намеренно проще деэскалации: застрявший агент, жгущий ходы на дешёвой модели, — исход
хуже, чем недолгая переплата.

Каждое **заблокированное** переключение пишется в журнал с причиной (`blocked_by`) — непроизошедшее
переключение это данные о политике, а не отсутствие события.

При любом сбое Jev или транспорта сессия продолжает работу на текущей модели (fail-open).

### Многоходовое сопровождение

По умолчанию сессия одноходовая. Чтобы супервизор вёл задачу до конца:

```bash
python3 scripts/live_supervisor.py \
  --continue-prompt "Continue with the next step. Reply TASK_COMPLETE when finished." \
  --max-turns 8 --max-seconds 1800 "задача"
```

Маркер завершения проверяется буквально: угадывать завершение по прозе ненадёжно, а ошибка
здесь либо обрывает работу, либо зацикливает её.

Три независимых ограничителя, потому что каждый закрывает свой класс зависания:

- `--max-turns` — счётчик ходов; не спасёт, если ход не завершается;
- `--max-seconds` — общий лимит по часам; единственная защита от «болтливого, но застрявшего»
  агента, который сбрасывает межкадровый таймаут своей же активностью;
- внутренний `IDLE_TIMEOUT_S` (30 мин) — тишина между кадрами stream-json.

Причина остановки пишется в журнал (`stop_reason`), вместе с кодом выхода Claude и хвостом его
stderr при ненулевом выходе — иначе fail-open путь потом невозможно диагностировать.
`dr-jev stats` показывает распределение причин остановки.

## Прозрачность решений

```bash
dr-jev route --summary "задача"   # компактная сводка
dr-jev route --explain "задача"   # сводка + полный JSON вероятностей
dr-jev last                       # последнее решение с полосами вероятностей
dr-jev stats                      # накопленная статистика и predicted-vs-actual
dr-claude-jev --quiet "задача"    # без сводки
```

`dr-jev stats` — это обратная связь: он показывает, насколько Jev решителен по каждой оси и как
часто фактическая работа оказалась шире предсказанного компонента. Именно это расхождение —
вход для следующей версии архитектуры.

## Безопасность

По умолчанию `enforce_jev_denials=false`. Это намеренно: вероятностная модель не должна единолично становиться security boundary.

`PreToolUse` имеет два слоя:

1. Детерминированный hard floor для явно разрушительных команд.
2. Jev risk score как advisory context.

Чтобы экспериментально включить запрос review на очень высоком Jev risk, измените:

```json
"enforce_jev_denials": true
```

в `plugins/dr-jev-control/config/jev-control.json` или создайте отдельную конфигурацию и задайте:

```bash
export DATARIM_JEV_CONFIG=/path/to/jev-control.local.json
```

Не используйте Jev вместо существующих Datarim security gates, permission system Claude Code, branch protection, tests или human approval для необратимых внешних действий.

## Настройка порогов

Все ключевые константы собраны в одном файле:

`plugins/dr-jev-control/config/jev-control.json`

Это соответствует рекомендуемому TypeSafe подходу: вопросы и thresholds должны быть централизованы и ревьюиться человеком.

Стартовые пороги:

```json
{
  "advisory": 0.55,
  "require_review": 0.78,
  "deny_autonomous": 0.94
}
```

Не считайте их доказанными. Калибруйте на реальных задачах Datarim.

## Telemetry и A/B тест

Решения пишутся в:

```text
~/.datarim/jev/ledger.jsonl
```

По умолчанию полный prompt **не сохраняется**. Пишется SHA-256 и decision metadata. Чтобы сохранять текст для локального исследования, явно включите `store_prompt_text`, понимая privacy consequences.

Рекомендуемый эксперимент:

- 100–200 обычных задач Claude-only.
- 100–200 сопоставимых задач через `dr-claude-jev`.
- Сравнивать не только tokens, а `$ / accepted task`.
- Дополнительно: latency, число Opus/Sonnet/Haiku запусков, retry/escalation rate, acceptance rate, regressions, validation failures.

## TypeSafe skill

Этот plugin работает напрямую с HTTP API и не требует TypeSafe Agent Skill. Но сам skill полезно установить, чтобы Claude умел проектировать новые Jev use cases:

```bash
claude plugin marketplace add typesafe-ai/skills
claude plugin install typesafe@typesafe-ai
```

После этого можно использовать `/typesafe:typesafe-ai` при разработке новых decision contracts.

## Совместимость с Datarim

Plugin автоматически индексирует текущие каталоги:

- `skills/**/SKILL.md`
- `agents/*.md`
- `commands/*.md`
- `templates/*`

Поэтому при добавлении нового skill/agent/command/template отдельный hardcoded registry для Jev не нужен. На runtime строится короткий список кандидатов.

Это специально не заменяет Datarim graph. Graph остаётся источником структурных связей и workflow; Jev — runtime judgment layer.

## Fail-open и отказ TypeSafe

Если API key отсутствует, API недоступен или истёк timeout:

- wrapper использует `sonnet` как default initial model;
- prompt hook молча не добавляет Jev advice;
- deterministic safety floor продолжает работать;
- Claude Code остаётся usable.

Для production autonomous pipelines можно позже добавить отдельный fail-closed profile для конкретных high-risk decision classes, но не следует делать глобальный fail-closed для всей разработки.

## Удаление

Удалите managed entries, содержащие `dr-jev-control/scripts/`, из выбранного Claude settings файла и symlinks:

```bash
rm -f ~/.local/bin/dr-claude-jev ~/.local/bin/dr-jev
```

Сам plugin можно удалить из `plugins/dr-jev-control` после отключения hooks.

## Контроль целостности

`JEV-MANIFEST.sha256` покрывает только исходники плагина (`.py`, `.json`, `.yaml`, `.md`, `bin/`);
байт-код `__pycache__` и `.pytest_cache` исключены — они пересобираются и в контроле целостности
бессмысленны.

```bash
# проверить
shasum -a 256 -c JEV-MANIFEST.sha256

# перегенерировать после изменения плагина
{
  printf '# Integrity manifest for the dr-jev-control plugin (source files only).\n'
  printf '# Regenerate: see the command in documentation/how-to/claude-code-jev-control-plane.md\n'
  printf '# Verify: shasum -a 256 -c JEV-MANIFEST.sha256\n'
  find plugins/dr-jev-control -type f \
    \( -name '*.py' -o -name '*.json' -o -name '*.yaml' -o -name '*.md' \) \
    -not -path '*/__pycache__/*' -not -path '*/.pytest_cache/*' -print0 \
  | sort -z | xargs -0 shasum -a 256
  shasum -a 256 plugins/dr-jev-control/bin/dr-jev plugins/dr-jev-control/bin/dr-claude-jev
} > JEV-MANIFEST.sha256
```

## Что тестировать сегодня

Начните с трёх классов задач: маленький bugfix, обычная feature, сложная архитектурная задача. Перед запуском каждого Claude вызова выполните `dr-jev route`, посмотрите на решение, затем запускайте wrapper. После 20–30 задач проверьте ledger и отдельно выпишите случаи under-routing и over-routing. Только после этого меняйте questions/thresholds.

Для динамического роутинга полезнее другое измерение: запускайте `--live` и затем `dr-jev stats`.
Смотрите не на «правильно ли Jev угадал модель», а на расхождение между предсказанным компонентом
и фактическими фазами работы (`predicted` vs `actual` в журнале). Высокий счётчик
«work broader than the prediction» — это и есть сигнал, что одноразовый роутинг недоописывает
задачу, и именно он должен определять следующую версию архитектуры, а не интуиция.
