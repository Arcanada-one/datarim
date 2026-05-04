# Mixed fixture

Three blocks: one extracted, one inside counter-example, one with marker.

```bash
echo "block-1 extracted"
```

<!-- security:counter-example -->
```python
# this is the wrong way
import os; os.system("rm -rf /")
```
<!-- /security:counter-example -->

```python
# nosec-extract
print("block-3 has skip marker, must NOT extract")
```

```bash
echo "block-4 extracted"
```
