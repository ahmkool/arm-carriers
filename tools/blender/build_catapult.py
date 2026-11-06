"""Builds the carried catapult and its bomb, exported to assets/models/weapon/catapult/.

Run: /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_catapult.py

Godot axes: the catapult throws along +Z, up is +Y, and the origin sits at carry height.
Blender is Z-up, so every part below is placed as (x, z_godot, y_godot) through `_v`.

The glb holds separate nodes that `catapult_specifics.gd` moves on its own:
- Frame: the base, uprights, stop bar and the back carrier's handles (around Godot z = -2.4).
- Arm: origin on the axle. At rest it points straight back (-Z); rotating it around X
  swings the cup up and over towards the front.
- FrontPole: one metre long from its origin along +Z, scaled to reach the front carrier.
- FrontGrip: the front carrier's crossbar, moved to the end of the pole.
The bomb is its own glb, centred on its origin.
"""
import math
import os

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "models", "weapon", "catapult")

## Must match ARM_PIVOT in src/weapon/catapult/catapult_specifics.gd.
ARM_PIVOT = (0.0, 0.55, 0.15)
ARM_LENGTH = 2.3
FRAME_FRONT_Z = 1.15


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
        bsdf.inputs["Emission Strength"].default_value = 6.0
    return mat


def _finish(obj, mat, bevel):
    obj.data.materials.append(mat)
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_auto_smooth(angle=math.radians(35))
    return obj


