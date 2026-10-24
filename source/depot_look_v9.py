"""Utilities & Waste Management depot - look v9 (open gutters, connected downpipe), made from scratch in Blender.
v4 layout (user's savegame1, depot origin = base-game Farma 400 pivot; game (x, z) -> Blender (x, -z)):
tank at (0, -14.5) turned 90, office at (-10, -8.75) turned -90. The Farma 400 itself is only outlined.
v5 = the user's "more realistic" pass: real door/window openings with frames, lintels, sills, step, tiled roof
with ridges, fascia and gutters, wall lamp, meter box, GPS antenna; weathered galvanized tank with top girder,
caged ladder, platform, pipework, valve, pump and striped bollards.
Run: blender -b -P depot_look_v5.py -- <outDir> <tag>      Preview renders only, nothing goes into the mod."""
import math
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, TAG = argv[0], argv[1]
TEX = argv[2]   # folder with the uwm*_diffuse/_normal/_specular.png sets (source/textures)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


# ================================================================ materials
def new_mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    return m, nt, nt.nodes["Principled BSDF"]


def simple(name, color, rough=0.5, metal=0.0):
    m, nt, b = new_mat(name)
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def noise(nt, scale, detail=6.0, coord="Object", stretch=None):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    if stretch:
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = stretch
        nt.links.new(tc.outputs[coord], mp.inputs["Vector"])
        nt.links.new(mp.outputs["Vector"], n.inputs["Vector"])
    else:
        nt.links.new(tc.outputs[coord], n.inputs["Vector"])
    return n


def ramp(nt, fac_socket, stops):
    r = nt.nodes.new("ShaderNodeValToRGB")
    els = r.color_ramp.elements
    els[0].position, els[0].color = stops[0][0], (*stops[0][1], 1)
    els[1].position, els[1].color = stops[-1][0], (*stops[-1][1], 1)
    for pos, col in stops[1:-1]:
        e = els.new(pos)
        e.color = (*col, 1)
    nt.links.new(fac_socket, r.inputs["Fac"])
    return r


