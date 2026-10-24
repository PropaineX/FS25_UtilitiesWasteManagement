"""Icon v3 = approved v2 + a smaller PRO EDITION banner at the very top.
Usage: python -I icon_v3_banner.py <v2.png> <out.png> [scale] [top_y]"""
import importlib.util
import sys
from pathlib import Path

from PIL import Image

# the shared banner tool: MOD PROJECTS\Library\_ProEditionBanner (this file is in MOD PROJECTS\<mod>\previews)
BANNER_SCRIPT = Path(__file__).resolve().parents[2] / "Library" / "_ProEditionBanner" / "add_banner.py"
spec = importlib.util.spec_from_file_location("add_banner", BANNER_SCRIPT)
add_banner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(add_banner)

src, out = sys.argv[1], sys.argv[2]
scale = float(sys.argv[3]) if len(sys.argv) > 3 else 0.7
top = int(sys.argv[4]) if len(sys.argv) > 4 else 14

icon = Image.open(src).convert("RGBA")
banner = add_banner.make_banner(scale * icon.width / 512)
icon.alpha_composite(banner, ((icon.width - banner.width) // 2, round(top * icon.width / 512)))
icon.save(out)
print("Saved", out, "banner", banner.size)
