# Date & Time

```bash
# Current date (ISO)
date +%Y-%m-%d

# Current datetime UTC (ISO 8601)
date -u +%Y-%m-%dT%H:%M:%SZ

# Current epoch timestamp
date +%s

# Epoch to human-readable
# macOS:
date -r 1700000000 +%Y-%m-%dT%H:%M:%SZ
# Linux:
date -d @1700000000 +%Y-%m-%dT%H:%M:%SZ

# Timezone conversion
TZ="America/New_York" date +%Y-%m-%dT%H:%M:%S%z
TZ="Europe/London" date +%Y-%m-%dT%H:%M:%S%z
TZ="Asia/Tokyo" date +%Y-%m-%dT%H:%M:%S%z

# Date arithmetic (macOS)
date -v+7d +%Y-%m-%d    # 7 days from now
date -v-1m +%Y-%m-%d    # 1 month ago

# Date arithmetic (Linux)
date -d "+7 days" +%Y-%m-%d
date -d "-1 month" +%Y-%m-%d
```

---

## Timezone Conversion

```bash
# Convert between timezones
python3 -c "
from datetime import datetime
from zoneinfo import ZoneInfo
dt = datetime.now(ZoneInfo('America/New_York'))
print('NYC:', dt.strftime('%Y-%m-%d %H:%M:%S %Z'))
print('UTC:', dt.astimezone(ZoneInfo('UTC')).strftime('%Y-%m-%d %H:%M:%S %Z'))
print('Tokyo:', dt.astimezone(ZoneInfo('Asia/Tokyo')).strftime('%Y-%m-%d %H:%M:%S %Z'))
"

# List available timezones
python3 -c "from zoneinfo import available_timezones; print('\n'.join(sorted(available_timezones())))" | head -20
```

**Note:** `zoneinfo` requires Python 3.9+. For older Python, use `pytz`.
