"""Utilities & Waste Management depot - look v2, made from scratch in Blender.
Our two buildings (open steel slurry tank, small brick office with hip roof + antenna) next to the space the
BASE-GAME UNIA Farma 400 (silos + dryer, used as it is, user 2026-10-23) takes up: 14 x 7 m + 6 x 7 m, from its
i3d test areas. Renders preview views; nothing is exported to the mod.
Run: blender -b -P depot_blockout.py -- <outDir> <tag>
Units: meters. Blender Z is up (the game's Y)."""
import math
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, TAG = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


# ---------------------------------------------------------------- materials
def mat(name, color, rough=0.5, metal=0.0, setup=None):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if setup:
        setup(nt, bsdf)
    return m


def corrugated(scale):
    def setup(nt, bsdf):
        tc = nt.nodes.new("ShaderNodeTexCoord")
        wave = nt.nodes.new("ShaderNodeTexWave")
        wave.wave_type = "BANDS"
        wave.bands_direction = "Z"
        wave.inputs["Scale"].default_value = scale
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.6
        nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
        nt.links.new(wave.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return setup


def bricks(nt, bsdf):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.inputs["Color1"].default_value = (0.36, 0.09, 0.05, 1)
    brick.inputs["Color2"].default_value = (0.45, 0.13, 0.07, 1)
    brick.inputs["Mortar"].default_value = (0.55, 0.52, 0.48, 1)
    brick.inputs["Scale"].default_value = 1.0
    brick.inputs["Brick Width"].default_value = 0.25
    brick.inputs["Row Height"].default_value = 0.075
    brick.inputs["Mortar Size"].default_value = 0.01
    mapping = nt.nodes.new("ShaderNodeMapping")
    nt.links.new(tc.outputs["Object"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], brick.inputs["Vector"])
    nt.links.new(brick.outputs["Color"], bsdf.inputs["Base Color"])


def tiles(nt, bsdf):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.bands_direction = "X"
    wave.inputs["Scale"].default_value = 6
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.5
    nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
    nt.links.new(wave.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])


M = {
    "ground": mat("ground", (0.12, 0.11, 0.10), 0.95),
    "concrete": mat("concrete", (0.42, 0.41, 0.39), 0.9),
    "steelFlat": mat("steelFlat", (0.50, 0.50, 0.49), 0.45, 0.8),
    "steelCorr": mat("steelCorr", (0.55, 0.55, 0.53), 0.35, 0.9, corrugated(9.0)),
    "steelDark": mat("steelDark", (0.28, 0.29, 0.29), 0.5, 0.7),
    "galv": mat("galv", (0.62, 0.62, 0.60), 0.35, 0.9),
    "brick": mat("brick", (0.40, 0.11, 0.06), 0.8, 0.0, bricks),
    "roof": mat("roof", (0.33, 0.07, 0.03), 0.6, 0.0, tiles),
    "door": mat("door", (0.55, 0.56, 0.55), 0.5, 0.3),
    "window": mat("window", (0.05, 0.12, 0.08), 0.2),
    "yellow": mat("yellow", (0.85, 0.60, 0.02), 0.5),
    "slurry": mat("slurry", (0.10, 0.07, 0.03), 0.15),
    "fan": mat("fan", (0.06, 0.06, 0.08), 0.4, 0.5),
    "sign": mat("sign", (0.95, 0.95, 0.93), 0.6),
    "grate": mat("grate", (0.30, 0.30, 0.28), 0.6, 0.7),
}


def assign(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)
    return obj


def cylinder(name, r, h, loc, material, verts=48, cap=True):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=(loc[0], loc[1], loc[2] + h / 2),
                                        end_fill_type="NGON" if cap else "NOTHING")
    o = bpy.context.object
    o.name = name
    return assign(o, material)


def box(name, size, loc, material, rot_z=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(loc[0], loc[1], loc[2] + size[2] / 2))
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.rotation_euler[2] = rot_z
    return assign(o, material)


def cone(name, r, h, loc, material, verts=48):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=0.35, depth=h, location=(loc[0], loc[1], loc[2] + h / 2))
    o = bpy.context.object
    o.name = name
    return assign(o, material)


