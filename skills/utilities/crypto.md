# Hashing

```bash
# SHA-256
echo -n "data" | openssl dgst -sha256
openssl dgst -sha256 filename.txt

# SHA-512
echo -n "data" | openssl dgst -sha512

# MD5 (not for security, only checksums)
echo -n "data" | openssl dgst -md5

# File checksum (SHA-256)
# macOS:
shasum -a 256 filename.txt
# Linux:
sha256sum filename.txt
```

---

## Random & UUID

```bash
# UUID v4
uuidgen
# Lowercase UUID (macOS uuidgen outputs uppercase)
uuidgen | tr '[:upper:]' '[:lower:]'

# Random hex string (16 bytes = 32 hex chars)
openssl rand -hex 16

# Random base64 string (32 bytes)
openssl rand -base64 32

# Random integer in range [0, N)
python3 -c "import secrets; print(secrets.randbelow(1000))"
```

---

## Password Generation

```bash
# 20-char alphanumeric password
openssl rand -base64 30 | tr -dc 'A-Za-z0-9' | head -c 20

# 32-char with special characters
openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@#$%^&*' | head -c 32

# Passphrase (4 random words — requires a wordlist or python)
python3 -c "
import secrets
words = ['alpha','bravo','charlie','delta','echo','foxtrot','golf','hotel',
         'india','juliet','kilo','lima','mike','november','oscar','papa',
         'quebec','romeo','sierra','tango','uniform','victor','whiskey','xray']
print('-'.join(secrets.choice(words) for _ in range(4)))
"
```