def wall_coords(nt):
    """(x + y, z) so 2D textures run along vertical walls (bricks, tile rows)."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    add = nt.nodes.new("ShaderNodeMath")
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["X"], add.inputs[0])
    nt.links.new(sep.outputs["Y"], add.inputs[1])
    nt.links.new(add.outputs["Value"], comb.inputs["X"])
    nt.links.new(sep.outputs["Z"], comb.inputs["Y"])
    return comb.outputs["Vector"]


def mat_brick():
    m, nt, b = new_mat("brick")
    br = nt.nodes.new("ShaderNodeTexBrick")
    br.offset = 0.5
    br.inputs["Color1"].default_value = (0.30, 0.075, 0.04, 1)
    br.inputs["Color2"].default_value = (0.42, 0.12, 0.06, 1)
    br.inputs["Mortar"].default_value = (0.42, 0.40, 0.36, 1)
    br.inputs["Scale"].default_value = 1.0
    br.inputs["Mortar Size"].default_value = 0.010
    br.inputs["Mortar Smooth"].default_value = 0.2
    br.inputs["Bias"].default_value = 0.0
    br.inputs["Brick Width"].default_value = 0.225
    br.inputs["Row Height"].default_value = 0.075
    nt.links.new(wall_coords(nt), br.inputs["Vector"])
    # per-brick shade + fine grit
    grit = noise(nt, 60.0)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 0.35
    nt.links.new(br.outputs["Color"], mix.inputs["A"])
    nt.links.new(grit.outputs["Color"], mix.inputs["B"])
    nt.links.new(mix.outputs["Result"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.85
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.8
    bump.inputs["Distance"].default_value = 0.01
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(br.outputs["Fac"], inv.inputs[1])
    nt.links.new(inv.outputs["Value"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def mat_tiles():
    m, nt, b = new_mat("roofTiles")
    br = nt.nodes.new("ShaderNodeTexBrick")       # tile courses: wide "bricks", narrow gaps
    br.offset = 0.5
    br.inputs["Color1"].default_value = (0.26, 0.06, 0.03, 1)
    br.inputs["Color2"].default_value = (0.33, 0.08, 0.035, 1)
    br.inputs["Mortar"].default_value = (0.10, 0.03, 0.02, 1)
    br.inputs["Brick Width"].default_value = 0.30
    br.inputs["Row Height"].default_value = 0.22
    br.inputs["Mortar Size"].default_value = 0.012
    nt.links.new(wall_coords(nt), br.inputs["Vector"])
    nt.links.new(br.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.6
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 1.0
    bump.inputs["Distance"].default_value = 0.02
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(br.outputs["Fac"], inv.inputs[1])
    nt.links.new(inv.outputs["Value"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def mat_galvanized(name, base=0.42):
    m, nt, b = new_mat(name)
    spangle = noise(nt, 3.0, 2.0)
    streak = noise(nt, 1.2, 3.0, stretch=(5.0, 5.0, 0.2))      # rain streaks run down the wall
    col = ramp(nt, spangle.outputs["Fac"], [(0.3, (base * 0.93,) * 3), (0.7, (base * 1.05,) * 3)])
    dirt = ramp(nt, streak.outputs["Fac"], [(0.5, (1, 1, 1)), (0.8, (0.78, 0.74, 0.68))])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(col.outputs["Color"], mix.inputs["A"])
    nt.links.new(dirt.outputs["Color"], mix.inputs["B"])
    # dirt at the base of the wall
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs["Vector"])
    low = ramp(nt, sep.outputs["Z"], [(0.3, (0.45, 0.39, 0.31)), (0.95, (1, 1, 1))])   # metres above ground
    mix2 = nt.nodes.new("ShaderNodeMix")
    mix2.data_type = "RGBA"
    mix2.blend_type = "MULTIPLY"
    mix2.inputs["Factor"].default_value = 1.0
    nt.links.new(mix.outputs["Result"], mix2.inputs["A"])
    nt.links.new(low.outputs["Color"], mix2.inputs["B"])
    nt.links.new(mix2.outputs["Result"], b.inputs["Base Color"])
    rough = ramp(nt, spangle.outputs["Fac"], [(0.3, (0.32,) * 3), (0.7, (0.55,) * 3)])
    nt.links.new(rough.outputs["Color"], b.inputs["Roughness"])
    b.inputs["Metallic"].default_value = 0.85
    return m


def mat_concrete(name="concrete", shade=0.40):
    m, nt, b = new_mat(name)
    n = noise(nt, 14.0, 8.0)
    c = ramp(nt, n.outputs["Fac"], [(0.3, (shade * 0.85, shade * 0.83, shade * 0.8)), (0.7, (shade * 1.1, shade * 1.08, shade * 1.03))])
    nt.links.new(c.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.92
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.15
    nt.links.new(n.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    return m


def mat_asphalt():
    m, nt, b = new_mat("asphalt")
    n = noise(nt, 40.0, 10.0)
    big = noise(nt, 0.4, 3.0)
    c = ramp(nt, n.outputs["Fac"], [(0.35, (0.035, 0.035, 0.035)), (0.65, (0.075, 0.073, 0.07))])
    w = ramp(nt, big.outputs["Fac"], [(0.4, (0.8, 0.8, 0.8)), (0.6, (1.15, 1.12, 1.08))])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(c.outputs["Color"], mix.inputs["A"])
    nt.links.new(w.outputs["Color"], mix.inputs["B"])
    nt.links.new(mix.outputs["Result"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.95
    return m


def mat_painted(name, color, rough=0.45):
    m, nt, b = new_mat(name)
    n = noise(nt, 25.0, 4.0)
    c = ramp(nt, n.outputs["Fac"], [(0.3, tuple(v * 0.9 for v in color)), (0.7, tuple(v * 1.05 for v in color))])
    nt.links.new(c.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = 0.2
    return m


def mat_glass():
    m, nt, b = new_mat("glass")
    b.inputs["Base Color"].default_value = (0.02, 0.035, 0.04, 1)
    b.inputs["Roughness"].default_value = 0.03
    b.inputs["Specular IOR Level"].default_value = 0.9
    return m


def mat_hazard():
    m, nt, b = new_mat("hazard")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    w = nt.nodes.new("ShaderNodeTexWave")
    w.bands_direction = "Z"
    w.inputs["Scale"].default_value = 2.2
    w.inputs["Distortion"].default_value = 0.0
    nt.links.new(tc.outputs["Object"], w.inputs["Vector"])
    r = ramp(nt, w.outputs["Fac"], [(0.49, (0.85, 0.62, 0.02)), (0.51, (0.02, 0.02, 0.02))])
    r.color_ramp.interpolation = "CONSTANT"
    nt.links.new(r.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.5
    return m


def mat_slurry():
    m, nt, b = new_mat("slurry")
    n = noise(nt, 3.0, 8.0)
    c = ramp(nt, n.outputs["Fac"], [(0.4, (0.045, 0.03, 0.015)), (0.62, (0.16, 0.12, 0.06))])
    nt.links.new(c.outputs["Color"], b.inputs["Base Color"])
    r = ramp(nt, n.outputs["Fac"], [(0.45, (0.12,) * 3), (0.62, (0.7,) * 3)])
    nt.links.new(r.outputs["Color"], b.inputs["Roughness"])
    return m


M = {
    "asphalt": mat_asphalt(),
    "concrete": mat_concrete(),
    "concreteLight": mat_concrete("concreteLight", 0.55),
    "brick": mat_brick(),
    "tiles": mat_tiles(),
    "ridge": simple("ridge", (0.22, 0.05, 0.025), 0.55),
    "galv": mat_galvanized("galv"),
    "galvLight": mat_galvanized("galvLight", 0.55),
    "steelDark": mat_painted("steelDark", (0.10, 0.11, 0.11), 0.5),
    "frame": mat_painted("frame", (0.16, 0.17, 0.17), 0.4),
    "door": mat_painted("door", (0.20, 0.25, 0.22), 0.45),
    "fascia": mat_painted("fascia", (0.12, 0.08, 0.06), 0.6),
    "gutter": mat_galvanized("gutter", 0.5),
    "glass": mat_glass(),
    "hazard": mat_hazard(),
    "slurry": mat_slurry(),
    "white": mat_painted("white", (0.80, 0.80, 0.78), 0.5),
    "yellow": mat_painted("yellow", (0.85, 0.6, 0.02), 0.5),
    "rubber": simple("rubber", (0.02, 0.02, 0.02), 0.8),
    "lamp": simple("lamp", (0.9, 0.85, 0.6), 0.2),
    "signRed": simple("signRed", (0.6, 0.03, 0.02), 0.5),
    "signText": simple("signText", (0.03, 0.03, 0.03), 0.6),
}


# ================================================================ geometry helpers
def assign(o, material):
    o.data.materials.clear()
    o.data.materials.append(material)
    return o


def apply_scale(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def box(name, size, loc, material, rot=(0, 0, 0)):
    """size (x, y, z), loc = bottom centre."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(loc[0], loc[1], loc[2] + size[2] / 2), rotation=rot)
    o = bpy.context.object
    o.name = name
    o.scale = size
    apply_scale(o)
    return assign(o, material)


def cyl(name, r, h, loc, material, verts=32, rot=(0, 0, 0), cap=True):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc, rotation=rot,
                                        end_fill_type="NGON" if cap else "NOTHING")
    o = bpy.context.object
    o.name = name
    return assign(o, material)


def tube(name, a, b, r, material, verts=12):
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=d.length, location=(a + b) / 2)
    o = bpy.context.object
    o.name = name
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    return assign(o, material)


def ring(name, R, r, z, material, center=(0, 0), seg=96, scale_z=1.0):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=seg, minor_segments=8,
                                     location=(center[0], center[1], z))
    o = bpy.context.object
    o.name = name
    o.scale[2] = scale_z
    apply_scale(o)
    return assign(o, material)


