# Marker-skip fixture

Two blocks. The first is marked nosec-extract; the second is normal.

```bash
# nosec-extract
echo "this would be flagged but author requests skip"
```

```python
# noshellcheck-extract
print("skipped python block (using noshellcheck-extract marker)")
```

```bash
echo "extracted normally"
```
