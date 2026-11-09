"""Builds the Combat Mech's grenade launcher and exports it to assets/models/weapon/enemies/combat_mech/.

Run: /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_grenade_launcher.py

A chunky revolver-drum launcher in the KayKit Combat Mech's palette (white plates, yellow drum like the minigun's,
dark barrel, a red sight and a green stripe), low-poly with soft bevels to sit beside the KayKit art.

Godot axes: the barrel points along +Z, up is +Y, and the origin is where the hand holds it, at the drum,
like the KayKit minigun, so it mounts on the mech's `handslot.r` the same way.
Blender is Z-up, so every part below is placed as (x, y_godot, z_godot) through `_v`.
"""
import math
import os

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "models", "weapon", "enemies", "combat_mech")


def _v(x, y_up, z_fwd):
    # Godot (x, y, z) -> Blender (x, -z, y): the glTF exporter maps Blender -Y to Godot +Z.
    return (x, -z_fwd, y_up)


def _material(name, color, roughness=0.6):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = roughness
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


def box(center, size, mat, bevel=0.03, tilt_deg=0.0):
    """`center` and `size` are Godot (x, y, z). `tilt_deg` pitches the box around X."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=_v(*center))
    obj = bpy.context.active_object
    obj.scale = (size[0], size[2], size[1])
    obj.rotation_euler = (math.radians(tilt_deg), 0.0, 0.0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return _finish(obj, mat, bevel)


def tube(center, radius, length, mat, verts=16, bevel=0.02):
    """A cylinder along the Godot Z (firing) axis."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=length, location=_v(*center))
    obj = bpy.context.active_object
    obj.rotation_euler = (math.radians(90), 0.0, 0.0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return _finish(obj, mat, bevel)


def _join(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    joined.data.name = name
    return joined


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    white = _material("Plate", (0.86, 0.88, 0.9))
    dark = _material("Dark", (0.2, 0.22, 0.26), 0.5)
    bore = _material("Bore", (0.04, 0.04, 0.05), 0.8)
    yellow = _material("Drum", (0.96, 0.72, 0.16))
    red = _material("Red", (0.85, 0.16, 0.16))
    green = _material("Green", (0.16, 0.58, 0.34))

    # Revolver drum at the hand: six chambers. It is its own object, around the barrel axis, so the game can turn it.
    drum_parts = [tube((0.0, 0.0, 0.0), 0.3, 0.42, yellow, verts=12, bevel=0.04)]
    for i in range(6):
        angle = math.radians(30 + i * 60)
        x, y = math.cos(angle) * 0.19, math.sin(angle) * 0.19
        drum_parts.append(tube((x, y, 0.215), 0.065, 0.02, bore, verts=10, bevel=0.0))
        drum_parts.append(tube((x, y, -0.215), 0.065, 0.02, dark, verts=10, bevel=0.0))
    drum = _join(drum_parts, "Drum")
    tube((0.0, 0.0, 0.0), 0.12, 0.48, dark, verts=12)

    # Fat barrel ahead of the drum, a white sleeve, and a red-banded muzzle.
    tube((0.0, 0.12, 0.62), 0.17, 0.85, dark)
    tube((0.0, 0.12, 0.42), 0.21, 0.36, white, bevel=0.04)
    tube((0.0, 0.12, 1.06), 0.23, 0.12, white, bevel=0.03)
    tube((0.0, 0.12, 0.98), 0.235, 0.04, red, bevel=0.0)
    tube((0.0, 0.12, 1.125), 0.13, 0.02, bore, bevel=0.0)

    # Receiver and stock behind the drum, with a green stripe on each side.
    box((0.0, 0.1, -0.42), (0.34, 0.42, 0.44), white, 0.05)
    box((0.175, 0.16, -0.42), (0.02, 0.08, 0.34), green, 0.0)
    box((-0.175, 0.16, -0.42), (0.02, 0.08, 0.34), green, 0.0)
    box((0.0, 0.02, -0.82), (0.24, 0.3, 0.4), white, 0.05)
    box((0.0, 0.0, -1.04), (0.28, 0.38, 0.08), dark, 0.02)

    # Pistol grip under the receiver, and a foregrip under the barrel.
    box((0.0, -0.28, -0.3), (0.15, 0.36, 0.18), dark, 0.03, tilt_deg=-15)
    box((0.0, -0.18, 0.62), (0.14, 0.28, 0.14), dark, 0.03)

    # Carry handle across the top, with a red sight on its front.
    box((0.0, 0.42, -0.25), (0.1, 0.08, 0.5), dark, 0.02)
    box((0.0, 0.35, -0.45), (0.08, 0.14, 0.06), dark, 0.01)
    box((0.0, 0.35, -0.03), (0.08, 0.14, 0.06), dark, 0.01)
    box((0.0, 0.48, 0.05), (0.12, 0.12, 0.12), red, 0.02)

    launcher = _join([o for o in bpy.context.scene.objects if o != drum], "GrenadeLauncher")
    drum.parent = launcher

    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "grenade_launcher.blend"))
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_DIR, "grenade_launcher.glb"),
        export_format="GLB",
        use_selection=False,
        export_apply=True,
    )


build()