def bevel(o, width=0.01, segments=2):
    mod = o.modifiers.new("bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    return o


def cut(target, cutter):
    mod = target.modifiers.new("cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    bpy.ops.object.select_all(action="DESELECT")
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def group(name, objs, loc, rot_z):
    bpy.context.view_layer.update()
    root = bpy.data.objects.new(name, None)
    scene.collection.objects.link(root)
    for o in objs:
        o.parent = root
    root.location = (loc[0], loc[1], 0)
    root.rotation_euler[2] = rot_z
    return root


def collect(start_count):
    return list(scene.objects)[start_count:]


# ================================================================ yard
bpy.ops.mesh.primitive_plane_add(size=160, location=(-2, 6, 0))
assign(bpy.context.object, M["asphalt"]).name = "ground"

# Farma 400 space (base game, not drawn), from its test areas
OUT_M = simple("farmaLine", (0.95, 0.75, 0.05), 0.5)
for (cx, cy, w, h) in ((0, 3.5, 14.0, 7.0), (0, -3.5, 6.0, 7.0)):
    for (ox, oy, sw, sh) in ((0, h / 2, w, 0.15), (0, -h / 2, w, 0.15), (w / 2, 0, 0.15, h), (-w / 2, 0, 0.15, h)):
        box("farmaEdge", (sw, sh, 0.02), (cx + ox, cy + oy, 0.0), OUT_M)
bpy.ops.object.text_add(location=(-4.8, 2.6, 0.03))
label = bpy.context.object
label.data.body = "FARMA 400\n(base game)"
label.data.size = 1.4
assign(label, OUT_M)


# ================================================================ office (local: door wall faces -Y)
n0 = len(scene.objects)
W, D, WH, PL = 4.2, 4.2, 2.85, 0.30          # wall footprint, wall height above plinth, plinth height
plinth = bevel(box("officePlinth", (W + 0.16, D + 0.16, PL), (0, 0, 0), M["concrete"]), 0.02)
walls = box("officeWalls", (W, D, WH), (0, 0, PL), M["brick"])
inner = box("officeInside", (W - 0.5, D - 0.5, WH + 0.2), (0, 0, PL - 0.1), M["brick"])
cut(walls, inner)
DOOR_W, DOOR_H, DOOR_X = 1.0, 2.1, 0.7
WIN_W, WIN_H, WIN_Z = 1.0, 1.1, PL + 0.95
openings = [("door", (DOOR_X, -D / 2), (DOOR_W, 0.8, DOOR_H), PL),
            ("winR", (W / 2, 0.4), (0.8, WIN_W, WIN_H), WIN_Z),
            ("winL", (-W / 2, -0.4), (0.8, WIN_W, WIN_H), WIN_Z),
            ("winB", (0.0, D / 2), (WIN_W, 0.8, WIN_H), WIN_Z)]
for name, (ox, oy), size, z in openings:
    cut(walls, box("cut_" + name, size, (ox, oy, z), M["brick"]))

# door: steel frame, recessed leaf with panels, lever handle, step, lintel
fx, fy = DOOR_X, -D / 2
for (sx, sz, px, pz) in ((0.06, DOOR_H + 0.06, -DOOR_W / 2, 0), (0.06, DOOR_H + 0.06, DOOR_W / 2, 0), (DOOR_W + 0.12, 0.06, 0, DOOR_H)):
    box("doorFrame", (sx, 0.12, sz), (fx + px, fy, PL + pz), M["frame"])
leaf = bevel(box("doorLeaf", (DOOR_W - 0.06, 0.05, DOOR_H - 0.03), (fx, fy + 0.08, PL), M["door"]), 0.006)
for z in (0.55, 1.35):
    box("doorGroove", (DOOR_W - 0.3, 0.012, 0.012), (fx, fy + 0.05, PL + z), M["frame"])
box("doorKick", (DOOR_W - 0.12, 0.01, 0.22), (fx, fy + 0.052, PL + 0.04), M["galvLight"])
cyl("handleRose", 0.035, 0.02, (fx + DOOR_W / 2 - 0.12, fy + 0.045, PL + 1.05), M["galvLight"], 16, (math.pi / 2, 0, 0))
tube("handleLever", (fx + DOOR_W / 2 - 0.12, fy + 0.02, PL + 1.05), (fx + DOOR_W / 2 - 0.26, fy + 0.02, PL + 1.05), 0.012, M["galvLight"])
bevel(box("doorStep", (DOOR_W + 0.5, 0.45, PL - 0.05), (fx, fy - 0.3, 0), M["concreteLight"]), 0.015)
bevel(box("doorLintel", (DOOR_W + 0.4, 0.26, 0.16), (fx, fy + 0.12, PL + DOOR_H + 0.03), M["concreteLight"]), 0.01)
# wall lamp over the door + sign
box("lampBase", (0.18, 0.06, 0.18), (fx, fy - 0.03, PL + DOOR_H + 0.35), M["steelDark"])
cyl("lampGlass", 0.07, 0.12, (fx, fy - 0.12, PL + DOOR_H + 0.44), M["lamp"], 16, (math.pi / 2, 0, 0))
box("signPlate", (0.9, 0.02, 0.3), (fx - 1.6, fy - 0.01, PL + 1.6), M["white"])
box("signStripe", (0.9, 0.022, 0.04), (fx - 1.6, fy - 0.012, PL + 1.62), M["signRed"])
bpy.ops.object.text_add(location=(fx - 1.98, fy - 0.025, PL + 1.72), rotation=(math.pi / 2, 0, 0))
t = bpy.context.object
t.data.body = "DEPOT OFFICE"
t.data.size = 0.11
assign(t, M["signText"])

# windows: frame, centre bar, glass, sill, lintel
def window(cx, cy, normal):
    nx, ny = normal
    tx, ty = -ny, nx                        # along the wall
    rot = (0, 0, math.atan2(ny, nx) - math.pi / 2)
    face = (cx - nx * 0.06, cy - ny * 0.06)  # set back into the opening
    def piece(name, w, h, along, z, depth, material, out=0.0):
        box(name, (w, depth, h), (face[0] + tx * along + nx * out, face[1] + ty * along + ny * out, z), material, rot)
    piece("winFrameL", 0.07, WIN_H, -WIN_W / 2 + 0.035, WIN_Z, 0.09, M["frame"])
    piece("winFrameR", 0.07, WIN_H, WIN_W / 2 - 0.035, WIN_Z, 0.09, M["frame"])
    piece("winFrameB", WIN_W, 0.07, 0, WIN_Z, 0.09, M["frame"])
    piece("winFrameT", WIN_W, 0.07, 0, WIN_Z + WIN_H - 0.07, 0.09, M["frame"])
    piece("winBar", 0.05, WIN_H, 0, WIN_Z, 0.07, M["frame"])
    piece("winGlass", WIN_W - 0.1, WIN_H - 0.1, 0, WIN_Z + 0.05, 0.01, M["glass"], -0.01)
    sill = box("winSill", (WIN_W + 0.16, 0.22, 0.06), (cx + nx * 0.06, cy + ny * 0.06, WIN_Z - 0.07), M["concreteLight"], rot)
    bevel(sill, 0.008)
    box("winLintel", (WIN_W + 0.36, 0.25, 0.15), (cx - nx * 0.01, cy - ny * 0.01, WIN_Z + WIN_H), M["concreteLight"], rot)


window(W / 2, 0.4, (1, 0))
window(-W / 2, -0.4, (-1, 0))
window(0.0, D / 2, (0, 1))

# roof: hip roof with overhang, fascia, ridge caps, gutters, downpipe
EAVE = PL + WH
OV = 0.35
RW = W / 2 + OV
RH = 1.75
RR = RW + 0.08                                   # roof edge reaches over the gutter
bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=RR * math.sqrt(2), radius2=0.0, depth=RH,
                                location=(0, 0, EAVE + 0.12 + RH / 2), rotation=(0, 0, math.pi / 4))
roof = assign(bpy.context.object, M["tiles"])
roof.name = "roof"
mod = roof.modifiers.new("thickness", "SOLIDIFY")
mod.thickness = 0.08
apex = Vector((0, 0, EAVE + 0.12 + RH))
for sx, sy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
    tube("hipRidge", (sx * RR, sy * RR, EAVE + 0.16), apex + Vector((0, 0, 0.04)), 0.07, M["ridge"])
for (sx, sy, along) in ((0, -1, "x"), (0, 1, "x"), (-1, 0, "y"), (1, 0, "y")):
    size = (2 * RW + 0.04, 0.04, 0.18) if along == "x" else (0.04, 2 * RW + 0.04, 0.18)
    box("fascia", size, (sx * (RW + 0.01), sy * (RW + 0.01), EAVE - 0.02), M["fascia"])
box("soffit", (2 * RW, 2 * RW, 0.03), (0, 0, EAVE - 0.02), M["fascia"])

# gutters: one open half-round channel (125 mm) running round all four eaves with mitred corners, hung on the
# fascia, rim just under the roof edge so the water drops in
GR = 0.0625
GC = RW + 0.03 + GR                       # centre line: fascia face + radius
GZ = EAVE + 0.105                         # rim height (top of the open channel)
prof = bpy.data.curves.new("gutterProfile", "CURVE")
prof.dimensions = "2D"
sp = prof.splines.new("POLY")
arc = [math.radians(a) for a in range(180, 361, 15)]          # bottom half circle: open at the top
sp.points.add(len(arc) - 1)
for k, a in enumerate(arc):
    sp.points[k].co = (GR * math.cos(a), GR * math.sin(a), 0, 1)
prof_obj = bpy.data.objects.new("gutterProfile", prof)
scene.collection.objects.link(prof_obj)
path = bpy.data.curves.new("gutterPath", "CURVE")
path.dimensions = "3D"
path.bevel_mode = "OBJECT"
path.bevel_object = prof_obj
path.use_fill_caps = False
sp = path.splines.new("POLY")
corners = [(GC, -GC), (GC, GC), (-GC, GC), (-GC, -GC)]
sp.points.add(len(corners) - 1)
for k, (cx, cy) in enumerate(corners):
    sp.points[k].co = (cx, cy, GZ, 1)
sp.use_cyclic_u = True
gut = bpy.data.objects.new("gutter", path)
scene.collection.objects.link(gut)
bpy.ops.object.select_all(action="DESELECT")
gut.select_set(True)
bpy.context.view_layer.objects.active = gut
bpy.ops.object.convert(target="MESH")
gut = bpy.context.object
assign(gut, M["gutter"])
gut.modifiers.new("thickness", "SOLIDIFY").thickness = 0.004
bpy.data.objects.remove(prof_obj, do_unlink=True)
# wet silt along the bottom of the channel: shows that the gutter is open and holds water
for k in range(4):
    (ax, ay), (bx, by) = corners[k], corners[(k + 1) % 4]
    run = Vector((bx - ax, by - ay, 0))
    mid = Vector(((ax + bx) / 2, (ay + by) / 2, GZ - GR + 0.012))
    silt = box("gutterSilt", (run.length, 0.05, 0.006), mid, M["slurry"], (0, 0, math.atan2(run.y, run.x)))
# outlet at the front-right corner: stub out of the gutter bottom -> swan neck (two bends) back to the wall ->
# straight down the brick on brackets -> shoe turning out at the bottom
PR = 0.045
cx, cy = GC - 0.12, -GC                   # outlet just before the corner, on the front run
wx, wy = W / 2 - 0.12, -D / 2 - 0.07      # pipe line on the wall, near the corner
z_out = GZ - GR - 0.01
pts = [Vector((cx, cy, z_out + 0.04)),    # inside the gutter bottom (outlet stub)
       Vector((cx, cy, z_out - 0.12)),    # stub end
       Vector((wx, wy, z_out - 0.32)),    # swan neck, angled back to the wall
       Vector((wx, wy, z_out - 0.45)),    # straight down the wall
       Vector((wx, wy, PL + 0.18)),       # bottom bend
       Vector((wx, wy - 0.22, PL + 0.02))]  # shoe, turned out from the wall
names = ["outlet", "swanNeck", "downpipeTop", "downpipe", "downpipeShoe"]
for k in range(len(pts) - 1):
    tube(names[k], pts[k], pts[k + 1], PR, M["gutter"], 16)
for k in range(1, len(pts) - 1):           # bends: a ball joint where pipes meet, so nothing shows a gap
    bpy.ops.mesh.primitive_uv_sphere_add(radius=PR * 1.02, segments=16, ring_count=8, location=pts[k])
    assign(bpy.context.object, M["gutter"]).name = "pipeBend"
cyl("outletCollar", PR + 0.012, 0.03, (cx, cy, z_out - 0.005), M["gutter"], 16)
for zb in (EAVE - 0.9, PL + 1.3):          # wall brackets
    cyl("pipeBracket", PR + 0.008, 0.03, (wx, wy, zb), M["gutter"], 16)
    box("pipeBracketTab", (0.03, 0.07, 0.03), (wx, wy + 0.06, zb - 0.015), M["gutter"])
bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=PR + 0.004, depth=0.02, location=pts[-1])
o = assign(bpy.context.object, M["steelDark"])     # open end of the shoe (dark inside)
o.name = "shoeMouth"
o.rotation_euler = (pts[-1] - pts[-2]).to_track_quat("Z", "Y").to_euler()
box("splashBlock", (0.3, 0.45, 0.05), (wx, wy - 0.45, 0.0), M["concreteLight"])

