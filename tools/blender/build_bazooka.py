"""Builds the bazooka and its rocket, exported to assets/models/weapon/bazooka/.

Run: /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_bazooka.py

Matches the main menu art: an eight-sided barrel of wooden staves held by brass bands,
a heavy octagonal muzzle glowing red inside, a brass sight tube on top, and a brass rocket.

Godot axes: the muzzle points along +Z, up is +Y, and the origin sits on the barrel's axis.
Blender is Z-up, so every part below is placed as (x, z_godot, y_godot) through `_v`.

bazooka.glb holds two nodes:
- Bazooka: the launcher. Muzzle opening at Godot z = 2.95, rear cap at z = -3.0.
- LoadedRocket: the warhead tip peeking out of the muzzle; `bazooka_specifics.gd` hides it
  while reloading.
bazooka_rocket.glb is the fired rocket, centred on its origin, nose along +Z, about 2 m long.
"""
import math
import os

import bpy
from mathutils import Matrix

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "models", "weapon", "bazooka")

## Distance from the axis to the outside of a barrel stave.
BARREL = 0.44
MUZZLE_Z = 2.95
OCTAGON = math.cos(math.pi / 8.0)


def _v(x, y_up, z_fwd):
    # Godot (x, y, z) -> Blender (x, -z, y): the glTF exporter maps Blender -Y to Godot +Z.
    return (x, -z_fwd, y_up)


