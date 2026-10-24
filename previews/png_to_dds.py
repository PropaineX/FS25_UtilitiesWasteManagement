"""PNG -> DXT5 .dds with a full mip chain (Pillow writes only the top level; levels are joined under one header).
Usage: python -I png_to_dds.py <in.png> <out.dds>"""
import io
import struct
import sys

from PIL import Image

src, out = sys.argv[1], sys.argv[2]
image = Image.open(src).convert("RGBA")

levels = []
size = image.size
while True:
    level = image.resize(size, Image.LANCZOS) if size != image.size else image
    buffer = io.BytesIO()
    level.save(buffer, "DDS", pixel_format="DXT5")
    levels.append(buffer.getvalue())
    if size == (1, 1):
        break
    size = (max(1, size[0] // 2), max(1, size[1] // 2))

header = bytearray(levels[0][:128])
flags = struct.unpack_from("<I", header, 8)[0] | 0x20000                       # DDSD_MIPMAPCOUNT
struct.pack_into("<I", header, 8, flags)
struct.pack_into("<I", header, 28, len(levels))                               # mip count
caps = struct.unpack_from("<I", header, 108)[0] | 0x400008                    # COMPLEX | MIPMAP
struct.pack_into("<I", header, 108, caps)

with open(out, "wb") as f:
    f.write(header)
    for data in levels:
        f.write(data[128:])

check = Image.open(out)
print(out, check.size, "mips", len(levels))
