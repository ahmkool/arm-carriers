"""Builds the shuriken launcher, its shuriken and the kunai, and exports them to
assets/models/weapon/shuriken_launcher/.

Run: /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_shuriken_launcher.py

Three files:
- shuriken_launcher.glb: a long launch rail. The back carrier holds the pistol grip at Godot z = -2.0,
  the front carrier the foregrip at z = 1.2, both on the gun's right (+X) side, like the pulse rifle.
  A round launch deck at the front holds the loaded shuriken flat, so the top-down camera sees it.
- shuriken.glb: a four-bladed throwing star lying flat (in Godot's XZ plane), its blades along +-X and
  +-Z. Each blade has a slot cut along its middle where a kunai rides. The kunai are not part of it.
- kunai.glb: one kunai, tip along +Z, origin at its middle. The shuriken scene places four in the slots.

Godot axes: up is +Y, the launcher fires along +Z, and the origin sits at carry height.
Blender is Z-up, so every part is placed as (x, z_godot, y_godot) through `_v`.
Keep DECK_Z in step with the ShurikenMuzzle marker in src/weapon/shuriken_launcher.tscn, and the slot
radii in step with KUNAI_RADIUS in src/weapon/shuriken_launcher/shuriken.gd.
"""
import math
import os

import bmesh
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "models", "weapon", "shuriken_launcher")

DECK_Z = 3.0
DECK_Y = 0.22

# Shuriken, in metres from its centre.
HUB_RADIUS = 0.32
BLADE_ROOT_HALF = 0.34
BLADE_TIP = 1.15
BLADE_THICK = 0.09
SLOT_FROM = 0.3
SLOT_TO = 1.0
SLOT_HALF = 0.075

# Kunai: 0.75 m long, tip along +Z.
KUNAI_LENGTH = 0.75


def _v(x, y_up, z_fwd):
    # Godot (x, y, z) -> Blender (x, -z, y): the glTF exporter maps Blender -Y to Godot +Z.
    return (x, -z_fwd, y_up)


def _material(name, color, metallic, roughness, emission=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 3.0
    return mat


def _select_only(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def _finish(obj, mat, bevel):
    obj.data.materials.append(mat)
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
    _select_only(obj)
    bpy.ops.object.shade_auto_smooth(angle=math.radians(35))
    return obj


def box(center, size, mat, bevel=0.03, tilt_deg=0.0, yaw_deg=0.0):
    """`center` and `size` are Godot (x, y, z). `tilt_deg` pitches around X, `yaw_deg` turns around Y."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=_v(*center))
    obj = bpy.context.active_object
    obj.scale = (size[0], size[2], size[1])
    obj.rotation_euler = (math.radians(tilt_deg), 0.0, math.radians(yaw_deg))
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return _finish(obj, mat, bevel)


def disc(center, radius, height, mat, verts=32, bevel=0.015):
    """A cylinder standing up (Godot Y)."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=height, location=_v(*center))
    return _finish(bpy.context.active_object, mat, bevel)


def tube(center, radius, length, mat, verts=16, bevel=0.01):
    """A cylinder along the Godot Z axis."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=length, location=_v(*center))
    obj = bpy.context.active_object
    obj.rotation_euler = (math.radians(90), 0.0, 0.0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return _finish(obj, mat, bevel)


def prism(name, outline_xz, y_center, thickness, mat, bevel=0.0):
    """A flat slab from a Godot (x, z) outline, counter-clockwise seen from above."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bottom = [bm.verts.new(_v(x, y_center - thickness / 2.0, z)) for x, z in outline_xz]
    top = [bm.verts.new(_v(x, y_center + thickness / 2.0, z)) for x, z in outline_xz]
    count = len(outline_xz)
    bm.faces.new(top)
    bm.faces.new(list(reversed(bottom)))
    for i in range(count):
        j = (i + 1) % count
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    return _finish(obj, mat, bevel)


def cut(target, cutter):
    mod = target.modifiers.new("Cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    _select_only(target)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def join_all(name):
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    return obj


def export(name):
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, name + ".blend"))
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_DIR, name + ".glb"),
        export_format="GLB",
        use_selection=False,
        export_apply=True,
    )


def _rotate_xz(points, angle):
    c = math.cos(angle)
    s = math.sin(angle)
    return [(x * c + z * s, -x * s + z * c) for x, z in points]


def build_shuriken():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    steel = _material("Steel", (0.62, 0.64, 0.68), 0.9, 0.25)
    dark = _material("DarkSteel", (0.12, 0.12, 0.14), 0.8, 0.35)
    red = _material("Lacquer", (0.75, 0.08, 0.06), 0.1, 0.45)
    edge = _material("Edge", (0.95, 0.97, 1.0), 1.0, 0.1)

    # One blade along +Z: wide at the hub, swept a little to one side so the star reads as spinning.
    blade = [
        (-BLADE_ROOT_HALF, 0.0),
        (BLADE_ROOT_HALF, 0.0),
        (0.16, 0.7),
        (0.05, BLADE_TIP),
        (-0.22, 0.62),
    ]
    edge_strip = [(0.16, 0.7), (0.05, BLADE_TIP), (0.12, 0.72), (BLADE_ROOT_HALF + 0.02, 0.05)]
    slot = [(-SLOT_HALF, SLOT_FROM), (SLOT_HALF, SLOT_FROM), (SLOT_HALF, SLOT_TO), (-SLOT_HALF, SLOT_TO)]
    for i in range(4):
        angle = i * math.pi / 2.0
        b = prism("Blade%d" % i, _rotate_xz(blade, angle), 0.0, BLADE_THICK, steel, 0.01)
        cutter = prism("Slot%d" % i, _rotate_xz(slot, angle), 0.0, BLADE_THICK * 3.0, steel)
        cut(b, cutter)
        prism("Edge%d" % i, _rotate_xz(edge_strip, angle), 0.0, BLADE_THICK * 0.6, edge)
        # A red lacquer stripe along the blade's spine, beside the slot.
        stripe = [(-0.2, 0.18), (-0.11, 0.18), (-0.11, 0.55), (-0.17, 0.55)]
        prism("Stripe%d" % i, _rotate_xz(stripe, angle), BLADE_THICK / 2.0 + 0.004, 0.01, red)

    disc((0.0, 0.0, 0.0), HUB_RADIUS, BLADE_THICK * 1.6, dark, verts=24)
    disc((0.0, BLADE_THICK * 0.8 + 0.01, 0.0), HUB_RADIUS * 0.62, 0.04, red, verts=24)
    disc((0.0, BLADE_THICK * 0.8 + 0.035, 0.0), 0.08, 0.04, steel, verts=12)
    join_all("Shuriken")
    export("shuriken")