def tube_between(name, a, b, r, material):
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=r, depth=d.length, location=(a + b) / 2)
    o = bpy.context.object
    o.name = name
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    return assign(o, material)


def railing(name, center, r, z, material, posts=16):
    bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=0.03, location=(center[0], center[1], z + 1.0))
    assign(bpy.context.object, material)
    for i in range(posts):
        a = 2 * math.pi * i / posts
        p = (center[0] + r * math.cos(a), center[1] + r * math.sin(a))
        cylinder(f"{name}_post{i}", 0.025, 1.0, (p[0], p[1], z), material, verts=6)


def ladder(name, x, y, z0, z1, facing, material):
    # two rails + rungs, standing just outside a wall, facing = angle of the wall normal
    nx, ny = math.cos(facing), math.sin(facing)
    tx, ty = -ny, nx
    for side in (-0.22, 0.22):
        tube_between(f"{name}_rail", (x + tx * side, y + ty * side, z0), (x + tx * side, y + ty * side, z1), 0.025, material)
    z = z0 + 0.3
    while z < z1:
        tube_between(f"{name}_rung", (x - tx * 0.22, y - ty * 0.22, z), (x + tx * 0.22, y + ty * 0.22, z), 0.015, material)
        z += 0.3


# ---------------------------------------------------------------- the yard
bpy.ops.mesh.primitive_plane_add(size=120, location=(8, -2, 0))
assign(bpy.context.object, M["ground"]).name = "ground"
box("yardSlab", (30, 26, 0.06), (6, -2, 0), M["concrete"])

# 1. open steel slurry tank (flat panels, ring bands, seams), ~13 m across, 5.5 m high
T = (0.0, 2.0)
TR, TH = 6.5, 5.5
cylinder("tankFooting", TR + 0.25, 0.25, (T[0], T[1], 0.06), M["concrete"], verts=64)
bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=TR, depth=TH, location=(T[0], T[1], 0.3 + TH / 2), end_fill_type="NOTHING")
wall = assign(bpy.context.object, M["steelFlat"])
wall.name = "tankWall"
mod = wall.modifiers.new("thickness", "SOLIDIFY")
mod.thickness = 0.12
cylinder("tankSlurry", TR - 0.15, 0.3 + TH * 0.55, (T[0], T[1], 0.0), M["slurry"], verts=64)
for i in range(1, 5):
    bpy.ops.mesh.primitive_torus_add(major_radius=TR + 0.04, minor_radius=0.05, major_segments=64,
                                     location=(T[0], T[1], 0.3 + TH * i / 4.6))
    assign(bpy.context.object, M["galv"]).name = f"tankRing{i}"
for i in range(16):
    a = 2 * math.pi * i / 16
    box(f"tankSeam{i}", (0.06, 0.12, TH), (T[0] + (TR + 0.03) * math.cos(a), T[1] + (TR + 0.03) * math.sin(a), 0.3), M["galv"], a)
ladder("tankLadder", T[0] + (TR + 0.3) * math.cos(-0.6), T[1] + (TR + 0.3) * math.sin(-0.6), 0.3, TH + 1.3, -0.6, M["galv"])
tube_between("tankPipe", (T[0] + (TR + 0.2) * math.cos(0.2), T[1] + (TR + 0.2) * math.sin(0.2), 0.3),
             (T[0] + (TR + 0.2) * math.cos(0.2), T[1] + (TR + 0.2) * math.sin(0.2), TH + 1.0), 0.1, M["steelDark"])
pump = (T[0] + (TR + 0.9) * math.cos(-0.25), T[1] + (TR + 0.9) * math.sin(-0.25))
box("tankPumpPad", (1.6, 1.2, 0.15), (pump[0], pump[1], 0.06), M["concrete"], -0.25)
cylinder("tankPump", 0.25, 0.8, (pump[0], pump[1], 0.2), M["steelDark"], verts=16)
for s in (-1.1, 1.1):
    cylinder("bollard", 0.1, 1.1, (pump[0] + s * math.sin(0.25), pump[1] + s * math.cos(0.25), 0.06), M["yellow"], verts=12)
