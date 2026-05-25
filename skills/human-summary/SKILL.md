---
name: human-summary
description: Plain-language operator recap for /dr-qa, /dr-compliance, /dr-archive. Four sub-sections, banlist + whitelist + per-paragraph escape hatch, 150-400 words.
current_aal: 1
target_aal: 2
---

# Human Summary — Operator-Facing Recap

A short, human-friendly recap that ends the output of `/dr-qa`, `/dr-compliance`, and `/dr-archive`. Sits **between** the technical block (verdict / report / archive write) and the CTA block. The technical block stays unchanged — this is a supplemental layer aimed at a human reader, not the agent.

## Why it exists

The technical output (per-layer verdicts, validation checklist, archive document path, CTA) is optimized for an agent in the loop. A human operator reading the chat wants four answers, fast:

1. What was actually done.
2. What worked.
3. What didn't work or is still open.
4. What happens next.

Opening the archive document or the compliance report to extract those four answers is friction. This skill removes the friction.

## When to apply

Loaded by:

- `commands/dr-qa.md` — after the QA-report write, before the CTA block. Runs on every overall verdict (ALL_PASS, CONDITIONAL_PASS, BLOCKED). On BLOCKED the «Что не получилось» sub-section carries the failure detail in plain language; «Что дальше» paraphrases the FAIL-Routing CTA without command syntax.
- `commands/dr-compliance.md` — after the verdict / per-step report, before the CTA block. Runs on every verdict (COMPLIANT, COMPLIANT_WITH_NOTES, NON-COMPLIANT). Same NON-COMPLIANT shape.
- `commands/dr-archive.md` — after the activeContext update, before the CTA block. Sourced from the just-written archive document plus the reflection file.

Other pipeline commands MAY adopt the same contract later (`/dr-do`, `/dr-plan`). The contract is identical regardless of caller.

## Output contract

The summary is emitted in chat as a markdown section:

```
## Отчёт оператору        # if operator language is Russian
## Operator summary       # if operator language is English

**{TASK-ID} · {title}**     # MANDATORY self-identifier preamble (see § Self-identifier preamble)

**Что было сделано / What was done**
... operator brief (paraphrased from § Operator brief verbatim) + which of those goals were achieved (1-3 sentences) ...

**Что получилось / What worked**
- bullet
- bullet

**Что не получилось / осталось открытым / What didn't work or is still open**
- bullet
- bullet
(or a single line «всё закрыто» / «nothing outstanding» if there is nothing)

**Что дальше / What's next**
... 1-2 sentences ...
```

**Sub-section order is fixed and exhaustive.** The self-identifier preamble + four sub-headings are the entire shape. **Adding** a fifth sub-section (e.g. «Где это видно» / «References» / «Source files» / «Audit trail» / «Links») is a `block` finding — references go inside the technical block above the summary or as a single sentence inside «Что дальше», not as their own sub-section. **Dropping** any of the four sub-headings (most often the writer dives straight into results and silently skips «Что было сделано») is also a `block` finding. Empty sub-section ⇒ emit a single-line placeholder («всё закрыто» / «nothing outstanding» / «нет открытых пунктов») — never omit the heading itself.

### Self-identifier preamble

The first non-empty line after the section header MUST be `**{TASK-ID} · {title}**` (same one-liner form as the Stage Header in `cta-format.md` § Stage Header). Rationale: the Stage Header at the top of the full `/dr-*` response identifies the task while the operator reads in-context. But the Human Summary section is **also read standalone** — operators scroll back the chat log and read the last summary chunk out of context. Without the self-identifier, a finished summary is unattributable: «Что получилось» + «Что не получилось» bullets describe results of *some* task without saying which.

Format rules are identical to Stage Header:

- `**{TASK-ID} · {title}**` with U+00B7 MIDDLE DOT separator surrounded by single ASCII spaces.
- Title verbatim from `tasks.md` one-liner; when the task is already in the archive document, take the title from `archive-{ID}.md` frontmatter `title:` field.
- Bold inline only — no surrounding heading, no blockquote, no italics.

The preamble is **mandatory for all callers** (`/dr-qa`, `/dr-compliance`, `/dr-archive`, and any future caller). Duplication with the Stage Header at the top of the response is **acceptable** — the two surfaces serve different reading modes (in-context first-line vs standalone section header).

### «Что было сделано» — explicit definition