# GPS antenna (like the RTK house), meter box with conduit
tube("mast", (0, 0, apex.z - 0.2), (0, 0, apex.z + 1.3), 0.035, M["galvLight"])
tube("mastArm", (0, 0, apex.z + 1.1), (0.35, 0, apex.z + 1.1), 0.02, M["galvLight"])
cyl("gpsPuck", 0.13, 0.08, (0, 0, apex.z + 1.36), M["white"], 24)
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0, 0, apex.z + 1.42))
o = assign(bpy.context.object, M["white"])
o.scale[2] = 0.45
cyl("radioAntenna", 0.012, 0.6, (0.35, 0, apex.z + 1.4), M["rubber"], 8)
bevel(box("meterBox", (0.5, 0.18, 0.65), (-W / 2 - 0.09, 1.2, PL + 0.9), M["galvLight"], (0, 0, math.pi / 2)), 0.01)
tube("conduit", (-W / 2 - 0.05, 1.2, PL + 0.9), (-W / 2 - 0.05, 1.2, PL), 0.025, M["steelDark"])
tube("conduitTop", (-W / 2 - 0.05, 1.2, PL + 1.55), (-W / 2 - 0.05, 1.2, EAVE - 0.05), 0.025, M["steelDark"])

office_root = group("office", collect(n0), (-10.0, 8.75), math.radians(-90))


