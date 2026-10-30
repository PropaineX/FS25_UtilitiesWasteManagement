"""Our GUI image sheet gui/uwm_ui.dds (+ .png): white shapes on transparent, 512 x 512, 64 px cells, tinted in game.
Same drawings as the approved mock-ups (menu v4, CO-OP v6, form v6). Cell order = UWMGui.ICONS in scripts/gui/UWMGui.lua.
python -I ui_atlas_v1.py <out.png>   (then previews/png_to_dds.py <png> <dds>)"""
import sys
from PIL import Image, ImageDraw

S = 4                      # drawn 4x and scaled down for smooth edges
CELL = 64 * S
W = (255, 255, 255, 255)
NAMES = ["solid", "tile", "bill", "tray", "cart", "tag", "slurry", "manure", "power", "bulk", "pallet", "farm", "depot",
         "arrow", "pencil", "drop", "pill"]

def draw(d, name, cx, cy, s):
    w = max(2, int(3.2 * s))
    if name == "solid":
        d.rectangle([cx - 32 * s, cy - 32 * s, cx + 32 * s, cy + 32 * s], fill=W)
    elif name == "tile":
        d.rounded_rectangle([cx - 31 * s, cy - 31 * s, cx + 31 * s, cy + 31 * s], 9 * s, fill=W)
    elif name == "pill":
        d.rounded_rectangle([cx - 31 * s, cy - 14 * s, cx + 31 * s, cy + 14 * s], 14 * s, outline=W, width=w)
    elif name == "bill":
        d.rounded_rectangle([cx - 13 * s, cy - 17 * s, cx + 13 * s, cy + 17 * s], 3 * s, outline=W, width=w)
        d.line([cx - 7 * s, cy - 8 * s, cx + 7 * s, cy - 8 * s], fill=W, width=w - 1)
        d.line([cx - 7 * s, cy - 2 * s, cx + 3 * s, cy - 2 * s], fill=W, width=w - 1)
        d.line([cx - 5 * s, cy + 9 * s, cx + 7 * s, cy + 9 * s], fill=W, width=w)
    elif name == "tray":
        d.line([cx, cy - 17 * s, cx, cy + 4 * s], fill=W, width=w)
        d.polygon([(cx - 8 * s, cy - 2 * s), (cx + 8 * s, cy - 2 * s), (cx, cy + 8 * s)], fill=W)
        d.line([cx - 15 * s, cy + 6 * s, cx - 15 * s, cy + 15 * s, cx + 15 * s, cy + 15 * s, cx + 15 * s, cy + 6 * s], fill=W, width=w)
    elif name == "cart":
        d.line([cx - 17 * s, cy - 13 * s, cx - 11 * s, cy - 13 * s, cx - 6 * s, cy + 6 * s, cx + 13 * s, cy + 6 * s,
                cx + 17 * s, cy - 7 * s, cx - 9 * s, cy - 7 * s], fill=W, width=w)
        d.ellipse([cx - 7 * s, cy + 10 * s, cx - 1 * s, cy + 16 * s], fill=W)
        d.ellipse([cx + 7 * s, cy + 10 * s, cx + 13 * s, cy + 16 * s], fill=W)
    elif name == "tag":
        d.polygon([(cx - 16 * s, cy - 4 * s), (cx - 4 * s, cy - 16 * s), (cx + 16 * s, cy - 16 * s), (cx + 16 * s, cy + 4 * s),
                   (cx + 4 * s, cy + 16 * s)], outline=W, width=w)
        d.ellipse([cx + 5 * s, cy - 10 * s, cx + 11 * s, cy - 4 * s], outline=W, width=w - 1)
    elif name == "slurry":
        d.polygon([(cx, cy - 16 * s), (cx - 11 * s, cy + 2 * s), (cx + 11 * s, cy + 2 * s)], fill=W)
        d.ellipse([cx - 11 * s, cy - 8 * s, cx + 11 * s, cy + 14 * s], fill=W)
    elif name == "manure":
        d.pieslice([cx - 17 * s, cy - 8 * s, cx + 17 * s, cy + 26 * s], 180, 360, fill=W)
    elif name == "power":
        d.polygon([(cx + 3 * s, cy - 17 * s), (cx - 10 * s, cy + 2 * s), (cx - 1 * s, cy + 2 * s), (cx - 4 * s, cy + 17 * s),
                   (cx + 10 * s, cy - 3 * s), (cx + 1 * s, cy - 3 * s)], fill=W)
    elif name == "bulk":
        d.line([cx, cy + 17 * s, cx, cy - 15 * s], fill=W, width=w)
        for k in range(4):
            y = cy + (-10 + k * 7) * s
            d.ellipse([cx - 10 * s, y - 3 * s, cx - 1 * s, y + 3 * s], fill=W)
            d.ellipse([cx + 1 * s, y - 3 * s, cx + 10 * s, y + 3 * s], fill=W)
    elif name == "pallet":
        d.rectangle([cx - 13 * s, cy - 15 * s, cx + 13 * s, cy + 5 * s], outline=W, width=w)
        d.line([cx - 17 * s, cy + 9 * s, cx + 17 * s, cy + 9 * s], fill=W, width=w)
        for x in (cx - 15 * s, cx, cx + 15 * s):
            d.line([x, cy + 9 * s, x, cy + 15 * s], fill=W, width=w)
    elif name == "farm":
        d.polygon([(cx - 15 * s, cy - 2 * s), (cx, cy - 15 * s), (cx + 15 * s, cy - 2 * s)], fill=W)
        d.rectangle([cx - 12 * s, cy - 2 * s, cx + 12 * s, cy + 14 * s], fill=W)
        d.rectangle([cx - 4 * s, cy + 4 * s, cx + 4 * s, cy + 14 * s], fill=(0, 0, 0, 0))
    elif name == "depot":
        d.rounded_rectangle([cx - 15 * s, cy - 12 * s, cx - 3 * s, cy + 15 * s], 4 * s, fill=W)
        d.rectangle([cx + 1 * s, cy - 2 * s, cx + 16 * s, cy + 15 * s], fill=W)
    elif name == "arrow":
        d.line([cx - 5 * s, cy - 11 * s, cx + 6 * s, cy, cx - 5 * s, cy + 11 * s], fill=W, width=w + 1)
    elif name == "pencil":
        d.line([cx - 9 * s, cy + 9 * s, cx + 8 * s, cy - 8 * s], fill=W, width=w + 2)
        d.polygon([(cx - 12 * s, cy + 12 * s), (cx - 11 * s, cy + 5 * s), (cx - 5 * s, cy + 11 * s)], fill=W)
    elif name == "drop":
        d.line([cx - 10 * s, cy - 5 * s, cx, cy + 5 * s, cx + 10 * s, cy - 5 * s], fill=W, width=w + 1)

big = Image.new("RGBA", (512 * S, 512 * S), (0, 0, 0, 0))
d = ImageDraw.Draw(big)
for i, name in enumerate(NAMES):
    col, row = i % 8, i // 8
    draw(d, name, col * CELL + CELL // 2, row * CELL + CELL // 2, S * (1.0 if name in ("solid", "tile", "pill") else 1.15))
big.resize((512, 512), Image.LANCZOS).save(sys.argv[1])
print("cells:", NAMES)
