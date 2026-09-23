# Datarim Sync

Synchronize framework files between `${DATARIM_RUNTIME:?}/` (active) and the Datarim repo.

```bash
# Set repo path (adjust per project)
DR_REPO="Projects/Datarim/code/datarim"

# Sync TO repo (after editing framework files locally)
for d in agents skills commands templates; do
  diff -rq "${DATARIM_RUNTIME:?}/$d/" "$DR_REPO/$d/" 2>/dev/null | grep "differ\|Only"
done
# Then copy changed files:
# cp ${DATARIM_RUNTIME:?}/agents/tester.md $DR_REPO/agents/

# Sync FROM repo (after pulling repo updates)
for d in agents skills commands templates; do
  diff -rq "$DR_REPO/$d/" "${DATARIM_RUNTIME:?}/$d/" 2>/dev/null | grep "differ\|Only"
done
# Then copy changed files:
# cp $DR_REPO/skills/datarim-system/SKILL.md ${DATARIM_RUNTIME:?}/skills/

# Full sync TO repo (overwrite all)
for d in agents skills commands templates; do
  cp "${DATARIM_RUNTIME:?}/$d/"*.md "$DR_REPO/$d/"
done

# Full sync FROM repo (overwrite all)
for d in agents skills commands templates; do
  cp "$DR_REPO/$d/"*.md "${DATARIM_RUNTIME:?}/$d/"
done

# Verify sync (should produce no output if identical)
for d in agents skills commands templates; do
  diff -rq "${DATARIM_RUNTIME:?}/$d/" "$DR_REPO/$d/" 2>/dev/null
done
```
