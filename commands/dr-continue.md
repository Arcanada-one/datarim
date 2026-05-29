---
name: dr-continue
description: Deprecated alias for /dr-next
deprecated: true
replacement: /dr-next
---

# /dr-continue - Deprecated Alias

`/dr-continue` is retained as a deprecated compatibility alias for `/dr-next`
through the Datarim 2.21.x line.

Use `/dr-next` for all new instructions, CTA block ([definition](../skills/cta-format/SKILL.md))s, examples, and public
documentation. The alias preserves existing operator muscle memory and older
automation while the command surface transitions.

## Behavior

When invoked, apply the same task resolution and snapshot-first resume semantics
defined by `commands/dr-next.md`.

## Compatibility

- Primary command: `/dr-next`
- Deprecated alias: `/dr-continue`
- Removal window: not before the next minor release after 2.21.x and only after
  explicit operator approval.