This sub-section is the operator-facing answer to **«Что я просил и что вы для этого сделали?»** It MUST surface two facts in one to three sentences:

1. **What the operator asked for** — paraphrase from `datarim/tasks/{TASK-ID}-init-task.md` § Operator brief (verbatim) (or the resolved § Source command if init-task absent). For `/dr-archive` also cross-reference `archive-{ID}.md` § Начальная задача. Stay close to the operator's own words — this is not the place for technical jargon.
2. **Which of those goals were achieved** — one-sentence outcome summary keyed to the brief. For `/dr-archive` cross-reference `archive-{ID}.md` § Как решили (без копирования всего списка — извлечение).

Pure descriptions of the *artifact-mutation process* («архив обновлён», «секции добавлены», «cleanup PASS») are **insufficient** — they describe what was *written about* the task, not what was *done for* the task. The latter is what the operator needs to see. A summary whose «Что было сделано» starts with «Архив дополнен …» / «Секции обновлены …» fails this rule and is a `block` finding (per § Severity ladder).

When init-task brief is unavailable (legacy task predating the init-task contract): paraphrase from `tasks/{TASK-ID}-task-description.md` § Overview and label as «(brief восстановлен из § Overview — оригинальный operator brief отсутствует)» so the operator sees the source explicitly.

Language detection: choose the language of the most recent operator message. Default for Russian-speaking operators is Russian.

Length budget: **150-400 words total** across the four sub-sections (not per sub-section). Hard upper bound. If the source material (archive document, compliance report, QA report) is bigger, compress aggressively — the goal is a fast read, not a faithful index.

### Mutability per caller

The chat-emission is the canonical surface. Persistence beyond chat is caller-specific:

- `/dr-qa` MAY append the same section to `datarim/qa/qa-report-{task-id}.md` at the bottom under a `## Plain-language summary` heading. Always chat-only when that file does not exist.
- `/dr-compliance` MAY append the same section to `datarim/reports/compliance-report-{task_id}.md` when that file exists.
- `/dr-archive` is **chat-only** — the archive document and the reflection document MUST NOT be mutated by this skill (the archive document is the permanent record; the reflection document already exists from Step 0.5).
- Other future callers default to chat-only unless their command file explicitly authorises a write target.

## Banlist + Whitelist + Escape Hatch (Option C)

Plain-language is enforced through three orthogonal layers.

### Banlist

The file `skills/human-summary/banlist.txt` lists ASCII tokens that MUST NOT appear in Russian-language prose of the summary. The list covers DevOps / CI-CD terminology, Git verbs, monitoring nouns, runtime processes, testing jargon, and gate/hook vocabulary. Universal Russian equivalents exist for every entry («развёртывание» for `deploy`, «откат» for `rollback`, «слияние» for `merge`, etc.).

Matching rule: case-insensitive full-word equality against ASCII tokens of length ≥3 found in the Russian sub-sections. Cyrillic transliterations («пайплайн», «коммит») are NOT matched — they are tolerated even when the parent term is banned.

When the operator-language is English, the banlist is informational only — the four sub-section sub-headings remain bilingual but the prose may use the original English vocabulary.

### Whitelist

The file `skills/human-summary/whitelist.txt` lists universally accepted technical terms with NO stable Russian-language equivalent: `JSON`, `OAuth`, `HTTP`, `CLI`, `RFC`, `CI/CD`, and so on. The whitelist is evaluated BEFORE the banlist. A token listed in the whitelist is allowed unconditionally even if orthographically similar to a banlist entry.

### Per-paragraph escape hatch

A single paragraph or a verbatim quoted block may be exempted from the banlist by wrapping it in a fence:

```markdown
<!-- gate:literal -->
... verbatim content ...
<!-- /gate:literal -->
```

Scope rules:

- Permitted content: verbatim command output, error messages, code snippets, PRD excerpts, log lines. The fence preserves auditability of the actual wording.
- Prohibited content: wrapping an entire plain-language report or narrative prose. The fence is not a way to disable the rules for the whole summary.
- Line budget: opening tag and closing tag MUST be ≤15 lines apart.
- Paragraph budget per task: at most **2 paragraphs** may be fenced inside one summary. A third gated paragraph is a `warn` finding; a fifth is a `block` finding (see severity ladder).
- An unclosed opening tag is a `warn` finding, not a block.

### Severity ladder (info / warn / block)

Banlist offences aggregate across the whole summary:

