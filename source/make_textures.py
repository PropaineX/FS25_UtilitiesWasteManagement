"""Our own tiling texture sets for the depot's tank and office (FS25 format), made from scratch with numpy.

Each set: <name>_diffuse.png (sRGB colour), <name>_normal.png (tangent space, OpenGL / green = up, as the game's own
normal maps measured on bricksGeneric_normal), <name>_specular.png (R = smoothness, G = baked AO, B = metalness, as
read from the game's buildingShader: float3(1 - roughness, bakedAO, metalness)).
Noise is built in frequency space, so every texture wraps seamlessly.

Usage: python -I make_textures.py <outDir> [size]      (size default 2048)
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.spatial import cKDTree

OUT = Path(sys.argv[1])
N = int(sys.argv[2]) if len(sys.argv) > 2 else 2048
OUT.mkdir(parents=True, exist_ok=True)
RNG = np.random.default_rng(20261024)


# ------------------------------------------------------------------ helpers
def noise(scale_px, octaves=4, persistence=0.5, aspect=(1.0, 1.0)):
    """Tileable fractal noise in 0..1. scale_px = size of the biggest blobs; aspect stretches (x, y)."""
    out = np.zeros((N, N))
    amp, total = 1.0, 0.0
    fy = np.fft.fftfreq(N)[:, None] * aspect[1]
    fx = np.fft.fftfreq(N)[None, :] * aspect[0]
    f = np.sqrt(fx ** 2 + fy ** 2)
    for o in range(octaves):
        s = scale_px / (2 ** o)
        filt = np.exp(-(f * s) ** 2 * 4.0)
        white = RNG.standard_normal((N, N))
        layer = np.real(np.fft.ifft2(np.fft.fft2(white) * filt))
        layer = (layer - layer.mean()) / (layer.std() + 1e-9)
        out += layer * amp
        total += amp
        amp *= persistence
    out /= total
    return np.clip(0.5 + out * 0.18, 0, 1)


def cells(n_cells, seed):
    """Tileable cell pattern: per-pixel random value of its cell (0..1) and distance to the cell border (px)."""
    rnd = np.random.default_rng(seed)
    pts = rnd.uniform(0, N, (n_cells, 2))
    tree = cKDTree(pts, boxsize=N)
    yy, xx = np.mgrid[0:N, 0:N]
    d, i = tree.query(np.stack([yy.ravel() + 0.5, xx.ravel() + 0.5], -1), k=2)
    val = rnd.uniform(0, 1, n_cells)[i[:, 0]].reshape(N, N)
    border = ((d[:, 1] - d[:, 0]) * 0.5).reshape(N, N)
    return val, border


def blur(a, px):
    fy = np.fft.fftfreq(N)[:, None]
    fx = np.fft.fftfreq(N)[None, :]
    filt = np.exp(-(fx ** 2 + fy ** 2) * (np.pi * px) ** 2 * 2)
    return np.real(np.fft.ifft2(np.fft.fft2(a) * filt))


def normal_from_height(h, strength):
    """height (0..1, higher = closer to the viewer) -> OpenGL normal map (green = up = towards row 0)."""
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5     # +rows = down the image
    nx, ny, nz = -dx * strength, dy * strength, np.ones_like(h)
    ln = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    return np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5


def ao_from_height(h, radius_px):
    return np.clip(1.0 - (blur(h, radius_px) - h) * 6.0, 0.35, 1.0)


def save(name, diffuse, height, strength, smooth, metal, ao_radius=6):
    to8 = lambda a: (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(to8(diffuse)).save(OUT / f"{name}_diffuse.png")
    Image.fromarray(to8(normal_from_height(height, strength))).save(OUT / f"{name}_normal.png")
    ao = ao_from_height(height, ao_radius)
    spec = np.stack([smooth, ao, metal if np.ndim(metal) else np.full_like(smooth, metal)], -1)
    Image.fromarray(to8(spec)).save(OUT / f"{name}_specular.png")
    print("wrote", name)


def srgb(rgb):
    return np.array(rgb, dtype=float)[None, None, :] / 255.0


def grid_cells(cols, rows, offset_odd_rows):
    """Per pixel: cell index (row, col), and position inside the cell (u, v in 0..1), for brick-like bonds."""
    y = (np.arange(N) + 0.5)[:, None] / N * rows
    x = (np.arange(N) + 0.5)[None, :] / N * cols
    r = np.floor(y).astype(int)
    xo = x + (0.5 * (r % 2) if offset_odd_rows else 0.0)
    c = np.floor(xo).astype(int) % cols
    return r % rows, c, xo - np.floor(xo), y - np.floor(y)


# ------------------------------------------------------------------ brick (1.88 m tile: 8 x 22 bricks, 10 mm joints)
def brick():
    cols, rows = 8, 22
    r, c, u, v = grid_cells(cols, rows, True)
    tile_m = 1.88
    joint_u = 0.010 / (tile_m / cols)
    joint_v = 0.010 / (tile_m / rows)
    du = np.minimum(u, 1 - u) / joint_u
    dv = np.minimum(v, 1 - v) / joint_v
    edge = np.clip(np.minimum(du, dv) - 0.5, 0, 1)             # 0 in the joint, 1 on the brick face
    bevel = np.clip(np.minimum(du, dv) / 2.2, 0, 1) ** 0.5
    rnd = np.random.default_rng(7)
    shade = rnd.uniform(0.78, 1.15, (rows, cols))[r, c]
    hue = rnd.uniform(-0.06, 0.06, (rows, cols))[r, c]
    base = srgb((150, 62, 42)) * shade[..., None]
    base[..., 0] *= 1 + hue
    base[..., 2] *= 1 - hue
    grain = noise(10, 3)[..., None]
    speck = noise(1.5, 1)[..., None]
    soot = noise(220, 3)[..., None]
    face = base * (0.84 + 0.3 * grain) * (0.9 + 0.2 * speck) * (0.92 + 0.16 * soot)
    face *= (0.8 + 0.2 * bevel)[..., None]                    # edges a little darker
    chips = (noise(6, 2) > 0.80) & (edge > 0.5) & (bevel < 0.75)   # small chips, mostly on the edges
    face = np.where(chips[..., None], face * 0.78, face)
    mortar = srgb((168, 160, 146)) * (0.85 + 0.3 * noise(6, 2)[..., None])
    col = face * edge[..., None] + mortar * (1 - edge[..., None])
    height = 0.55 * bevel + 0.08 * grain[..., 0] - 0.12 * chips + 0.05 * noise(4, 2)
    smooth = 0.18 + 0.10 * grain[..., 0] * edge
    save("uwmBrick", col, height, 9.0, smooth, 0.0)


# ------------------------------------------------------------------ roof tiles (1.8 m tile: 6 x 8 clay tiles)
def roof():
    cols, rows = 6, 8
    r, c, u, v = grid_cells(cols, rows, True)
    rnd = np.random.default_rng(11)
    shade = rnd.uniform(0.82, 1.12, (rows, cols))[r, c]
    curve = np.sin(np.pi * u) ** 0.6                            # each tile is rounded across
    lap = np.clip((v - 0.08) / 0.92, 0, 1)                      # lower edge of the row above overlaps the top
    shadow = np.clip(v / 0.12, 0, 1)
    gap = np.clip(np.minimum(u, 1 - u) / 0.025, 0, 1)
    grain = noise(12, 3) * 0.6 + noise(2, 2) * 0.4
    col = srgb((158, 58, 34)) * shade[..., None] * (0.82 + 0.36 * grain[..., None])
    lip = np.clip(v / 0.2, 0, 1) ** 0.7                       # shadow cast by the row above
    rim = np.clip(1 - (1 - v) / 0.04, 0, 1)                   # light catches the bottom edge
    col *= (0.35 + 0.65 * lip)[..., None] * (0.45 + 0.55 * gap)[..., None]
    col *= (1 + 0.25 * rim * gap)[..., None]
    moss = np.clip((noise(60, 4) - 0.62) * 6, 0, 1) * (1 - shadow * 0.6)
    col = col * (1 - moss[..., None] * 0.7) + srgb((70, 78, 36)) * moss[..., None] * 0.7
    height = 0.35 * curve + 0.45 * lap * gap + 0.05 * grain
    smooth = 0.30 + 0.12 * grain - 0.15 * moss
    save("uwmRoofTiles", col, height, 7.0, smooth, 0.0)


# ------------------------------------------------------------------ galvanized tank panel (one 1.70 x 1.375 m panel)
def panel(name, grime):
    PW, PH = 1.70, 1.375
    y = (np.arange(N) + 0.5)[:, None] / N
    x = (np.arange(N) + 0.5)[None, :] / N
    cell_val, cell_border = cells(14000, 3)
    spangle = 0.65 * cell_val + 0.35 * noise(6, 2)          # galvanized crystals + fine grain
    flow = noise(90, 4, 0.55, aspect=(0.18, 1.0))               # streaks run down
    base = 0.60 + 0.12 * (spangle - 0.5) * 2 - 0.03 * np.clip(1 - cell_border / 1.5, 0, 1)
    col = np.repeat(base[..., None], 3, -1) * srgb((236, 238, 240)) / (236 / 255)
    streak = np.clip((flow - 0.5) * 3.0, 0, 1) * (0.25 + 0.6 * y)
    col *= (1 - 0.32 * streak)[..., None]
    col = col * (1 - 0.18 * streak[..., None]) + srgb((120, 96, 70)) * 0.18 * streak[..., None]
    # lap seams on all four edges with bolt heads every 100 mm
    seam = np.minimum(np.minimum(x, 1 - x) * PW, np.minimum(y, 1 - y) * PH)      # metres to the nearest edge
    seam_band = np.clip(1 - (seam - 0.02) / 0.012, 0, 1)
    bolts = np.zeros((N, N))
    pitch = 0.10
    bx = ((x * PW) % pitch) - pitch / 2
    by = ((y * PH) % pitch) - pitch / 2
    near_v = np.minimum(x, 1 - x) * PW
    near_h = np.minimum(y, 1 - y) * PH
    ring = np.zeros((N, N))
    disc = np.zeros((N, N))
    for d_edge, d_along in ((near_v, by), (near_h, bx)):
        rr = np.sqrt((d_edge - 0.025) ** 2 + d_along ** 2)
        bolts = np.maximum(bolts, np.clip(1 - rr / 0.013, 0, 1) ** 0.5)           # domed heads, 26 mm (height)
        disc = np.maximum(disc, np.clip((0.013 - rr) / 0.0015, 0, 1))             # solid head, crisp edge
        ring = np.maximum(ring, np.clip(1 - np.abs(rr - 0.0145) / 0.0025, 0, 1))  # washer shadow
    lap_line = np.clip(1 - np.abs(seam - 0.04) / 0.003, 0, 1)                    # edge of the overlapping sheet
    col *= (1 - 0.10 * seam_band - 0.35 * lap_line - 0.35 * ring)[..., None]
    light = 0.8 + 0.5 * (np.roll(bolts, 4, 0) - np.roll(bolts, -4, 0))           # dome lit from above
    head = srgb((150, 152, 150)) * np.clip(light, 0.5, 1.3)[..., None] * (0.9 + 0.2 * noise(3, 1))[..., None]
    col = col * (1 - disc[..., None]) + head * disc[..., None]
    # rust only runs DOWN from a few bolts (rows grow downwards), never on the head itself
    run = sum(np.roll(blur(bolts, 2), k, 0) for k in range(8, 60, 4)) / 13.0
    rust_under_bolts = np.clip(run * 2.2 - bolts * 3, 0, 1) * (noise(30, 2) > 0.55)
    col = col * (1 - 0.4 * rust_under_bolts[..., None]) + srgb((130, 70, 35)) * 0.4 * rust_under_bolts[..., None]
    if grime:
        g = np.clip((y - 0.35) / 0.65, 0, 1) ** 1.6 * (0.6 + 0.4 * noise(40, 4))
        splash = np.clip((noise(14, 3) - 0.55) * 4, 0, 1) * np.clip((y - 0.7) / 0.3, 0, 1)
        dirt = np.clip(g + 0.6 * splash, 0, 1)
        col = col * (1 - 0.65 * dirt[..., None]) + srgb((74, 62, 46)) * 0.65 * dirt[..., None]
    else:
        dirt = np.zeros((N, N))
    height = 0.6 * seam_band - 0.4 * lap_line + 1.2 * bolts - 0.3 * ring + 0.04 * spangle + 0.05 * noise(200, 3)
    smooth = 0.62 + 0.12 * (spangle - 0.5) - 0.25 * streak - 0.45 * dirt
    metal = np.clip(0.9 - 0.8 * dirt - 0.3 * streak, 0, 1)
    save(name, col, height, 6.0, smooth, metal)


# ------------------------------------------------------------------ concrete (2 m tile)
def concrete():
    pores = np.clip((noise(2, 1) - 0.80) * 8, 0, 1)
    blot = noise(260, 5, 0.55)
    grain = noise(8, 3)
    col = srgb((152, 149, 142)) * (0.8 + 0.4 * blot[..., None]) * (0.9 + 0.2 * grain[..., None])
    stains = np.clip((noise(120, 4) - 0.6) * 3, 0, 1)
    col *= (1 - 0.25 * stains)[..., None]
    crack_field = np.abs(noise(300, 5, 0.6) - 0.5)
    cracks = np.clip(1 - crack_field / 0.0025, 0, 1) * (noise(150, 3) > 0.62)
    col *= (1 - 0.28 * cracks - 0.3 * pores)[..., None]
    height = 0.1 * grain - 0.5 * pores - 0.6 * cracks + 0.05 * blot
    smooth = 0.12 + 0.08 * grain
    save("uwmConcrete", col, height, 5.0, smooth, 0.0)


# ------------------------------------------------------------------ painted steel (1 m tile, colour set in the shader)
def painted():
    peel = noise(5, 2)
    chips = np.clip((noise(9, 2) - 0.84) * 12, 0, 1)
    wear = noise(160, 4)
    grey = 0.78 + 0.08 * (peel - 0.5) + 0.12 * (wear - 0.5)
    col = np.repeat(grey[..., None], 3, -1)
    col = col * (1 - 0.6 * chips[..., None]) + srgb((150, 148, 144)) * 0.6 * chips[..., None]
    height = 0.04 * peel - 0.4 * chips
    smooth = 0.55 + 0.1 * peel - 0.25 * chips - 0.15 * (wear - 0.5)
    metal = 0.85 * chips
    save("uwmPaintedSteel", col, height, 4.0, smooth, metal)


brick()
roof()
panel("uwmTankPanel", grime=False)
panel("uwmTankPanelLow", grime=True)
concrete()
painted()