# ================================================================ tank (open steel slurry tank)
n0 = len(scene.objects)
TR, TH, BASE = 6.5, 5.5, 0.30
bevel(cyl("tankFooting", TR + 0.35, BASE, (0, 0, BASE / 2), M["concrete"], 96), 0.03)
COURSE = TH / 4
for wname, z0, h in (("tankWallLow", BASE, COURSE), ("tankWall", BASE + COURSE, TH - COURSE)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=120, radius=TR, depth=h, location=(0, 0, z0 + h / 2), end_fill_type="NOTHING")
    w = assign(bpy.context.object, M["galv"])
    w.name = wname
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    w.modifiers.new("thickness", "SOLIDIFY").thickness = 0.1
cyl("tankSlurry", TR - 0.12, 0.05, (0, 0, BASE + TH * 0.72), M["slurry"], 96)
# panel courses: lap joints (slightly proud bands) + top wind girder
for i in range(1, 4):
    ring("tankLap", TR + 0.015, 0.035, BASE + TH * i / 4, M["galv"], scale_z=0.5)
ring("tankGirder", TR + 0.1, 0.12, BASE + TH - 0.08, M["galvLight"], scale_z=0.45)
ring("tankRim", TR, 0.05, BASE + TH, M["galvLight"])
# (vertical panel joints and bolts are in the panel texture now)

# caged ladder + top platform at angle LA
LA = math.radians(-35)
nx, ny = math.cos(LA), math.sin(LA)
tx, ty = -ny, nx
lx, ly = (TR + 0.35) * nx, (TR + 0.35) * ny
for s in (-0.25, 0.25):
    tube("ladderRail", (lx + tx * s, ly + ty * s, BASE), (lx + tx * s, ly + ty * s, BASE + TH + 1.1), 0.03, M["galvLight"])
z = BASE + 0.3
while z < BASE + TH:
    tube("ladderRung", (lx - tx * 0.25, ly - ty * 0.25, z), (lx + tx * 0.25, ly + ty * 0.25, z), 0.016, M["galvLight"])
    z += 0.3
z = BASE + 2.3
cage = []
while z < BASE + TH + 1.0:
    bpy.ops.mesh.primitive_torus_add(major_radius=0.38, minor_radius=0.018, location=(lx + nx * 0.3, ly + ny * 0.3, z))
    cage.append(assign(bpy.context.object, M["galvLight"]))
    z += 0.7
for k in range(5):
    a = LA + math.radians(-90 + 45 * k)
    px, py = lx + nx * 0.3 + 0.38 * math.cos(a), ly + ny * 0.3 + 0.38 * math.sin(a)
    tube("cageBar", (px, py, BASE + 2.3), (px, py, BASE + TH + 0.95), 0.014, M["galvLight"])
