"""Exports the depot tank, office, manure pit and decorative pallet pad to an i3d for FS25.

Builds the scene with depot_look_v9.py (render calls left out), drops the preview-only objects (ground, Farma 400
outline, cameras, light), turns curves/text into meshes with their modifiers applied, exports with the GIANTS
exporter, then rewrites the materials to the game's buildingShader with our own texture sets (colour, normal,
specular = smoothness / AO / metalness) - the same set-up the base-game Farma 400 uses with its own textures.

Run: blender -b -P export_depot.py -- <outDir> <texSrcDir>
     writes <outDir>/depot.i3d (+ .i3d.shapes); textures are expected in <outDir>/textures/*.dds (make_dds.py).
"""
import math
import os
import sys
import xml.etree.ElementTree as ET

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
OUT_DIR, TEX_SRC = os.path.abspath(args[0]), os.path.abspath(args[1])
HERE = os.path.dirname(os.path.abspath(__file__))

# 1. build the scene (same code as the previews, without rendering)
src = open(os.path.join(HERE, "depot_look_v9.py"), encoding="utf-8").read()
src = "\n".join(l for l in src.splitlines() if not l.startswith("shoot("))
sys.argv = [sys.argv[0], "--", OUT_DIR, "export", TEX_SRC]
g = {"__name__": "depot_build", "__file__": os.path.join(HERE, "depot_look_v9.py")}
exec(compile(src, "depot_look_v9.py", "exec"), g)

# 2. preview-only objects out
for ob in list(bpy.data.objects):
    if ob.type in ("CAMERA", "LIGHT") or ob.name.startswith(("ground", "farmaEdge")) or \
            (ob.type == "FONT" and "FARMA" in ob.data.body):
        bpy.data.objects.remove(ob, do_unlink=True)

# --- placeable structure -------------------------------------------------------------------------------------
# One root "depot" holding everything; collisions for our tank / pump pad / office (the Farma 400 brings its own);
# placement areas covering all three buildings. Blender (x, y) = game (x, -z).
# Union footprint in game coords: x -12.5..10.5, z -21.5..7.2 (Farma 400 x -7..7 z -7..7, tank centre z -14.5
# r 6.85, pump pad to x ~10.4, office x -12.25..-7.75 z -11..-6.5).
from mathutils import Matrix, Vector as V
BUILDING = {"i3D_static": True, "i3D_collision": True, "i3D_nonRenderable": True,
            "i3D_collisionFilterGroup": "0x1034", "i3D_collisionFilterMask": "0xfffffbff"}   # Farma 400 "collision"
TIP = dict(BUILDING, i3D_collisionFilterGroup="0x8", i3D_collisionFilterMask="0x1")         # Farma 400 "tipCollision"


def empty(name, loc, parent=None):
    o = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    if parent is not None:
        bpy.context.view_layer.update()
        o.parent = parent
        o.matrix_parent_inverse = parent.matrix_world.inverted()
    return o


def collider(name, mesh_op, props, parent):
    mesh_op()
    o = bpy.context.object
    o.name = name
    for k, v in props.items():
        o[k] = v
    bpy.context.view_layer.update()
    mw = o.matrix_world.copy()
    o.parent = parent
    o.matrix_world = mw
    return o


# every visual mesh: no physics of its own
for ob in bpy.data.objects:
    if ob.type == "MESH":
        ob["i3D_collision"] = False
        ob["i3D_static"] = False

depot = empty("depot", (0, 0, 0))
# the build script sets the tank root's location last and never updates the view layer after it: without this
# update its matrix_world is still identity and the tank lands on the depot origin (inside the Farma 400)
bpy.context.view_layer.update()
for name in ("office", "tank"):
    o = bpy.data.objects[name]
    mw = o.matrix_world.copy()
    o.parent = depot
    o.matrix_world = mw
cols = empty("collisions", (0, 0, 0), depot)
TANK_C = V((0.0, 14.5, 0.0))
for nm, props in (("tankCollision", BUILDING), ("tankTipCollision", TIP)):
    collider(nm, lambda: bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=6.85, depth=6.2,
                                                             location=TANK_C + V((0, 0, 3.1))), props, cols)