def build_kunai():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    steel = _material("KunaiSteel", (0.85, 0.87, 0.92), 1.0, 0.15)
    wrap = _material("Wrap", (0.8, 0.1, 0.08), 0.0, 0.7)
    dark = _material("KunaiDark", (0.1, 0.1, 0.12), 0.7, 0.4)

    half = KUNAI_LENGTH / 2.0
    # Leaf blade from the guard (z = -0.02) to the tip (z = half), a diamond in cross-section.
    leaf = [(0.0, half), (-0.075, 0.12), (-0.03, -0.02), (0.03, -0.02), (0.075, 0.12)]
    prism("Leaf", leaf, 0.0, 0.035, steel, 0.008)
    prism("Ridge", [(0.0, half - 0.04), (-0.012, 0.1), (0.012, 0.1)], 0.02, 0.008, dark)
    # Handle wrapped in red cord, then the ring at the pommel.
    tube((0.0, 0.0, -0.15), 0.026, 0.26, wrap, verts=10)
    for i in range(4):
        tube((0.0, 0.0, -0.06 - i * 0.06), 0.03, 0.012, dark, verts=10, bevel=0.0)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.055, minor_radius=0.013, location=_v(0.0, 0.0, -0.33))
    # Lying flat, so the camera looks through the ring.
    _finish(bpy.context.active_object, dark, 0.0)
    join_all("Kunai")
    export("kunai")


def build_launcher():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    body = _material("Body", (0.14, 0.11, 0.10), 0.3, 0.55)
    wood = _material("Wood", (0.45, 0.25, 0.12), 0.0, 0.7)
    lacquer = _material("Lacquer", (0.72, 0.09, 0.06), 0.1, 0.4)
    brass = _material("Brass", (0.85, 0.62, 0.22), 0.9, 0.3)
    glow = _material("Glow", (1.0, 0.55, 0.15), 0.0, 0.4, emission=(1.0, 0.45, 0.1))

    # Stock and shoulder pad.
    box((0.0, -0.05, -2.7), (0.38, 0.55, 0.9), wood, 0.05)
    box((0.0, -0.05, -3.12), (0.42, 0.62, 0.1), body, 0.02)

    # Long rail from the stock to the deck, with lacquered side plates.
    box((0.0, 0.0, -0.3), (0.5, 0.42, 4.0), body, 0.05)
    box((0.27, 0.05, -0.4), (0.04, 0.3, 3.0), lacquer, 0.01)
    box((-0.27, 0.05, -0.4), (0.04, 0.3, 3.0), lacquer, 0.01)
    for i in range(5):
        box((0.0, 0.24, -1.6 + i * 0.6), (0.56, 0.06, 0.08), brass, 0.0)

    # Pistol grip and trigger guard for the back carrier.
    box((0.0, -0.45, -1.95), (0.24, 0.6, 0.28), wood, 0.04, tilt_deg=-18)
    box((0.0, -0.28, -1.6), (0.16, 0.06, 0.42), body, 0.015)

    # Spring housing under the rail: what flings the star.
    tube((0.0, -0.3, -0.2), 0.2, 1.6, body)
    for i in range(6):
        tube((0.0, -0.3, -0.85 + i * 0.26), 0.22, 0.05, brass, bevel=0.0)

    # The front carrier's foregrip, and a lever beside it that releases the kunai.
    box((0.0, -0.45, 1.2), (0.22, 0.6, 0.24), wood, 0.04)
    box((0.3, 0.1, 1.2), (0.08, 0.36, 0.1), brass, 0.01, tilt_deg=20)

    # The launch deck: a round plate the shuriken lies on, a spindle up its middle and two clamps.
    box((0.0, 0.0, 2.0), (0.5, 0.36, 1.0), body, 0.04)
    disc((0.0, DECK_Y - 0.08, DECK_Z), 1.05, 0.08, body, verts=40)
    disc((0.0, DECK_Y - 0.03, DECK_Z), 0.98, 0.03, lacquer, verts=40)
    disc((0.0, DECK_Y + 0.04, DECK_Z), 0.07, 0.2, brass, verts=12)
    for side in (-1, 1):
        box((side * 1.02, DECK_Y, DECK_Z), (0.1, 0.2, 0.4), brass, 0.01)
    box((0.0, DECK_Y - 0.06, DECK_Z + 1.02), (0.5, 0.06, 0.1), glow, 0.0)
    join_all("ShurikenLauncher")
    export("shuriken_launcher")


build_shuriken()
build_kunai()
build_launcher()
