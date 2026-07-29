---
task_id: TUNE-0530
artifact: init-task
schema_version: 1
captured_at: 2026-07-29
captured_by: /dr-init
operator: valentov
status: canonical
source: /dr-init
---

# TUNE-0530 — Init-Task (canonical operator brief)

> Контракт: оператор может на любом этапе работы дополнять файл; каждый этап
> pipeline ОБЯЗАН сверяться с ним и фиксировать в своём выходе любые
> расхождения.

## Source command

```
/dr-init TUNE-0530 — Rework stack selection: from prescribed stacks to justified proposals. L3-L4, research + consilium heavy. The defect: skills/tech-stack/SKILL.md prescribes "Required Stack" per project type with no alternatives, trade-offs, or decision surface. Systems languages (Rust, Go) are absent. The framework contradicts itself with stack-agnostic-gate.md. Target outcome: informed operator choice at PRD/plan time with 2-3 viable candidate stacks, explicit trade-offs, and a recommendation — not a different set of hardcoded defaults. Deliverables: audit of prescription surfaces, design via Fable 5 + consilium, implementation of replacement mechanism, bats tests, validation dry-run against Control Arcana case.
```

## Operator brief (verbatim)

The target outcome is **informed operator choice at PRD/plan time**, not a different set of hardcoded defaults. Replacing one prescription with another is a failed outcome.

The defect: `skills/tech-stack/SKILL.md` prescribes "Required Stack" per project type with no alternatives, trade-offs, or decision surface. The section heading is literally "Project Type -> Required Stack" — prescription, not guidance. Systems languages (Rust, Go) are absent from the table despite being in production use across the ecosystem (Disk Arcana, ARAS, Cubrim, RTK).

The framework contradicts itself: `skills/evolution/stack-agnostic-gate.md` forbids naming concrete technologies in skills, while `tech-stack/SKILL.md` prescribes them wholesale.

A real case exposed the defect: Control Arcana redesign. An agent concluded "no MUI" on the false premise that MUI is paid — it is MIT-licensed. The framework offered no mechanism to surface "Tailwind vs MUI" as a decision with trade-offs. A legitimate architectural question never reached the operator.

The task: rework the stack selection block to produce, at PRD/plan time, 2-3 viable candidate stacks with explicit trade-offs and a recommendation — not a single mandated answer. Cover architecture choices too (monolith vs services, SSR vs SPA, sync vs event-driven, SQL vs document). Define when the question is worth asking. Record the operator's choice ADR-style and make it binding downstream via the immutability/return-to-plan contract. Keep defaults for the common path.

Deliverables: (1) audit of every stack prescription surface, (2) design via Fable 5 + consilium, (3) implementation reworking `skills/tech-stack/` and wiring into `/dr-prd`/`/dr-plan`, (4) add missing domains (cross-platform CLI/desktop, systems services), (5) bats tests asserting wiring and proposal shape, (6) validation dry-run against the Control Arcana case.

Research requirement: survey current practice across frontend component/styling, meta-frameworks, systems/cross-platform languages, backend frameworks, and decision-making methods (ADR, ATAM, technology radar, weighted-criteria selection). Weigh hiring/AI-assistance familiarity, LTS, licence, bundle/runtime cost, migration cost, and ecosystem coherence.

## Append-log (operator amendments)

> Дополнения добавляются хронологически; каждое — отдельная подпись.
> Агенты должны читать **весь** append-log, не только верхний блок.

_(пусто на момент создания)_