def box(center, size, mat, bevel=0.03, pitch_deg=0.0, roll_deg=0.0):
    """`center` and `size` are Godot (x, y, z). `pitch_deg` tilts around X, `roll_deg` around Z."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=_v(*center))
    obj = bpy.context.active_object
    obj.scale = (size[0], size[2], size[1])
    obj.rotation_euler = (math.radians(pitch_deg), math.radians(roll_deg), 0.0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return _finish(obj, mat, bevel)


def rod_x(center, radius, length, mat, verts=16, bevel=0.01):
    """A cylinder along the Godot X (sideways) axis."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=length, location=_v(*center))
    obj = bpy.context.active_object
    obj.rotation_euler = (0.0, math.radians(90), 0.0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return _finish(obj, mat, bevel)


def rod_y(center, radius, length, mat, verts=12, bevel=0.0):
    """A cylinder along the Godot Y (up) axis."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=length, location=_v(*center))
    return _finish(bpy.context.active_object, mat, bevel)


def sphere(center, radius, mat, segments=24, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius, location=_v(*center))
    obj = bpy.context.active_object
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return obj


def join_as(name, objects, origin=(0.0, 0.0, 0.0)):
    """Joins `objects` into one mesh called `name`, with its origin at the Godot point `origin`."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    joined.data.name = name
    bpy.context.scene.cursor.location = _v(*origin)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return joined


def collect(build_parts):
    before = set(bpy.data.objects)
    build_parts()
    return [obj for obj in bpy.data.objects if obj not in before]


def build_frame(wood, dark_wood, iron, rope):
    # Two long base beams, with iron caps, and cross beams tying them together.
    for x in (-0.45, 0.45):
        box((x, -0.15, -0.45), (0.2, 0.22, 3.2), wood, 0.04)
        box((x, -0.15, -2.02), (0.24, 0.26, 0.1), iron, 0.01)
        box((x, -0.15, FRAME_FRONT_Z), (0.24, 0.26, 0.1), iron, 0.01)
    for z in (-1.8, -0.75, 0.95):
        box((0.0, -0.12, z), (1.0, 0.16, 0.18), dark_wood, 0.03)

    # Uprights holding the axle, braced back and forth.
    pivot_x, pivot_y, pivot_z = ARM_PIVOT
    for x in (-0.45, 0.45):
        box((x, 0.25, pivot_z), (0.18, 0.95, 0.2), wood, 0.03)
        box((x, 0.18, pivot_z - 0.42), (0.14, 0.95, 0.14), dark_wood, 0.02, pitch_deg=-38)
        box((x, 0.18, pivot_z + 0.42), (0.14, 0.95, 0.14), dark_wood, 0.02, pitch_deg=38)
    rod_x((0.0, pivot_y, pivot_z), 0.075, 1.2, iron)

    # The stop bar the arm slams into, padded with rope.
    for x in (-0.45, 0.45):
        box((x, 0.85, pivot_z + 0.35), (0.16, 1.1, 0.16), wood, 0.03, pitch_deg=12)
    box((0.0, 1.38, pivot_z + 0.45), (1.06, 0.18, 0.2), dark_wood, 0.03)
    rod_x((0.0, 1.38, pivot_z + 0.45), 0.13, 0.5, rope, verts=12)

    # Winch drum at the back, for the look of a wound-down arm.
    rod_x((0.0, 0.05, -1.45), 0.16, 0.7, dark_wood)
    for x in (-0.36, 0.36):
        rod_x((x, 0.05, -1.45), 0.2, 0.06, iron)
    rod_x((0.0, 0.05, -1.45), 0.17, 0.08, rope, verts=12)

    # The back carrier's handles: the base beams carry on behind the frame.
    for x in (-0.45, 0.45):
        box((x, -0.15, -2.3), (0.14, 0.14, 0.5), dark_wood, 0.03)
    box((0.0, -0.15, -2.52), (1.04, 0.12, 0.12), dark_wood, 0.03)

    # The front pole's socket.
    box((0.0, -0.12, FRAME_FRONT_Z + 0.02), (0.3, 0.24, 0.24), iron, 0.02)


def build_arm(wood, dark_wood, iron, rope):
    # Built around the pivot at the origin, pointing back along -Z.
    box((0.0, 0.0, -ARM_LENGTH * 0.5 + 0.15), (0.18, 0.18, ARM_LENGTH + 0.3), wood, 0.04)
    rod_x((0.0, 0.0, 0.0), 0.14, 0.42, iron)
    for z in (-0.45, -1.1, -1.7):
        box((0.0, 0.0, z), (0.22, 0.22, 0.07), iron, 0.01)
    # Counterweight-looking lump on the short end, roped on.
    box((0.0, -0.02, 0.32), (0.36, 0.34, 0.26), dark_wood, 0.05)
    rod_x((0.0, -0.02, 0.32), 0.19, 0.06, rope, verts=12)
    # The cup: a shallow wooden bowl with an iron rim, facing up.
    cup_z = -ARM_LENGTH
    box((0.0, 0.05, cup_z), (0.62, 0.1, 0.62), dark_wood, 0.04)
    for x in (-0.31, 0.31):
        box((x, 0.17, cup_z), (0.08, 0.24, 0.66), iron, 0.01)
    for z in (-0.31, 0.31):
        box((0.0, 0.17, cup_z + z), (0.66, 0.24, 0.08), iron, 0.01)


def build_front_pole(dark_wood, iron):
    box((0.0, 0.0, 0.5), (0.16, 0.16, 1.0), dark_wood, 0.0)
    box((0.0, 0.0, 0.03), (0.2, 0.2, 0.06), iron, 0.0)


def build_front_grip(dark_wood, iron):
    box((0.0, 0.0, 0.0), (1.0, 0.13, 0.13), dark_wood, 0.03)
    for x in (-0.5, 0.5):
        box((x, 0.0, 0.0), (0.06, 0.18, 0.18), iron, 0.01)
    box((0.0, 0.0, 0.0), (0.22, 0.2, 0.2), iron, 0.02)


def build_bomb():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    shell = _material("BombShell", (0.08, 0.08, 0.09), 0.6, 0.45)
    band = _material("BombBand", (0.55, 0.38, 0.18), 0.7, 0.4)
    fuse = _material("BombFuse", (0.85, 0.75, 0.55), 0.0, 0.9)
    spark = _material("BombSpark", (1.0, 0.55, 0.1), 0.0, 0.4, emission=(1.0, 0.5, 0.08))
    parts = collect(lambda: (
        sphere((0.0, 0.0, 0.0), 0.42, shell),
        rod_x((0.0, 0.0, 0.0), 0.43, 0.1, band, verts=32),
        rod_y((0.0, 0.42, 0.0), 0.12, 0.12, band),
        rod_y((0.0, 0.56, 0.0), 0.035, 0.2, fuse),
        sphere((0.0, 0.68, 0.0), 0.07, spark, 12, 6),
    ))
    join_as("Bomb", parts)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "catapult_bomb.blend"))
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_DIR, "catapult_bomb.glb"),
        export_format="GLB",
        use_selection=False,
        export_apply=True,
    )


def build_catapult():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    wood = _material("Wood", (0.52, 0.32, 0.16), 0.0, 0.75)
    dark_wood = _material("DarkWood", (0.3, 0.18, 0.09), 0.0, 0.8)
    iron = _material("Iron", (0.16, 0.16, 0.18), 0.5, 0.5)
    rope = _material("Rope", (0.78, 0.66, 0.44), 0.0, 0.95)

    join_as("Frame", collect(lambda: build_frame(wood, dark_wood, iron, rope)))
    join_as("Arm", collect(lambda: build_arm(wood, dark_wood, iron, rope)))
    join_as("FrontPole", collect(lambda: build_front_pole(dark_wood, iron)))
    join_as("FrontGrip", collect(lambda: build_front_grip(dark_wood, iron)))
    # Parts were built around their own origins; move the arm onto its axle.
    bpy.data.objects["Arm"].location = _v(*ARM_PIVOT)

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "catapult.blend"))
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_DIR, "catapult.glb"),
        export_format="GLB",
        use_selection=False,
        export_apply=True,
    )


os.makedirs(OUT_DIR, exist_ok=True)
build_catapult()
build_bomb()