pad = TANK_C + V((8.3 * math.cos(math.radians(10)), 8.3 * math.sin(math.radians(10)), 0))
collider("pumpCollision", lambda: bpy.ops.mesh.primitive_cube_add(size=1, location=pad + V((0, 0, 0.75)),
                                                                   scale=(2.9, 2.8, 1.5)), BUILDING, cols)
OFFICE_C = V((-10.0, 8.75, 0.0))
for nm, props in (("officeCollision", BUILDING), ("officeTipCollision", TIP)):
    collider(nm, lambda: bpy.ops.mesh.primitive_cube_add(size=1, location=OFFICE_C + V((0, 0, 2.6)),
                                                         scale=(4.6, 4.6, 5.2)), props, cols)
# placement areas (game convention: start node with the end / width / height nodes as children)
areas = empty("areas", (0, 0, 0), depot)
X0, X1, ZN, ZF = -16.5, 15.5, 7.2, -21.5          # pit frontage and slurry loading lane included
def gp(x, z, y=0.0):
    return V((x, -z, y))                             # game (x, y, z) -> Blender
t0 = empty("testAreaStart", gp(X0, ZN), areas)
empty("testAreaEnd", gp(X1, ZF, 17.0), t0)
c0 = empty("clearAreaStart", gp(X0, ZF), areas)
empty("clearAreaWidth", gp(X1, ZF), c0)
empty("clearAreaHeight", gp(X0, ZN), c0)
l0 = empty("levelAreaStart", gp(X0, ZF), areas)
empty("levelAreaWidth", gp(X1, ZF), l0)
empty("levelAreaHeight", gp(X0, ZN), l0)
o0 = empty("tipOcclusionStart", gp(X0, ZN), areas)
empty("tipOcclusionEnd", gp(X1, ZF), o0)

# pickups and the office door (game coords). Trigger presets from GE's collisionMaskFlags.xml: FILL_TRIGGER
# (group TRIGGER, mask FILLABLE = a trailer's exactFillRootNode) and PLAYER_TRIGGER (mask PLAYER).
FILL_TRIGGER = {"i3D_static": True, "i3D_trigger": True, "i3D_collision": True, "i3D_nonRenderable": True,
                "i3D_collisionFilterGroup": "0x20000000", "i3D_collisionFilterMask": "0x40000000"}
PLAYER_TRIGGER = dict(FILL_TRIGGER, i3D_collisionFilterMask="0x100000")
trig = empty("triggers", (0, 0, 0), depot)


def trigger_box(name, centre, size, props):
    """centre and size in game (x, y, z)"""
    o = collider(name, lambda: bpy.ops.mesh.primitive_cube_add(size=1, location=gp(centre[0], centre[2], centre[1]),
                                                               scale=(size[0], size[2], size[1])), props, trig)
    # physics shapes get their size in the mesh, not as a node scale
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


# slurry: the tank's capped coupling (game x 9.68, y 1.3, z -15.6, facing +x); a tanker stands in the lane
# beside it, along z, past the bollards
trigger_box("slurryTrigger", (13.0, 1.75, -15.6), (5.0, 3.5, 14.0), FILL_TRIGGER)
empty("slurryDischarge", gp(9.8, -15.6, 1.3), trig)
empty("slurryMarker", gp(11.8, -15.6, 0.0), trig)
# manure: open/front (-x) end of the new pit, facing the same direction as the office door.
# A trailer stands across the entrance; the pickup is not attached to the Farma pipe anymore.
trigger_box("manureTrigger", (-16.0, 2.5, -17.175), (5.0, 5.0, 8.0), FILL_TRIGGER)
empty("manureDischarge", gp(-14.8, -17.175, 3.5), trig)
empty("manureMarker", gp(-16.0, -17.175, 0.0), trig)
# bulk (user, 2026-10-28: "available from the silo"): under the Farma 400's loading pipe on its +z side, where the
# 0.4 manure pickup was (x -7..7, z 3.5..7.5); a trailer drives along x under the pipe
trigger_box("siloTrigger", (0.0, 2.5, 5.5), (14.0, 5.0, 4.0), FILL_TRIGGER)
empty("siloDischarge", gp(0.0, 5.5, 4.5), trig)
empty("siloMarker", gp(0.0, 5.5, 0.0), trig)
# office door (door face at game x -12.1, z -8.05, opening to -x)
trigger_box("officeTrigger", (-13.3, 1.0, -8.05), (2.0, 2.0, 2.4), PLAYER_TRIGGER)
empty("officeMarker", gp(-13.3, -8.05, 0.0), trig)           # the shop-basket icon on the ground at the door
empty("mapPosition", gp(0.0, -6.0, 0.0), trig)

