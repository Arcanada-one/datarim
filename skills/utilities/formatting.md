# Byte Humanization

```bash
# Humanize bytes
python3 -c "
def humanize(b):
    for u in ['B','KB','MB','GB','TB','PB']:
        if b < 1024: return f'{b:.1f} {u}'
        b /= 1024
import sys; print(humanize(int(sys.argv[1])))
" 1073741824
# Output: 1.0 GB
```

---

## Number Formatting

```bash
# Thousands separator
python3 -c "print(f'{1234567890:,}')"
# Output: 1,234,567,890

# Currency (USD)
python3 -c "print(f'${1234567.89:,.2f}')"
# Output: $1,234,567.89

# Percentage
python3 -c "print(f'{0.8567:.1%}')"
# Output: 85.7%
```

---

## Color Conversion

```bash
# Hex to RGB
python3 -c "
h = 'FF5733'
print(f'rgb({int(h[0:2],16)}, {int(h[2:4],16)}, {int(h[4:6],16)})')
"

# RGB to Hex
python3 -c "print(f'#{255:02X}{87:02X}{51:02X}')"

# Hex to HSL
python3 -c "
import colorsys
h = 'FF5733'
r,g,b = int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255
hue,l,s = colorsys.rgb_to_hls(r,g,b)
print(f'hsl({hue*360:.0f}, {s*100:.0f}%, {l*100:.0f}%)')
"

# HSL to Hex
python3 -c "
import colorsys
r,g,b = colorsys.hls_to_rgb(11/360, 0.60, 1.0)
print(f'#{int(r*255):02X}{int(g*255):02X}{int(b*255):02X}')
"
```
