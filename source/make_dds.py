"""Converts the depot texture sets (make_textures.py output) to DDS for the game, plus the derived maps the
i3d uses: painted-steel colour maps pre-tinted per part (same tints as the previews), a lighter concrete for
sills/lintels, and the yellow/black bollard stripes. Full mip chain (Pillow writes only the top level, so levels
are joined under one header - the same way as the mod icon). Release sizes: at most 1024 px (the textures tile
every 1-2 m, so that is ~500 px per metre); colour and specular maps DXT1 (no alpha), normal maps DXT5.

Usage: python -I make_dds.py <texSrcDir> <outTexDir>
"""
import io
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

SRC, OUT = Path(sys.argv[1]), Path(sys.argv[2])
OUT.mkdir(parents=True, exist_ok=True)


def to_dds(image, out, max_size=1024, fmt="DXT1"):
    image = image.convert("RGBA")
    if image.width > max_size:
        image = image.resize((max_size, max_size), Image.LANCZOS)
    levels, size = [], image.size
    while True:
        level = image if size == image.size else image.resize(size, Image.LANCZOS)
        buf = io.BytesIO()
        level.save(buf, "DDS", pixel_format=fmt)
        levels.append(buf.getvalue())
        if size == (1, 1):
            break
        size = (max(1, size[0] // 2), max(1, size[1] // 2))
    header = bytearray(levels[0][:128])
    struct.pack_into("<I", header, 8, struct.unpack_from("<I", header, 8)[0] | 0x20000)
    struct.pack_into("<I", header, 28, len(levels))
    struct.pack_into("<I", header, 108, struct.unpack_from("<I", header, 108)[0] | 0x400008)
    with open(out, "wb") as f:
        f.write(header)
        for data in levels:
            f.write(data[128:])


def lin(a):
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def srgb(a):
    a = np.clip(a, 0, 1)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * a ** (1 / 2.4) - 0.055)


def tinted(png, tint, size=None):
    im = Image.open(png).convert("RGB")
    if size:
        im = im.resize((size, size), Image.LANCZOS)
    a = np.asarray(im).astype(float) / 255
    out = srgb(lin(a) * np.array(tint)[None, None, :])
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8))


count = 0
for png in sorted(SRC.glob("uwm*.png")):
    to_dds(Image.open(png), OUT / (png.stem + ".dds"), 1024, "DXT5" if png.stem.endswith("_normal") else "DXT1")
    count += 1

TINTS = {"GalvSmall": (0.72, 0.73, 0.74), "SteelDark": (0.14, 0.15, 0.15), "Frame": (0.2, 0.21, 0.21),
         "DoorGreen": (0.24, 0.32, 0.28), "Fascia": (0.16, 0.11, 0.08), "White": (1.0, 1.0, 0.98),
         "Yellow": (1.0, 0.72, 0.05), "Red": (0.75, 0.05, 0.03)}
for name, tint in TINTS.items():
    to_dds(tinted(SRC / "uwmPaintedSteel_diffuse.png", tint, 1024), OUT / f"uwmPaintedSteel_diffuse{name}.dds", 1024)
    count += 1
to_dds(tinted(SRC / "uwmConcrete_diffuse.png", (1.18, 1.18, 1.16)), OUT / "uwmConcrete_diffuseLight.dds")
count += 1

# bollard stripes: v goes up the bollard; top half yellow, bottom half black, a little wear
N = 512
y = (np.arange(N) + 0.5)[:, None] / N * np.ones((1, N))
rng = np.random.default_rng(5)
wear = np.clip(rng.normal(0, 1, (N, N)) * 0.04, -0.1, 0.1)
yellow, black = np.array([0.86, 0.62, 0.03]), np.array([0.03, 0.03, 0.03])     # sRGB values
col = np.clip(np.where((y < 0.5)[..., None], yellow, black) * (1 + wear[..., None]), 0, 1)
to_dds(Image.fromarray((col * 255 + 0.5).astype(np.uint8)), OUT / "uwmHazard_diffuse.dds", 512)
count += 1
print(f"wrote {count} dds files to {OUT}")