pz = BASE + TH + 0.05
box("platform", (1.1, 1.2, 0.06), (TR * nx + nx * 0.1, TR * ny + ny * 0.1, pz), M["galvLight"], (0, 0, LA))
for s in (-0.55, 0.55):
    px, py = (TR + 0.1) * nx + tx * s, (TR + 0.1) * ny + ty * s
    tube("platPost", (px, py, pz), (px, py, pz + 1.05), 0.025, M["galvLight"])
    tube("platRail", (px, py, pz + 1.05), (px - nx * 0.7, py - ny * 0.7, pz + 1.05), 0.025, M["galvLight"])

# pump station, built in the tank's local frame: radial direction PA, tangent along the wall
# suction nozzle (tank bottom) -> pump -> tee (fill pipe up the wall and over the rim) -> gate valve -> capped
# hose coupling on a pipe stand, where a tanker hooks up
PA = math.radians(-80)
RN = Vector((math.cos(PA), math.sin(PA), 0))
TN = Vector((-math.sin(PA), math.cos(PA), 0))


def P(r, s, z):
    """point at radius r, s metres along the wall, height z"""
    return RN * r + TN * s + Vector((0, 0, z))


PIPE = 0.085
ZS = BASE + 0.25                        # suction height: pump casing sits on its base frame (top 0.32)
pad_c = P(TR + 1.95, 0.0, 0.0)
bevel(box("pumpPad", (2.9, 2.8, 0.2), (pad_c.x, pad_c.y, 0), M["concreteLight"], (0, 0, PA)), 0.02)

# suction nozzle with flanges on the wall, pipe out to the pump
cyl("nozzleFlange", 0.16, 0.05, P(TR + 0.08, -0.6, ZS), M["steelDark"], 24, (0, math.pi / 2, PA))
tube("suction", P(TR + 0.05, -0.6, ZS), P(TR + 1.35, -0.6, ZS), PIPE, M["steelDark"], 16)
cyl("suctionFlange", 0.15, 0.04, P(TR + 0.7, -0.6, ZS), M["steelDark"], 24, (0, math.pi / 2, PA))

# pump: base frame, motor along the wall, volute casing in line with the suction pipe
base_c = P(TR + 1.62, -0.28, 0.2)
box("pumpBase", (0.62, 1.15, 0.12), (base_c.x, base_c.y, 0.2), M["steelDark"], (0, 0, PA))
for s in (-0.6, -0.1, 0.25):                         # feet under casing and motor
    f = P(TR + 1.62, s, 0)
    box("pumpFoot", (0.34, 0.08, 0.05), (f.x, f.y, 0.31), M["steelDark"], (0, 0, PA))
cyl("volute", 0.24, 0.22, P(TR + 1.5, -0.6, ZS), M["door"], 32, (0, math.pi / 2, PA))
cyl("voluteCover", 0.18, 0.04, P(TR + 1.62, -0.6, ZS), M["steelDark"], 32, (0, math.pi / 2, PA))
motor = cyl("motor", 0.2, 0.62, P(TR + 1.75, 0.05, ZS), M["door"], 32, (math.pi / 2, 0, PA))
for k in range(8):                                     # cooling fins
    a = 2 * math.pi * k / 8
    off = Vector((0, 0, 0.2 * math.cos(a))) + RN * (0.2 * math.sin(a))
    c = P(TR + 1.75, 0.05, ZS) + off
    box("motorFin", (0.02, 0.5, 0.03), (c.x, c.y, c.z - 0.015), M["door"], (0, 0, PA))
cyl("motorFan", 0.17, 0.08, P(TR + 1.75, 0.4, ZS), M["steelDark"], 24, (math.pi / 2, 0, PA))
box("terminalBox", (0.16, 0.16, 0.12), (P(TR + 1.75, 0.0, 0).x, P(TR + 1.75, 0.0, 0).y, ZS + 0.18), M["door"], (0, 0, PA))
tube("couplingShaft", P(TR + 1.6, -0.6, ZS), P(TR + 1.75, -0.25, ZS), 0.04, M["galvLight"])

# discharge: up out of the volute, along to the tee, valve and coupling
d0 = P(TR + 1.5, -0.6, ZS + 0.24)
d1 = P(TR + 1.5, -0.6, BASE + 1.0)
tube("discharge", d0, d1, PIPE, M["steelDark"], 16)
cyl("elbow", PIPE * 1.15, PIPE * 2.3, d1, M["steelDark"], 16)
tee = P(TR + 2.2, -0.6, BASE + 1.0)
tube("dischargeRun", d1, tee, PIPE, M["steelDark"], 16)
cyl("tee", PIPE * 1.2, PIPE * 2.6, tee, M["steelDark"], 16, (math.pi / 2, 0, PA))

# fill branch from the tee back to the wall, up and over the rim
w0 = P(TR + 0.22, -0.6, BASE + 1.0)
tube("fillBranch", tee, w0, PIPE, M["steelDark"], 16)
tube("fillRiser", w0, P(TR + 0.22, -0.6, BASE + TH + 0.35), PIPE, M["steelDark"], 16)
tube("fillOver", P(TR + 0.22, -0.6, BASE + TH + 0.35), P(TR - 0.7, -0.6, BASE + TH + 0.35), PIPE, M["steelDark"], 16)
tube("fillDown", P(TR - 0.7, -0.6, BASE + TH + 0.35), P(TR - 0.7, -0.6, BASE + TH - 0.4), PIPE, M["steelDark"], 16)
for zz in (BASE + 2.0, BASE + 3.6, BASE + 5.0):        # wall brackets
    box("pipeBracket", (0.24, 0.06, 0.05), (P(TR + 0.1, -0.6, 0).x, P(TR + 0.1, -0.6, 0).y, zz), M["galvLight"], (0, 0, PA + math.pi / 2))
    cyl("pipeClamp", PIPE + 0.02, 0.05, P(TR + 0.22, -0.6, zz), M["galvLight"], 16)

# gate valve in the outlet run: body, bonnet, stem, handwheel on the stem
v = P(TR + 2.6, -0.6, BASE + 1.0)
tube("outletA", tee, P(TR + 2.48, -0.6, BASE + 1.0), PIPE, M["steelDark"], 16)
cyl("valveBody", 0.13, 0.26, v, M["door"], 24, (0, math.pi / 2, PA))
for s in (-0.13, 0.13):
    cyl("valveFlange", 0.16, 0.035, v + RN * s, M["door"], 24, (0, math.pi / 2, PA))