- 1st offence ⇒ `info` — recorded in the QA / compliance report, summary still emits.
- 3rd offence ⇒ `warn` — visible warning above the summary, summary still emits.
- 5th offence ⇒ `block` — summary is rejected, caller emits a brief plain-language note explaining that the recap was suppressed and offers a re-run with corrections.

The same ladder applies to escape-hatch abuse and to merge-conflict markers found in `banlist.txt` / `whitelist.txt`.

### Archive grandfathering

The validator runs on the **runtime** plain-language report files only (the chat output and the optional appended sections in `datarim/qa/` and `datarim/reports/`). Existing `archive-{ID}.md` documents are **never re-validated**. Adding a word to the banlist in a patch release does not open historical archives, and an archive written before this contract is not retroactively a `block` finding.

### Missing list files

If `banlist.txt` or `whitelist.txt` is absent at runtime, the caller MUST emit a one-line note `human-summary lists missing — skipping plain-language guard` and proceed without the summary. The technical block and the CTA are unchanged. The bats spec-regression test guards against silent removal.

## Sourcing rules per caller

### From `/dr-qa`

- «Что было сделано» — one phrase about the scope of the task being reviewed (read from `datarim/tasks/{TASK-ID}-task-description.md` § Overview).
- «Что получилось» — layers that returned PASS or PASS_WITH_NOTES, expectations checklist items that ended `met`.
- «Что не получилось» — layers that returned FAIL with one-phrase reasons, expectations items at `partial` without override or at `missed`. On overall ALL_PASS emit «всё закрыто» / «nothing outstanding».
- «Что дальше» — for ALL_PASS / CONDITIONAL_PASS at L3-L4: «можно переходить к проверке итогов» / «ready for compliance». For L1-L2: «можно архивировать» / «ready to archive». For BLOCKED: paraphrase the FAIL-Routing target layer name without command syntax. **Mirror** means paraphrase, not verbatim copy — the CTA block below already carries the command tokens.

### From `/dr-compliance`

- «Что было сделано» — one phrase about the scope of the task being verified (read from `datarim/tasks/{TASK-ID}-task-description.md` § Overview).
- «Что получилось» — checks that passed in the compliance report.
- «Что не получилось» — checks that failed; on COMPLIANT verdict emit «всё закрыто» / «nothing outstanding».
- «Что дальше» — for PASS: «можно архивировать». For NON-COMPLIANT: paraphrase the FAIL-Routing direction in plain language. **Mirror** means paraphrase, not verbatim copy.

### From `/dr-archive`

- «Что было сделано» — sourced from § Overview / § Outcome of the just-written archive document.
- «Что получилось» — acceptance criteria marked done in the archive document.
- «Что не получилось» — Known Outstanding State / Operator Handoff section of the archive, plus any deferred items in reflection.
- «Что дальше» — next active task headline or the operator handoff item, in plain language.

## Style rules

- Plain language. Imagine the reader has not seen the task description, has not opened any file, and is not a programmer.
- **No tables.** Use bullet lists or running prose. A single-level bullet list is acceptable; nested bullets are not.
- In Russian text, do not use English loanwords when a Russian equivalent exists (the banlist enumerates the most common offenders). English file paths and command names stay in original form (`commands/dr-archive.md`), but explain them in one phrase the first time they appear.
- Do not paste bare task identifiers without recap. Always pair them with a one-phrase recap.
- Do not reference internal file paths unless they are user-actionable.
- Avoid acronyms without expansion (TDD, PRD, AAL, AC) on first use. Whitelisted protocol names (`HTTP`, `JSON`, `OAuth`) do not require expansion.
- No emoji. No multi-level nested lists. No promises about the future («после этого всё заработает»). State only what is done and what is the next step.

## Anti-patterns

- A table-style layout («| AC | Status |»). Forbidden.
- A wall of file paths with no context.
- A bullet list of acronyms.
- A copy-paste of the technical verdict block.
- Promises («в следующей версии будет…»).
- A summary longer than 400 words. If the source material does not fit, drop detail, never extend.
- Mixing languages inside one summary. Pick one and stick to it.
- Wrapping the entire summary in `<!-- gate:literal -->` to bypass the banlist. The fence is for verbatim quoted blocks, not narrative prose.

## Failure mode

