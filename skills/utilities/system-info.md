# OS Info

```bash
# Full system info
uname -a

# macOS version
sw_vers

# Linux distribution
lsb_release -a 2>/dev/null || cat /etc/os-release

# Current user
whoami

# Hostname
hostname

# Architecture
uname -m
```

---

## Math

```bash
# Python3 (arbitrary precision, float support)
python3 -c "print(2 ** 256)"
python3 -c "print(round(3.14159 * 100, 2))"
python3 -c "import math; print(math.sqrt(144))"

# bc (pipe expressions)
echo "scale=10; 22/7" | bc -l
echo "2^64" | bc
```
