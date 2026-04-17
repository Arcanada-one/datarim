# Validation

```bash
# Validate email
python3 -c "
import re, sys
email = sys.argv[1]
ok = bool(re.match(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$', email))
print('VALID' if ok else 'INVALID')
" "user@example.com"

# Validate URL
python3 -c "
import re, sys
url = sys.argv[1]
ok = bool(re.match(r'^https?://[^\s/$.?#].[^\s]*$', url))
print('VALID' if ok else 'INVALID')
" "https://example.com"

# Validate IPv4
python3 -c "
import re, sys
ip = sys.argv[1]
ok = bool(re.match(r'^((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$', ip))
print('VALID' if ok else 'INVALID')
" "192.168.1.1"

# Validate UUID
python3 -c "
import re, sys
uid = sys.argv[1]
ok = bool(re.match(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', uid, re.I))
print('VALID' if ok else 'INVALID')
" "550e8400-e29b-41d4-a716-446655440000"
```
