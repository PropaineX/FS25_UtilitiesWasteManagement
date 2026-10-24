"""Draft mod icon for Utilities & Waste Management: lightning bolt, slurry puddle with fumes, manure heap on a dark tile."""
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

# slurry puddle with stink fumes (middle)
import math
def puddle(dr, c):
    # lumpy puddle: a few overlapping ellipses
    for box in [(196, 270, 330, 322), (210, 258, 300, 300), (262, 262, 326, 304), (188, 282, 252, 322)]:
        dr.ellipse(box, fill=c)
glow(puddle, (92, 66, 32, 255), blur=8)
d.ellipse([214, 272, 300, 300], fill=(112, 82, 42, 255))           # wet centre
d.ellipse([226, 276, 262, 286], fill=(185, 150, 100, 255))         # shine
for x, y, r in [(286, 284, 7), (246, 300, 5), (304, 300, 4)]:      # bubbles
    d.ellipse([x - r, y - r, x + r, y + r], outline=(170, 135, 85, 255), width=3)

def fumes(dr, c):
    for x0, phase in [(222, 0.0), (262, 1.6), (302, 3.1)]:
        pts = []
        for i in range(40):
            y = 250 - i * 3.6
            x = x0 + 13 * math.sin(i / 6.0 + phase)
            pts.append((x, y))
        dr.line(pts, fill=c, width=9, joint="curve")
glow(fumes, (150, 200, 70, 230), blur=9)

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