cyl("valveBonnet", 0.08, 0.22, v + Vector((0, 0, 0.2)), M["door"], 16)
cyl("valveStem", 0.018, 0.3, v + Vector((0, 0, 0.42)), M["galvLight"], 12)
wheel_c = v + Vector((0, 0, 0.56))
bpy.ops.mesh.primitive_torus_add(major_radius=0.17, minor_radius=0.018, location=wheel_c)
assign(bpy.context.object, M["signRed"]).name = "handwheel"
for k in range(3):
    a = 2 * math.pi * k / 3
    tube("wheelSpoke", wheel_c, wheel_c + Vector((0.17 * math.cos(a), 0.17 * math.sin(a), 0)), 0.012, M["signRed"])
cyl("wheelHub", 0.035, 0.05, wheel_c, M["signRed"], 12)

# outlet with camlock-style coupling and a chained cap, on a pipe stand
tube("outletB", P(TR + 2.72, -0.6, BASE + 1.0), P(TR + 3.15, -0.6, BASE + 1.0), PIPE, M["steelDark"], 16)
cyl("coupling", 0.11, 0.16, P(TR + 3.22, -0.6, BASE + 1.0), M["galvLight"], 24, (0, math.pi / 2, PA))
cyl("couplingCap", 0.115, 0.06, P(TR + 3.33, -0.6, BASE + 1.0), M["yellow"], 24, (0, math.pi / 2, PA))
for s in (-1, 1):
    tube("camLever", P(TR + 3.2, -0.6 + s * 0.11, BASE + 1.0), P(TR + 3.05, -0.6 + s * 0.13, BASE + 0.85), 0.012, M["galvLight"])
stand = P(TR + 2.95, -0.6, 0)
tube("pipeStand", stand + Vector((0, 0, 0.2)), stand + Vector((0, 0, BASE + 0.9)), 0.04, M["galvLight"])
box("pipeStandFoot", (0.2, 0.2, 0.02), (stand.x, stand.y, 0.2), M["galvLight"], (0, 0, PA))
tube("pipeSaddle", P(TR + 2.95, -0.72, BASE + 0.9), P(TR + 2.95, -0.48, BASE + 0.9), 0.02, M["galvLight"])

# striped bollards guarding the pump from trucks
for s in (-1.2, 1.2):
    b = P(TR + 3.0, s, 0)                               # these stand on the pad
    cyl("bollard", 0.09, 1.1, (b.x, b.y, 0.75), M["hazard"], 20)
    cyl("bollardCap", 0.095, 0.03, (b.x, b.y, 1.31), M["yellow"], 20)

# sign plate on the wall
SA = math.radians(-115)
sx, sy = (TR + 0.06) * math.cos(SA), (TR + 0.06) * math.sin(SA)
box("tankSign", (2.4, 0.02, 0.8), (sx, sy, BASE + 3.2), M["white"], (0, 0, SA + math.pi / 2))
box("tankSignStripe", (2.0, 0.024, 0.06), (sx, sy, BASE + 3.32), M["signRed"], (0, 0, SA + math.pi / 2))
bpy.ops.object.text_add(location=(0, 0, 0))
t = bpy.context.object
t.data.body = "COMMUNITY DEPOT"
t.data.size = 0.22
t.data.align_x = "CENTER"
t.rotation_euler = (math.pi / 2, 0, SA + math.pi / 2)
t.location = (sx + math.cos(SA) * 0.02, sy + math.sin(SA) * 0.02, BASE + 3.42)
assign(t, M["signText"])

tank_root = group("tank", collect(n0), (0.0, 14.5), math.radians(90))


# ================================================================ texture pass: our own texture sets + UVs
import bmesh


def image_mat(name, tex, tint=(1, 1, 1), metal_scale=1.0):
    """Principled material reading a uwm texture set the way the game does: colour x tint, normal (OpenGL),
    specular R = smoothness, G = AO (multiplied into colour), B = metalness."""
    m, nt, b = new_mat(name)
    def img(suffix, colorspace):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(f"{TEX}/{tex}_{suffix}.png", check_existing=True)
        n.image.colorspace_settings.name = colorspace
        return n
    dif, nor, spe = img("diffuse", "sRGB"), img("normal", "Non-Color"), img("specular", "Non-Color")
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(spe.outputs["Color"], sep.inputs["Color"])
    tint_mix = nt.nodes.new("ShaderNodeMix")
    tint_mix.data_type = "RGBA"
    tint_mix.blend_type = "MULTIPLY"
    tint_mix.inputs["Factor"].default_value = 1.0
    tint_mix.inputs["B"].default_value = (*tint, 1)
    nt.links.new(dif.outputs["Color"], tint_mix.inputs["A"])
    ao_mix = nt.nodes.new("ShaderNodeMix")
    ao_mix.data_type = "RGBA"
    ao_mix.blend_type = "MULTIPLY"
    ao_mix.inputs["Factor"].default_value = 1.0
    nt.links.new(tint_mix.outputs["Result"], ao_mix.inputs["A"])
    nt.links.new(sep.outputs["Green"], ao_mix.inputs["B"])
    nt.links.new(ao_mix.outputs["Result"], b.inputs["Base Color"])
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(sep.outputs["Red"], inv.inputs[1])
    nt.links.new(inv.outputs["Value"], b.inputs["Roughness"])
    ms = nt.nodes.new("ShaderNodeMath")
    ms.operation = "MULTIPLY"
    ms.inputs[1].default_value = metal_scale
    nt.links.new(sep.outputs["Blue"], ms.inputs[0])
    nt.links.new(ms.outputs["Value"], b.inputs["Metallic"])
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nor.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    return m


