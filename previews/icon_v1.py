"""Draft mod icon for Utilities & Waste Management: lightning bolt, slurry drop, manure heap on a dark tile."""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

out = sys.argv[1]
S = 512
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# tile with a soft vertical gradient
tile = Image.new("RGBA", (S, S))
td = ImageDraw.Draw(tile)
for y in range(S):
    t = y / S
    td.line([(0, y), (S, y)], fill=(int(28 + 14 * t), int(40 + 10 * t), int(36 + 6 * t), 255))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([8, 8, S - 8, S - 8], radius=56, fill=255)
img.paste(tile, (0, 0), mask)
d = ImageDraw.Draw(img)


def glow(shape_draw, color, blur=10):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shape_draw(ImageDraw.Draw(layer), color)
    halo = layer.filter(ImageFilter.GaussianBlur(blur))
    img.alpha_composite(halo)
    img.alpha_composite(layer)


# lightning bolt (left)
def bolt(dr, c):
    dr.polygon([(150, 70), (82, 225), (138, 225), (104, 340), (196, 180), (140, 180), (176, 70)], fill=c)
glow(bolt, (255, 205, 40, 255))

# slurry drop (middle)
def drop(dr, c):
    cx, top, r = 262, 110, 62
    dr.polygon([(cx, top), (cx - r + 4, 255), (cx + r - 4, 255)], fill=c)
    dr.ellipse([cx - r, 230 - r + 40, cx + r, 230 + r + 40], fill=c)
glow(drop, (150, 105, 55, 255))
d.ellipse([238, 250, 258, 270], fill=(210, 175, 130, 255))  # shine

# manure heap (right)
def heap(dr, c):
    dr.pieslice([330, 175, 470, 335], 180, 360, fill=c)
    dr.ellipse([355, 140, 445, 230], fill=c)
glow(heap, (105, 72, 40, 255))
for x, y in [(370, 225), (410, 200), (430, 240), (390, 180)]:
    d.ellipse([x, y, x + 12, y + 8], fill=(140, 100, 60, 255))

# title
font = ImageFont.truetype("arialbd.ttf", 62)
small = ImageFont.truetype("arialbd.ttf", 38)
for text, f, y in [("UTILITIES", font, 368), ("& WASTE MANAGEMENT", small, 438)]:
    w = d.textlength(text, font=f)
    d.text(((S - w) / 2, y), text, font=f, fill=(245, 245, 240, 255), stroke_width=3, stroke_fill=(0, 0, 0, 255))

img.save(out)