# Approved photo layout, 2026-10-26. In the photo, down = game -x and right = game +z.
# Tank centre (0,-14.5), radius 6.85. Pit back is tangent to its near edge; left wall
# aligns with the tank's far-left z edge. Right wall leaves 2 m to office z=-11.0.
pit = empty("manurePit", (0, 0, 0), depot)
pad_root = empty("palletArea", (0, 0, 0), depot)

def visual_box(name, centre, size, material, parent):
    o = g["box"](name, (size[0], size[2], size[1]), gp(centre[0], centre[2], centre[1]),
                 bpy.data.materials[material])
    g["box_uv"](o, 2.0)
    o["i3D_collision"] = False
    o["i3D_static"] = False
    bpy.context.view_layer.update()
    mw = o.matrix_world.copy()
    o.parent = parent
    o.matrix_world = mw
    return o

wall_h, wall_t = 1.8, 0.25
back_x, front_x, left_z, right_z = -7.2, -14.5, -21.35, -13.0
pit_width = right_z - left_z
pit_length = back_x - front_x
visual_box("manurePitFloor", ((front_x + back_x)/2, -0.09, (left_z + right_z)/2),
           (pit_length, 0.10, pit_width), "uwmConcrete", pit)
walls = [
    ("manurePitBack", (back_x, 0, (left_z + right_z)/2), (wall_t, wall_h, pit_width + wall_t)),
    ("manurePitLeft", ((front_x + back_x)/2, 0, left_z), (pit_length, wall_h, wall_t)),
    ("manurePitRight", ((front_x + back_x)/2, 0, right_z), (pit_length, wall_h, wall_t)),
]
for name, centre, size in walls:
    visual_box(name, centre, size, "uwmConcrete", pit)
    for suffix, props in (("Collision", BUILDING), ("TipCollision", TIP)):
        collider(name + suffix, lambda centre=centre, size=size: bpy.ops.mesh.primitive_cube_add(
            size=1, location=gp(centre[0], centre[2], centre[1] + size[1]/2),
            scale=(size[0], size[2], size[1])), props, cols)

# Pallet pad: paid pallets spawn here for the buyer (user, 2026-10-28; was decorative before). One spawn line per
# bay, along x through the bay's middle (bays are split along z by the yellow lines below).
px0, px1, pz0, pz1 = -14.5, -8.0, -4.5, 3.5
for n in range(3):
    bz = pz0 + 0.2 + (n + 0.5) * (pz1 - pz0 - 0.4) / 3
    empty("pallet%dStart" % (n + 1), gp(px0 + 0.4, bz, 0.1), trig)
    empty("pallet%dEnd" % (n + 1), gp(px1 - 0.4, bz, 0.1), trig)
visual_box("palletConcretePad", ((px0+px1)/2, -0.09, (pz0+pz1)/2),
           (px1-px0, 0.10, pz1-pz0), "uwmConcreteLight", pad_root)
line = 0.10
for n, x in enumerate((px0+0.2, px1-0.2)):
    visual_box("palletBoundaryX%d" % n, (x, 0.012, (pz0+pz1)/2),
               (line, 0.006, pz1-pz0-0.4), "uwmYellow", pad_root)
for n in range(4):
    z = pz0 + 0.2 + n*(pz1-pz0-0.4)/3
    visual_box("palletBayLine%d" % n, ((px0+px1)/2, 0.012, z),
               (px1-px0-0.4, 0.006, line), "uwmYellow", pad_root)

# bollard stripes: v runs up the bollard (0.4 m per yellow + black pair); tank ring bands get UVs too
for ob in bpy.data.objects:
    if ob.type == "MESH" and ob.data.materials:
        if ob.data.materials[0].name == "hazard":
            g["box_uv"](ob, 0.4)
        elif ob.data.materials[0].name == "galv":
            g["box_uv"](ob, 1.0)

# Bake collision dimensions into vertices, as required by static physics shapes.
for ob in list(bpy.data.objects):
    if ob.type == "MESH" and ob.get("i3D_collision", False):
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

