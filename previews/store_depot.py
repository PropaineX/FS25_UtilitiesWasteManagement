"""Shop picture for the Community Depot from a GIANTS Editor capture (GE_work/uwm/store_view1.png, made by
run_store.ps1): the flat editor background is keyed out, the building fitted into y 175-436 of a 512 px image
(the shop card's visible part, see the knowledge index) and lightened (gamma 0.75) to come closer to the base-game shop pictures.
The PRO EDITION banner goes on afterwards with _ProEditionBanner/add_banner.py <png> <png> 441.

Usage: python -I store_depot.py <capture.png> <out.png>
"""
import sys

import numpy as np
from PIL import Image

src = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(float)
h, w, _ = src.shape
# GE's viewport background: one flat grey, taken from the corners (the camera label sits bottom left)
bg = np.median(np.concatenate([src[:20, :20].reshape(-1, 3), src[:20, -20:].reshape(-1, 3), src[-20:, -20:].reshape(-1, 3)]), axis=0)
dist = np.abs(src - bg).max(axis=2)
alpha = np.clip((dist - 4) / 10, 0, 1)
alpha[h - 40:, :200] = 0                           # the "uwmCam" label
ys, xs = np.nonzero(alpha > 0.5)
y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1

rgb = (src / 255) ** 0.75                        # GE draws darker than the shop renders: lighten
rgba = np.dstack([rgb, alpha])[y0:y1, x0:x1]
img = Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA")

TOP, BOTTOM, SIDE = 175, 436, 12
scale = min((BOTTOM - TOP) / img.height, (512 - 2 * SIDE) / img.width)
img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
out = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
out.alpha_composite(img, ((512 - img.width) // 2, BOTTOM - img.height))
out.save(sys.argv[2])
print("bg", bg, "subject", (x0, y0, x1, y1), "->", img.size)
