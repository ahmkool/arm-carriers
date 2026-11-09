"""Builds the fork cannon model and exports it to assets/models/weapon/fork_cannon/.

Run: /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_fork_cannon.py

A pulse rifle's receiver that forks ahead of the foregrip into two prongs: a fat missile tube on the
left (-X) and a thin, coiled bolt barrel on the right (+X). The game camera looks down, so the fork
splits sideways where it reads best.

Godot axes: the muzzles point along +Z, up is +Y, and the origin sits at carry height.
Blender is Z-up, so every part below is placed as (x, z_godot, y_godot) through `_v`.
The back carrier holds the pistol grip at Godot z = -2.0, the front carrier the
foregrip at z = 1.2, both on the gun's right (+X) side.
Keep MISSILE_MUZZLE and BOLT_MUZZLE in step with the markers in src/weapon/fork_cannon.tscn.
"""
import math
import os

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "models", "weapon", "fork_cannon")

FORK_Z = 1.75
MISSILE_X = -0.5
BOLT_X = 0.42
PRONG_Y = 0.1
MISSILE_MUZZLE_Z = 3.75
BOLT_MUZZLE_Z = 3.95


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
        bsdf.inputs["Emission Strength"].default_value = 4.0
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


def box(center, size, mat, bevel=0.03, tilt_deg=0.0, yaw_deg=0.0):
    """`center` and `size` are Godot (x, y, z). `tilt_deg` pitches around X, `yaw_deg` turns around Y."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=_v(*center))
    obj = bpy.context.active_object
    obj.scale = (size[0], size[2], size[1])
    obj.rotation_euler = (math.radians(tilt_deg), 0.0, math.radians(yaw_deg))
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return _finish(obj, mat, bevel)


def tube(center, radius, length, mat, verts=24, bevel=0.015, yaw_deg=0.0):
    """A cylinder along the Godot Z (firing) axis, optionally turned around Y."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=length, location=_v(*center))
    obj = bpy.context.active_object
    obj.rotation_euler = (math.radians(90), 0.0, math.radians(yaw_deg))
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return _finish(obj, mat, bevel)