If the skill cannot be loaded (missing file), the caller proceeds without the summary section. The technical output and the CTA block remain unchanged. The bats spec-regression test guards against silent removal of the skill, its sub-headings, the banlist / whitelist, and the escape-hatch contract.

<!-- gate:history-allowed -->
In addition to the markdown contract, the severity ladder above is also checked by a programmatic validator — the opt-in Claude Code `Stop` hook `dev-tools/hooks/dr-output-stop.sh` (TUNE-0264). When the user invoked `/dr-archive`, `/dr-compliance`, or `/dr-qa`, the hook extracts the `## Отчёт оператору` / `## Operator summary` section and emits a block finding for any of `missing_section`, `missing_preamble`, `missing_subheading_<1..4>`, `fifth_subheading`, or `wrong_order`. On first occurrence the hook returns stdout JSON `{"decision":"block","reason":"..."}` so the model regenerates the summary; on retry (`stop_hook_active=true`) the same findings are emitted to stderr as advisory and exit 0 (retry budget = 1). The hook is opt-in via `~/.claude/settings.json § hooks.Stop[]` per `docs/how-to/dr-output-hook.md`.
<!-- /gate:history-allowed -->

## Example (RU)

> ## Отчёт оператору
>
> **Что было сделано.** В трёх командах Датарима — проверке качества, проверке итогов и архивации — теперь печатается короткий человеческий пересказ для оператора. Раньше после прогона выводился только технический блок (вердикт, ссылки на файлы, инструкции для следующего шага); теперь над инструкциями появляется четыре простых абзаца.
>
> **Что получилось**
> - Один навык описывает контракт пересказа: четыре подзаголовка, длина от ста пятидесяти до четырёхсот слов, без таблиц.
> - Появились два словаря — запрещённых англоязычных слов и общепринятых сокращений (например, `JSON` или `OAuth`); словарь общепринятых читается раньше словаря запрещённых.
> - Внутри одного пересказа допустимо процитировать вывод инструмента дословно — для этого предусмотрен «литеральный блок» с открывающим и закрывающим маркером.
> - Тест-сторож в `tests/` ловит случайное удаление подзаголовков, словарей или маркеров литерального блока.
>
> **Что не получилось / осталось открытым**
> - Жёсткая проверка словарей в момент вывода ещё не подключена — пока контракт фиксируется текстом и тестом-сторожем, а сам валидатор появится отдельной задачей.
>
> **Что дальше.** Можно переходить к проверке итогов. Первый же запуск проверки итогов сам выведет такой пересказ — это и будет живая проверка, что всё работает.

## Example (EN)

> ## Operator summary
>
> **What was done.** Three Datarim commands — the quality-review step, the post-verification step, and the archive step — now end with a short human recap for the operator. Previously the output was technical only (verdict, file paths, next-step instructions); now four plain paragraphs sit above the instructions.
>
> **What worked**
> - A single skill captures the recap contract: four sub-headings, a length budget of 150 to 400 words, no tables.
> - Two sibling lists appeared — a list of forbidden anglicisms and a list of universal abbreviations (`JSON`, `OAuth`); the universal list is consulted before the forbidden list.
> - Inside one recap the operator may quote tool output verbatim through a literal-block fence with explicit opening and closing markers.
> - A guard test in `tests/` catches accidental removal of the sub-headings, the lists, or the literal-block fence.
>
> **What didn't work or is still open**
> - A strict runtime validator that scans the emitted text against the lists is not wired yet — for now the contract is fixed in prose and in the guard test; the validator itself ships in a follow-up.
>
> **What's next.** The work can move on to the post-verification step. The first run of that step will itself emit this recap, which doubles as a live check that the wiring works.

## See also

- Архивный и compliance-отчёт используют тот же банлист (`skills/human-summary/banlist.txt` + `skills/human-summary/whitelist.txt`). См. `${DATARIM_RUNTIME:-$HOME/.claude}/templates/archive-template.md` § «Как решили» и `${DATARIM_RUNTIME:-$HOME/.claude}/templates/compliance-report-template.md` § «Как решили» — банлист применяется к прозе четырёх верхних разделов; аудит-аддендум обёрнут в `<!-- gate:literal -->` fence для технических таблиц.
- Канонический валидатор для прозы шаблонов — `dev-tools/check-banlist-on-prose.sh` (awk one-shot, поддерживает YAML frontmatter skip + `<!-- gate:literal -->` / `<!-- gate:example-only -->` fence-блоки).