box("tankSign", (0.02, 2.2, 0.7), (T[0] + TR + 0.08, T[1] - 1.5, 3.4), M["sign"])

# 2. the base-game Farma 400 goes here (not drawn): its footprint from farma400.i3d test areas, game x/z ->
#    Blender x/-y: block x -7..7, z -7..0 and strip x -3..3, z 0..7, here turned so the strip points away from the tank
F = (13.0, 0.0)
FT = mat("farmaArea", (0.06, 0.06, 0.06), 0.95)
OUTLINE = mat("farmaLine", (0.95, 0.75, 0.05), 0.5)
box("farmaBlock", (7.0, 14.0, 0.08), (F[0] - 3.5, F[1], 0.06), FT)
box("farmaStrip", (7.0, 6.0, 0.08), (F[0] + 3.5, F[1], 0.06), FT)
for (cx, cy, w, h) in ((F[0] - 3.5, F[1], 7.0, 14.0), (F[0] + 3.5, F[1], 7.0, 6.0)):
    for (ox, oy, sw, sh) in ((0, h / 2, w, 0.12), (0, -h / 2, w, 0.12), (w / 2, 0, 0.12, h), (-w / 2, 0, 0.12, h)):
        box("farmaEdge", (sw, sh, 0.1), (cx + ox, cy + oy, 0.08), OUTLINE)
bpy.ops.object.text_add(location=(F[0] - 6.6, F[1] - 0.6, 0.2))
label = bpy.context.object
label.data.body = "FARMA 400\n(base game)"
label.data.size = 1.5
assign(label, OUTLINE)

# 3. small brick office, hip roof, antenna (the "office" of the depot)
H = (1.5, -9.5)
box("officeFooting", (4.4, 4.4, 0.25), (H[0], H[1], 0.06), M["concrete"])
box("officeWalls", (4.0, 4.0, 3.0), (H[0], H[1], 0.3), M["brick"])
bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=3.3, radius2=0.0, depth=1.8, location=(H[0], H[1], 3.3 + 0.9),
                                rotation=(0, 0, math.pi / 4))
assign(bpy.context.object, M["roof"]).name = "officeRoof"
box("officeDoor", (1.0, 0.04, 2.1), (H[0] + 0.8, H[1] - 2.02, 0.3), M["door"])
box("officeWindow", (0.04, 0.6, 1.0), (H[0] + 2.02, H[1] + 0.5, 1.4), M["window"])
box("officeWindow2", (0.04, 0.6, 1.0), (H[0] - 2.02, H[1] - 0.5, 1.4), M["window"])
tube_between("antennaMast", (H[0], H[1], 5.0), (H[0], H[1], 6.6), 0.04, M["steelDark"])
cylinder("antennaDish", 0.25, 0.15, (H[0], H[1], 6.5), M["yellow"], verts=16)

# ---------------------------------------------------------------- light, sky, cameras
world = bpy.data.worlds.new("sky")
scene.world = world
world.use_nodes = True
sky = world.node_tree.nodes.new("ShaderNodeTexSky")
world.node_tree.links.new(sky.outputs["Color"], world.node_tree.nodes["Background"].inputs["Color"])
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.25
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 2.2
sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
scene.collection.objects.link(sun)

scene.render.engine = "CYCLES"
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = 1400, 900
scene.view_settings.view_transform = "AgX"
scene.view_settings.exposure = -0.6


def shoot(name, loc, target, lens=28):
    cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
    cam.data.lens = lens
    scene.collection.objects.link(cam)
    cam.location = loc
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = f"{OUT}/depot_{TAG}_{name}.png"
    bpy.ops.render.render(write_still=True)


shoot("front", (4, -30, 3.0), (5, -2, 3))
shoot("side", (-20, -18, 5), (5, -2, 3))
shoot("office", (-3, -19, 2.2), (1.5, -9.5, 2.2), lens=35)
shoot("top", (6, -14, 34), (6, -2, 0), lens=30)
