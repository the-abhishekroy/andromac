"""Draws the Andromac DMG window background. Run: python3 dmg/make-background.py  (window is 660x390, drawn at 2x)"""
from PIL import Image, ImageDraw, ImageFont
import math, os
W, H = 1320, 780
here = os.path.dirname(os.path.abspath(__file__))
BOLD = '/System/Library/Fonts/Supplemental/Arial Bold.ttf'
REG = '/System/Library/Fonts/Supplemental/Arial.ttf'
def font(p, s):
    try: return ImageFont.truetype(p, s)
    except Exception: return ImageFont.load_default()

img = Image.new('RGB', (W, H), (0, 0, 0))                      # pure black, like the app
d = ImageDraw.Draw(img)
d.rounded_rectangle((5, 5, W - 6, H - 6), radius=30, outline=(38, 38, 38), width=3)

# light cards behind the two icons (Finder always draws dark labels, so they need a light surface)
for cx in (360, 960):
    d.rounded_rectangle((cx - 140, 262, cx + 140, 600), radius=34, fill=(236, 236, 236))

d.text((W / 2, 96), 'Andromac', font=font(BOLD, 104), fill=(255, 255, 255), anchor='mm')
d.text((W / 2, 170), 'Your Mac and your Android, one ecosystem', font=font(REG, 32), fill=(126, 126, 126), anchor='mm')

# arrow from the app to Applications, in the app's soft green
g = (135, 215, 135)
ax0, ax1, ay = 560, 780, 400
for i in range(ax0, ax1 - 30, 36):
    d.rounded_rectangle((i, ay - 4, i + 20, ay + 4), radius=4, fill=g)
d.polygon([(ax1 - 34, ay - 24), (ax1 + 8, ay), (ax1 - 34, ay + 24)], fill=g)
d.text((W / 2, 648), 'Drag Andromac into Applications', font=font(REG, 28), fill=(126, 126, 126), anchor='mm')

# footer: Made with <heart> by Abhishek Roy
f = font(BOLD, 30)
left, right = 'Made with', 'by Abhishek Roy'
lw = d.textlength(left, font=f); rw = d.textlength(right, font=f)
hw = 34; total = lw + 14 + hw + 14 + rw; x0 = W / 2 - total / 2; fy = 722
d.text((x0, fy), left, font=f, fill=(255, 255, 255), anchor='lm')
hx = x0 + lw + 14 + hw / 2
pts = []
for i in range(0, 360, 4):
    t = math.radians(i)
    pts.append((hx + 16 * math.sin(t) ** 3 * 1.2, fy - (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) * 1.2 - 2))
d.polygon(pts, fill=(255, 107, 129))
d.text((x0 + lw + 14 + hw + 14, fy), right, font=f, fill=(255, 255, 255), anchor='lm')

img.save(os.path.join(here, 'background@2x.png'))
img.resize((W // 2, H // 2), Image.LANCZOS).save(os.path.join(here, 'background.png'))
print('background ok')