# 3. curves / text -> meshes, modifiers applied
bpy.ops.object.select_all(action="DESELECT")
for ob in bpy.data.objects:
    if ob.type in ("MESH", "CURVE", "FONT"):
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
bpy.ops.object.convert(target="MESH")

# buildingShader needs a second UV set (TEXCOORD1, used for its dirt/moss mask): GE refused to draw the meshes
# without one ("Vertex attribute mismatch ... missing TEXCOORD1"). A copy of the first set is enough.
for ob in bpy.data.objects:
    if ob.type == "MESH" and ob.data.uv_layers and len(ob.data.uv_layers) < 2:
        ob.data.uv_layers.new(name="UVMap2", do_init=True)

# the exporter reads Principled Base Color; keep the procedural ones' colour sensible
FLAT = {"glass": (0.02, 0.035, 0.04), "lamp": (0.9, 0.85, 0.6), "slurry": (0.07, 0.05, 0.025),
        "signText": (0.03, 0.03, 0.03), "rubber": (0.02, 0.02, 0.02), "ridge": (0.22, 0.05, 0.025)}
for m in bpy.data.materials:
    if m.name in FLAT and m.use_nodes:
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*FLAT[m.name], 1)
# The exporter MERGES materials that look alike to it: same Principled Base Color (Box Truck lesson) and here
# also the same image texture (all tinted steels share one painted-steel image, both concretes one concrete
# image -> one material each). Our textured materials are rewritten after the export anyway, so strip their
# nodes down to a Principled with its own plain colour.
for i, m in enumerate(sorted(bpy.data.materials, key=lambda m: m.name)):
    if not m.use_nodes or m.name in FLAT or "Principled BSDF" not in m.node_tree.nodes:
        continue
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL"):
            nt.nodes.remove(n)
    nt.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.2 + 0.03 * i, 0.5, 0.31 + 0.017 * i, 1)

# 4. export
import addon_utils
addon_utils.enable("io_export_i3d", default_set=True)
from io_export_i3d import i3d_export
from io_export_i3d.dcc import dccBlender as d
import io_export_i3d.dcc as dccpkg
from io_export_i3d.util import logUtil

_vis = lambda n: bpy.data.objects[n].visible_get()      # background mode has no 3D view
d.isNodeVisible = _vis
dccpkg.isNodeVisible = _vis
OUT = os.path.join(OUT_DIR, "depot.i3d")
d.UISetAttrBool("i3D_exportUseSoftwareFileName", False)
d.UISetAttrBool("i3D_binaryFiles", True)
d.UISetAttrString("i3D_exportFileLocation", OUT)
i3d_export.I3DExportAll()
for t, msg in logUtil.ActionLog.message:
    if t != "INFO":
        print("EXPORT", t, msg)

# 5. materials -> buildingShader with our texture sets
TEX = "textures/"
SETS = {  # Blender material -> (diffuse, normal, specular)
    "uwmBrick": ("uwmBrick_diffuse", "uwmBrick_normal", "uwmBrick_specular"),
    "uwmRoofTiles": ("uwmRoofTiles_diffuse", "uwmRoofTiles_normal", "uwmRoofTiles_specular"),
    "uwmConcrete": ("uwmConcrete_diffuse", "uwmConcrete_normal", "uwmConcrete_specular"),
    "uwmConcreteLight": ("uwmConcrete_diffuseLight", "uwmConcrete_normal", "uwmConcrete_specular"),
    "uwmTankPanel": ("uwmTankPanel_diffuse", "uwmTankPanel_normal", "uwmTankPanel_specular"),
    "uwmTankPanelLow": ("uwmTankPanelLow_diffuse", "uwmTankPanelLow_normal", "uwmTankPanelLow_specular"),
    "hazard": ("uwmHazard_diffuse", "uwmPaintedSteel_normal", "uwmPaintedSteel_specular"),
}
for tint in ("GalvSmall", "SteelDark", "Frame", "DoorGreen", "Fascia", "White", "Yellow", "Red"):
    SETS["uwm" + tint] = ("uwmPaintedSteel_diffuse" + tint, "uwmPaintedSteel_normal", "uwmPaintedSteel_specular")
SETS["galv"] = SETS["uwmGalvSmall"]                     # tank lap bands, girder and rim

