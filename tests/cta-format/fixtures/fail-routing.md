---

**QA failed для TUNE-0032 — earliest failed layer: Layer 3 (Plan)**

1. `/dr-plan TUNE-0032` — **рекомендуется** — пересмотреть план (missing rollback strategy)
2. `/dr-prd TUNE-0032` — если нужно ревизовать scope
3. Эскалация — после 3 same-layer fails (loop guard)

---
