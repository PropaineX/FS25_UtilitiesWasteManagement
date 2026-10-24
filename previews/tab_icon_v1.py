"""ESC menu tab / page header icon: a water drop with a lightning bolt cut out of it (user, 2026-10-24).
White on transparent (the game tints menu icons). Usage: python -I previews\\tab_icon_v1.py <out.png> [preview.png]"""
import sys

from PIL import Image, ImageDraw

S = 256
K = 4                      # draw big, shrink for smooth edges
N = S * K


def draw():
    img = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(img)
    # drop: round bottom + pointed top
    cx, r = N / 2, N * 0.30
    cy = N * 0.62
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    tip = N * 0.06
    # the sides touch the circle at its tangent points, so the outline runs smooth
    import math
    dist = cy - tip
    a = math.asin(r / dist)                       # half the angle at the tip
    tx = r * math.cos(a)
    ty = cy - r * math.sin(a)
    d.polygon([(cx, tip), (cx - tx, ty), (cx + tx, ty)], fill=255)
    # bolt, cut out
    bolt = [(0.555, 0.33), (0.395, 0.64), (0.495, 0.64), (0.445, 0.86), (0.615, 0.53), (0.515, 0.53), (0.575, 0.33)]
    d.polygon([(x * N, y * N) for x, y in bolt], fill=0)
    alpha = img.resize((S, S), Image.LANCZOS)
    out = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


if __name__ == "__main__":
    icon = draw()
    icon.save(sys.argv[1])
    if len(sys.argv) > 2:
        # preview: on the green header tile and on the dark menu column
        pv = Image.new("RGB", (560, 280), (35, 35, 35))
        tile = Image.new("RGB", (240, 240), (126, 163, 24))
        dark = Image.new("RGB", (240, 240), (20, 20, 20))
        small = icon.resize((150, 150), Image.LANCZOS)
        tile.paste((25, 25, 25), (45, 45), small)
        dark.paste((235, 235, 235), (45, 45), small)
        pv.paste(tile, (20, 20))
        pv.paste(dark, (300, 20))
        pv.save(sys.argv[2])