def _strut(x_from, x_to, z_from, z_to, y, size_xy, mat):
    """A box joining (x_from, z_from) to (x_to, z_to): the fork's arms."""
    dx = x_to - x_from
    dz = z_to - z_from
    length = math.hypot(dx, dz)
    # Blender's Z rotation turns Godot +Z (Blender -Y) towards Godot +X by a positive angle.
    yaw = math.degrees(math.atan2(dx, dz))
    center = ((x_from + x_to) / 2.0, y, (z_from + z_to) / 2.0)
    return box(center, (size_xy[0], size_xy[1], length), mat, 0.03, yaw_deg=yaw)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    body = _material("Body", (0.10, 0.11, 0.13), 0.7, 0.35)
    panel = _material("Panel", (0.80, 0.80, 0.78), 0.1, 0.45)
    glow = _material("Glow", (0.25, 0.95, 1.0), 0.0, 0.3, emission=(0.25, 0.95, 1.0))
    hot = _material("Hot", (1.0, 0.35, 0.08), 0.0, 0.4, emission=(1.0, 0.35, 0.08))
    accent = _material("Accent", (0.95, 0.45, 0.10), 0.2, 0.5)
    warning = _material("Warning", (0.95, 0.80, 0.15), 0.1, 0.5)

    # Stock, with a light shoulder pad.
    box((0.0, -0.05, -2.75), (0.4, 0.58, 0.7), panel, 0.05)
    box((0.0, -0.05, -3.13), (0.44, 0.68, 0.12), body, 0.03)
    box((0.0, 0.25, -2.2), (0.32, 0.16, 0.5), body, 0.03)

    # Receiver, wider than the rifle's, since it feeds two barrels.
    box((0.0, 0.05, -0.6), (0.7, 0.66, 3.0), body, 0.06)
    box((0.36, 0.14, -0.7), (0.04, 0.36, 2.3), panel, 0.015)
    box((-0.36, 0.14, -0.7), (0.04, 0.36, 2.3), panel, 0.015)
    box((0.385, 0.14, -0.7), (0.02, 0.06, 1.8), glow, 0.0)
    box((-0.385, 0.14, -0.7), (0.02, 0.06, 1.8), hot, 0.0)

    # Pistol grip for the back carrier, and the trigger guard.
    box((0.0, -0.5, -1.95), (0.26, 0.62, 0.28), body, 0.04, tilt_deg=-18)
    box((0.0, -0.3, -1.6), (0.16, 0.06, 0.42), body, 0.015)

    # Bolt cell under the right side, missile drum under the left.
    box((0.16, -0.5, -0.75), (0.3, 0.72, 0.46), body, 0.04, tilt_deg=12)
    box((0.31, -0.58, -0.72), (0.02, 0.3, 0.12), glow, 0.0, tilt_deg=12)
    tube((-0.22, -0.32, -0.3), 0.3, 0.9, panel, verts=8, bevel=0.03)
    for i in range(4):
        tube((-0.22, -0.32, -0.66 + i * 0.24), 0.32, 0.05, warning, verts=8, bevel=0.0)

    # Top rail and sight.
    box((0.0, 0.43, -0.5), (0.24, 0.08, 2.6), body, 0.01)
    for i in range(9):
        box((0.0, 0.49, -1.6 + i * 0.27), (0.26, 0.04, 0.1), body, 0.0)
    box((0.0, 0.67, -0.9), (0.32, 0.34, 0.5), body, 0.04)
    box((0.0, 0.71, -0.62), (0.24, 0.2, 0.04), hot, 0.0)

    # Handguard up to the fork, and the front carrier's vertical foregrip.
    box((0.0, 0.05, 1.25), (0.66, 0.52, 1.1), panel, 0.05)
    box((0.0, -0.2, 1.25), (0.68, 0.06, 1.12), accent, 0.015)
    box((0.0, -0.5, 1.2), (0.22, 0.62, 0.24), body, 0.04)

    # The fork: a yoke, then an arm out to each prong.
    box((0.0, PRONG_Y, FORK_Z), (0.7, 0.42, 0.3), body, 0.04)
    _strut(-0.15, MISSILE_X, FORK_Z, FORK_Z + 0.6, PRONG_Y, (0.34, 0.36), body)
    _strut(0.15, BOLT_X, FORK_Z, FORK_Z + 0.6, PRONG_Y, (0.24, 0.26), body)

    # Missile prong: a wide launch tube with hazard bands and an open, glowing mouth.
    tube((MISSILE_X, PRONG_Y, 2.95), 0.26, 1.6, body)
    tube((MISSILE_X, PRONG_Y, 2.55), 0.29, 0.1, warning, bevel=0.0)
    tube((MISSILE_X, PRONG_Y, 3.25), 0.29, 0.1, warning, bevel=0.0)
    tube((MISSILE_X, PRONG_Y, MISSILE_MUZZLE_Z - 0.08), 0.31, 0.16, body)
    tube((MISSILE_X, PRONG_Y, MISSILE_MUZZLE_Z - 0.14), 0.2, 0.05, hot, bevel=0.0)
    box((MISSILE_X - 0.27, PRONG_Y + 0.12, 2.9), (0.06, 0.12, 0.9), accent, 0.01)

    # Bolt prong: a thin barrel with glowing coils and a muzzle brake, reaching a little further.
    tube((BOLT_X, PRONG_Y, 3.05), 0.1, 1.8, body)
    for i in range(4):
        tube((BOLT_X, PRONG_Y, 2.55 + i * 0.22), 0.15, 0.06, glow, bevel=0.0)
    tube((BOLT_X, PRONG_Y, BOLT_MUZZLE_Z - 0.15), 0.16, 0.3, body)
    box((BOLT_X, PRONG_Y, BOLT_MUZZLE_Z - 0.15), (0.38, 0.08, 0.16), body, 0.01)

    # A brace between the prongs, so the fork reads as one gun.
    box(((MISSILE_X + BOLT_X) / 2.0, PRONG_Y - 0.12, 3.0), (BOLT_X - MISSILE_X, 0.08, 0.18), body, 0.02)

    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    gun = bpy.context.active_object
    gun.name = "ForkCannon"
    gun.data.name = "ForkCannon"

    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "fork_cannon.blend"))
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_DIR, "fork_cannon.glb"),
        export_format="GLB",
        use_selection=False,
        export_apply=True,
    )


build()