tree = ET.parse(OUT)
root = tree.getroot()
files = root.find("Files")
if files is None:
    files = ET.Element("Files")
    root.insert(list(root).index(root.find("Materials")), files)
next_id = max([int(f.get("fileId")) for f in files] + [0]) + 1
ids = {}


def fid(path):
    global next_id
    if path not in ids:
        ET.SubElement(files, "File", fileId=str(next_id), filename=path)
        ids[path] = str(next_id)
        next_id += 1
    return ids[path]


for m in root.find("Materials"):
    m.set("emissiveColor", "0 0 0 1") if m.get("emissiveColor") else None
    name = m.get("name")
    if name not in SETS:
        continue
    dif, nor, spe = SETS[name]
    for k in list(m.attrib):
        if k not in ("name", "materialId"):
            del m.attrib[k]
    for child in list(m):
        m.remove(child)
    m.set("customShaderId", fid("$data/shaders/buildingShader.xml"))
    ET.SubElement(m, "CustomParameter", name="dirtMossSmoothness", value="0.12 0.82")
    ET.SubElement(m, "Texture", fileId=fid(TEX + dif + ".dds"))
    ET.SubElement(m, "Normalmap", fileId=fid(TEX + nor + ".dds"))
    ET.SubElement(m, "Glossmap", fileId=fid(TEX + spe + ".dds"))
    print("MATERIAL", name, "-> buildingShader", dif)
# drop file entries the exporter made for the preview PNGs (absolute paths)
for f in list(files):
    if ":" in f.get("filename", "") and f.get("filename") not in ids:
        files.remove(f)
# an empty link node for the base-game Farma 400 at the depot origin, LAST child of depot. UWMDepot loads
# $data/placeables/unia/farma/farma400/farma400.i3d into it at runtime (nothing copied). NOT a ReferenceNode: GIANTS
# Editor resolves those, but the game loaded it with 0 children (first in-game test, 2026-10-24: no silo).
scene_el = root.find("Scene")
depot_tg = next(tg for tg in scene_el.iter("TransformGroup") if tg.get("name") == "depot")
max_node = max(int(n.get("nodeId")) for n in scene_el.iter() if n.get("nodeId"))
ET.SubElement(depot_tg, "TransformGroup", name="farma400", nodeId=str(max_node + 1))
tree.write(OUT, encoding="iso-8859-1", xml_declaration=True)
print("WROTE", OUT)
# i3dMapping paths for the placeable XML: root index ">" child indices (node elements only)
NODE_TAGS = {"TransformGroup", "Shape", "Light", "Camera", "Dynamic", "Audio", "ReferenceNode"}
MAPPED = {"testAreaStart", "testAreaEnd", "clearAreaStart", "clearAreaWidth", "clearAreaHeight", "levelAreaStart",
          "levelAreaWidth", "levelAreaHeight", "tipOcclusionStart", "tipOcclusionEnd", "farma400", "office", "tank",
          "triggers", "slurryTrigger", "slurryDischarge", "slurryMarker", "manureTrigger", "manureDischarge",
          "manureMarker", "siloTrigger", "siloDischarge", "siloMarker", "officeTrigger", "officeMarker", "mapPosition",
          "pallet1Start", "pallet1End", "pallet2Start", "pallet2End", "pallet3Start", "pallet3End"}


mapping_paths = {}

def walk(el, prefix):
    """prefix None = scene level ('0>'), 'n>' = children of a root node ('n>i'), else 'a>b|c'."""
    for i, c in enumerate(c for c in el if c.tag in NODE_TAGS):
        if prefix is None:
            path = f"{i}>"
        elif prefix.endswith(">"):
            path = f"{prefix}{i}"
        else:
            path = f"{prefix}|{i}"
        if c.get("name") in MAPPED:
            print("MAPPING", c.get("name"), path)
            mapping_paths[c.get("name")] = path
        walk(c, path)


walk(scene_el, None)

# Keep XML mappings valid when new visual roots change the exported child indices.
xml_path = os.path.join(OUT_DIR, "depot.xml")
if os.path.exists(xml_path):
    xml_tree = ET.parse(xml_path)
    for mapping in xml_tree.getroot().find("i3dMappings"):
        mapping.set("node", mapping_paths[mapping.get("id")])
    ET.indent(xml_tree, space="    ")
    xml_tree.write(xml_path, encoding="utf-8", xml_declaration=True)