def _material(name, color, metallic, roughness, emission=None, strength=5.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def make_palette():
    # Brass stays barely metallic and leans orange: under the levels' cyan sky and ambient light,
    # a metallic or yellower brass reads green in Godot.
    return {
        "wood": _material("Wood", (0.45, 0.17, 0.04), 0.0, 0.75),
        "wood_light": _material("WoodLight", (0.60, 0.26, 0.06), 0.0, 0.7),
        "wood_dark": _material("WoodDark", (0.10, 0.035, 0.01), 0.0, 0.85),
        "brass": _material("Brass", (0.80, 0.30, 0.04), 0.1, 0.4),
        "brass_dark": _material("BrassDark", (0.40, 0.12, 0.015), 0.1, 0.5),
        "bore": _material("Bore", (0.3, 0.03, 0.01), 0.0, 0.8, emission=(1.0, 0.1, 0.02), strength=1.5),
        "glow": _material("Glow", (1.0, 0.18, 0.04), 0.0, 0.4, emission=(1.0, 0.18, 0.04), strength=4.0),
        "ember": _material("Ember", (0.4, 0.08, 0.02), 0.0, 0.6, emission=(1.0, 0.25, 0.05), strength=1.0),
    }


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


def _select_only(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def _apply_transform(obj):
    _select_only(obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def _spin_around_axis(obj, angle):
    """Rolls `obj` around the Godot Z axis (Blender Y through the origin)."""
    obj.matrix_world = Matrix.Rotation(angle, 4, "Y") @ obj.matrix_world
    _apply_transform(obj)


def box(center, size, mat, bevel=0.03, tilt_deg=0.0):
    """`center` and `size` are Godot (x, y, z). `tilt_deg` pitches around X."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=_v(*center))
    obj = bpy.context.active_object
    obj.scale = (size[0], size[2], size[1])
    obj.rotation_euler = (math.radians(tilt_deg), 0.0, 0.0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return _finish(obj, mat, bevel)


def tube(z_from, z_to, radius, mat, radius_end=None, verts=8, bevel=0.02, y=0.0, hollow=0.0):
    """A prism or cone along Godot Z, from `z_from` (radius) to `z_to` (radius_end).

    Radii are measured to the flat faces, so an 8-sided band of radius r hugs staves at r.
    `hollow` > 0 leaves the caps open and gives the wall that thickness.
    """
    end = radius if radius_end is None else radius_end
    flat = OCTAGON if verts == 8 else 1.0
    bpy.ops.mesh.primitive_cone_add(
        vertices=verts,
        radius1=radius / flat,
        radius2=end / flat,
        depth=abs(z_to - z_from),
        end_fill_type="NOTHING" if hollow > 0.0 else "NGON",
        location=(0.0, 0.0, 0.0),
    )
    obj = bpy.context.active_object
    # Cone axis is Blender +Z; tip it to Blender -Y (Godot +Z) so radius2 sits at z_to.
    obj.rotation_euler = (math.radians(90 if z_to > z_from else -90), 0.0, 0.0)
    _apply_transform(obj)
    if verts == 8:
        # Turn a flat face to the top, lined up with the staves.
        _spin_around_axis(obj, math.pi / 8.0)
    obj.location = _v(0.0, y, (z_from + z_to) * 0.5)
    _apply_transform(obj)
    if hollow > 0.0:
        mod = obj.modifiers.new("Wall", "SOLIDIFY")
        mod.thickness = hollow
        mod.offset = 1.0
    return _finish(obj, mat, bevel)


def staves(z_from, z_to, apothem, pal, thickness=0.09):
    """Eight wooden planks around the axis, in alternating tones."""
    # Slightly narrow, so dark grooves show between the planks.
    width = 2.0 * apothem * math.tan(math.pi / 8.0) - 0.035
    tones = (pal["wood"], pal["wood_light"])
    for i in range(8):
        plank = box((0.0, apothem - thickness * 0.5, (z_from + z_to) * 0.5), (width, thickness, z_to - z_from), tones[i % 2], 0.015)
        _spin_around_axis(plank, i * math.tau / 8.0)
    # A dark core so no gaps show between planks.
    tube(z_from, z_to, apothem - thickness * 0.6, pal["wood_dark"], bevel=0.0)


def fins(z_from, z_to, inner, outer, mat, count=4, thickness=0.06):
    for i in range(count):
        fin = box((0.0, (inner + outer) * 0.5, (z_from + z_to) * 0.5), (thickness, outer - inner, z_to - z_from), mat, 0.015)
        _spin_around_axis(fin, math.pi / 4.0 + i * math.tau / count)


def build_rocket_parts(pal, z_offset=0.0, warhead_only=False):
    """The rocket, nose along +Z, about 2 m long; `z_offset` slides every part.

    `warhead_only` skips the motor and fins, which would poke through the barrel.
    """
    o = z_offset
    _build_warhead(pal, o)
    if warhead_only:
        return
    # Motor, tail collar, fins and a glowing nozzle.
    tube(o - 0.85, o - 0.1, 0.17, pal["brass_dark"], bevel=0.015)
    tube(o - 0.9, o - 0.72, 0.21, pal["brass"], bevel=0.02)
    fins(o - 0.95, o - 0.35, 0.15, 0.52, pal["brass"])
    tube(o - 1.02, o - 0.88, 0.2, pal["brass_dark"], radius_end=0.15, hollow=0.04, bevel=0.0)
    tube(o - 0.93, o - 0.91, 0.16, pal["glow"], bevel=0.0)


def _build_warhead(pal, o):
    tube(o - 0.2, o - 0.05, 0.17, pal["brass_dark"], radius_end=0.29, bevel=0.015)
    tube(o - 0.05, o + 0.35, 0.29, pal["brass"], bevel=0.025)
    tube(o + 0.12, o + 0.2, 0.3, pal["brass_dark"], bevel=0.0)
    # Faceted pointed nose, blunted at the tip like the menu art.
    tube(o + 0.35, o + 0.85, 0.29, pal["brass"], radius_end=0.08, bevel=0.02)
    tube(o + 0.85, o + 0.92, 0.08, pal["brass_dark"], radius_end=0.05, bevel=0.0)


def build_bazooka(pal):
    b = BARREL
    staves(-2.75, 2.2, b, pal)

    # Heavy octagonal muzzle block, wood with brass rims, glowing red inside.
    tube(2.15, 2.85, b + 0.2, pal["wood"], hollow=0.12, bevel=0.03)
    tube(2.1, 2.3, b + 0.25, pal["brass"], bevel=0.03)
    tube(2.75, MUZZLE_Z, b + 0.25, pal["brass"], hollow=0.14, bevel=0.03)
    tube(2.16, 2.9, b + 0.08, pal["bore"], radius_end=b + 0.1, hollow=0.02, bevel=0.0)
    tube(2.3, 2.34, b + 0.06, pal["glow"], bevel=0.0)

    # Brass bands along the barrel, paired like the menu art.
    for z in (-1.6, -1.35, 0.3, 0.55, 1.6):
        tube(z - 0.08, z + 0.08, b + 0.05, pal["brass"], bevel=0.02)

    # Rear: a flared brass-rimmed cap with a faint ember inside.
    tube(-2.9, -2.6, b + 0.12, pal["wood"], hollow=0.1, bevel=0.03)
    tube(-3.0, -2.85, b + 0.16, pal["brass"], hollow=0.1, bevel=0.03)
    tube(-2.7, -2.5, b + 0.07, pal["brass"], bevel=0.02)
    tube(-2.78, -2.75, b - 0.02, pal["ember"], bevel=0.0)

    # Brass sight tube on two posts, open at both ends.
    sight_y = b + 0.42
    for z in (-1.85, -0.85):
        box((0.0, b + 0.2, z), (0.1, 0.36, 0.12), pal["brass_dark"], 0.02)
    tube(-2.25, -0.5, 0.13, pal["brass"], y=sight_y, hollow=0.04, bevel=0.01)
    tube(-0.62, -0.42, 0.16, pal["brass_dark"], y=sight_y, hollow=0.05, bevel=0.01)
    tube(-2.33, -2.13, 0.16, pal["brass_dark"], y=sight_y, hollow=0.05, bevel=0.01)


def join_as(name, objects):
    _select_only(objects[0])
    for obj in objects:
        obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    joined.data.name = name
    return joined


def collect(build_parts):
    before = set(bpy.data.objects)
    build_parts()
    return [obj for obj in bpy.data.objects if obj not in before]


def export(filename):
    os.makedirs(OUT_DIR, exist_ok=True)
    base = os.path.join(OUT_DIR, filename)
    bpy.ops.wm.save_as_mainfile(filepath=base + ".blend")
    bpy.ops.export_scene.gltf(filepath=base + ".glb", export_format="GLB", use_selection=False, export_apply=True)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    pal = make_palette()
    join_as("Bazooka", collect(lambda: build_bazooka(pal)))
    # Only the nose shows past the muzzle; the rest hides inside the bore.
    join_as("LoadedRocket", collect(lambda: build_rocket_parts(pal, z_offset=MUZZLE_Z - 0.6, warhead_only=True)))
    export("bazooka")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    pal = make_palette()
    join_as("BazookaRocket", collect(lambda: build_rocket_parts(pal)))
    export("bazooka_rocket")


build()