T = {
    "brick": (image_mat("uwmBrick", "uwmBrick"), 1.88),
    "roof": (image_mat("uwmRoofTiles", "uwmRoofTiles"), 1.80),
    "concrete": (image_mat("uwmConcrete", "uwmConcrete"), 2.0),
    "concreteLight": (image_mat("uwmConcreteLight", "uwmConcrete", (1.18, 1.18, 1.16)), 2.0),
    "panel": (image_mat("uwmTankPanel", "uwmTankPanel"), None),
    "panelLow": (image_mat("uwmTankPanelLow", "uwmTankPanelLow"), None),
    "galvSmall": (image_mat("uwmGalvSmall", "uwmPaintedSteel", (0.72, 0.73, 0.74), 1.0), 1.0),
    "steelDark": (image_mat("uwmSteelDark", "uwmPaintedSteel", (0.14, 0.15, 0.15)), 1.0),
    "frame": (image_mat("uwmFrame", "uwmPaintedSteel", (0.2, 0.21, 0.21)), 1.0),
    "door": (image_mat("uwmDoorGreen", "uwmPaintedSteel", (0.24, 0.32, 0.28)), 1.0),
    "fascia": (image_mat("uwmFascia", "uwmPaintedSteel", (0.16, 0.11, 0.08)), 1.0),
    "white": (image_mat("uwmWhite", "uwmPaintedSteel", (1.0, 1.0, 0.98)), 1.0),
    "yellow": (image_mat("uwmYellow", "uwmPaintedSteel", (1.0, 0.72, 0.05)), 1.0),
    "red": (image_mat("uwmRed", "uwmPaintedSteel", (0.75, 0.05, 0.03)), 1.0),
}
REMAP = {"brick": "brick", "concrete": "concrete", "concreteLight": "concreteLight", "galvLight": "galvSmall",
         "gutter": "galvSmall", "steelDark": "steelDark", "frame": "frame", "door": "door", "fascia": "fascia",
         "white": "white", "yellow": "yellow", "signRed": "red"}


def mesh_objects():
    return [o for o in scene.objects if o.type == "MESH" and o.data.materials]


def box_uv(o, size):
    """Planar UVs in metres / tile size, picked per face from its normal (like a cube projection)."""
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in f.loops:
            co = loop.vert.co
            if ax == 2:
                loop[uv].uv = (co.x / size, co.y / size)
            elif ax == 0:
                loop[uv].uv = (co.y / size * (1 if n.x > 0 else -1), co.z / size)
            else:
                loop[uv].uv = (co.x / size * (-1 if n.y > 0 else 1), co.z / size)
    bm.to_mesh(me)
    bm.free()


def cylinder_panel_uv(o, z0, course_h, panels=24):
    """Tank wall: one texture per 1.7 x 1.375 m panel - u = panels around, v = courses up."""
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        fc = f.calc_center_median()
        fa = math.atan2(fc.y, fc.x)
        for loop in f.loops:
            co = loop.vert.co
            a = math.atan2(co.y, co.x)
            if a - fa > math.pi:
                a -= 2 * math.pi
            elif fa - a > math.pi:
                a += 2 * math.pi
            loop[uv].uv = (a / (2 * math.pi) * panels, (co.z - z0) / course_h)
    bm.to_mesh(me)
    bm.free()


def roof_uv(o, size):
    """Each roof slope: u along the eave, v up the slope, so tile rows lie level."""
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        horiz = Vector((n.x, n.y, 0))
        if horiz.length < 1e-4:
            for loop in f.loops:
                loop[uv].uv = (loop.vert.co.x / size, loop.vert.co.y / size)
            continue
        along = Vector((-n.y, n.x, 0)).normalized()
        up = n.cross(along).normalized()
        if up.z < 0:
            up = -up
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = (co.dot(along) / size, co.dot(up) / size)
    bm.to_mesh(me)
    bm.free()


for o in mesh_objects():
    old = o.data.materials[0].name
    if o.name in ("tankWall", "tankWallLow"):
        key = "panelLow" if o.name == "tankWallLow" else "panel"
        z0 = BASE if key == "panelLow" else BASE + COURSE
        cylinder_panel_uv(o, z0, COURSE)
    elif old == "roofTiles":
        key = "roof"
        roof_uv(o, T[key][1])
    elif old in REMAP:
        key = REMAP[old]
        box_uv(o, T[key][1])
    else:
        continue
    o.data.materials[0] = T[key][0]

# ================================================================ light, sky, cameras
world = bpy.data.worlds.new("sky")
scene.world = world
world.use_nodes = True
sky = world.node_tree.nodes.new("ShaderNodeTexSky")
world.node_tree.links.new(sky.outputs["Color"], world.node_tree.nodes["Background"].inputs["Color"])
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.22
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 2.6
sun.data.angle = math.radians(1.5)
sun.data.color = (1.0, 0.93, 0.82)
sun.rotation_euler = (math.radians(58), 0, math.radians(-40))
scene.collection.objects.link(sun)

scene.render.engine = "CYCLES"
scene.cycles.samples = 160
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = 1920, 1200
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Medium High Contrast"
scene.view_settings.exposure = -0.4


def shoot(name, loc, target, lens=35):
    cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
    cam.data.lens = lens
    scene.collection.objects.link(cam)
    cam.location = loc
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = f"{OUT}/depot_{TAG}_{name}.png"
    bpy.ops.render.render(write_still=True)


# office door wall faces -Y locally; turned -90 it faces -X in the yard
# office turned -90: local +x (outlet side) faces world -y; local -y (door) faces world -x
# shoot("officeCorner", (-15.5, 2.8, 2.6), (-10.0, 8.75, 2.4), lens=32)
# shoot("gutterCorner", (-13.6, 4.4, 2.9), (-11.9, 6.9, 2.4), lens=35)
# shoot("gutterTop", (-14.6, 3.6, 6.2), (-11.9, 6.6, 3.3), lens=32)
# shoot("gutterInside", (-13.5, 5.3, 4.1), (-12.55, 6.25, 3.05), lens=40)
shoot("gutterOutlet", (-13.25, 5.75, 3.95), (-12.66, 6.22, 3.12), lens=45)
