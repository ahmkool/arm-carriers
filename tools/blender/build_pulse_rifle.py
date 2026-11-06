"""Builds the pulse rifle model and exports it to assets/models/weapon/pulse_rifle/.

Run: /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_pulse_rifle.py

Godot axes: the muzzle points along +Z, up is +Y, and the origin sits at carry height.
Blender is Z-up, so every part below is placed as (x, z_godot, y_godot) through `_v`.
The back carrier holds the pistol grip at Godot z = -2.0, the front carrier the
foregrip at z = 1.2, both on the gun's right (+X) side.
"""
import math
import os

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "models", "weapon", "pulse_rifle")


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


def box(center, size, mat, bevel=0.03, tilt_deg=0.0):
    """`center` and `size` are Godot (x, y, z). `tilt_deg` pitches the box around X."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=_v(*center))
    obj = bpy.context.active_object
    obj.scale = (size[0], size[2], size[1])
    obj.rotation_euler = (math.radians(tilt_deg), 0.0, 0.0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return _finish(obj, mat, bevel)


def tube(center, radius, length, mat, verts=24, bevel=0.015):
    """A cylinder along the Godot Z (firing) axis."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=length, location=_v(*center))
    obj = bpy.context.active_object
    obj.rotation_euler = (math.radians(90), 0.0, 0.0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return _finish(obj, mat, bevel)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    body = _material("Body", (0.10, 0.11, 0.13), 0.7, 0.35)
    panel = _material("Panel", (0.78, 0.80, 0.83), 0.1, 0.45)
    glow = _material("Glow", (0.25, 0.95, 1.0), 0.0, 0.3, emission=(0.25, 0.95, 1.0))
    accent = _material("Accent", (0.95, 0.45, 0.10), 0.2, 0.5)

    # Stock, with a light shoulder pad.
    box((0.0, -0.05, -2.75), (0.36, 0.55, 0.7), panel, 0.05)
    box((0.0, -0.05, -3.13), (0.40, 0.66, 0.12), body, 0.03)
    box((0.0, 0.25, -2.2), (0.3, 0.16, 0.5), body, 0.03)

    # Receiver: dark core with light side panels and a glowing status strip.
    box((0.0, 0.05, -0.8), (0.52, 0.62, 2.7), body, 0.05)
    box((0.27, 0.12, -0.9), (0.04, 0.36, 2.1), panel, 0.015)
    box((-0.27, 0.12, -0.9), (0.04, 0.36, 2.1), panel, 0.015)
    box((0.29, 0.12, -0.9), (0.02, 0.06, 1.6), glow, 0.0)
    box((-0.29, 0.12, -0.9), (0.02, 0.06, 1.6), glow, 0.0)
    # Ejection port and charging handle, orange so the gun reads at a glance.
    box((0.27, 0.22, 0.05), (0.06, 0.12, 0.38), accent, 0.01)

    # Pistol grip for the back carrier, and the trigger guard.
    box((0.0, -0.5, -1.95), (0.24, 0.62, 0.28), body, 0.04, tilt_deg=-18)
    box((0.0, -0.3, -1.6), (0.16, 0.06, 0.42), body, 0.015)

    # Box magazine, angled forward, with a light band and glowing cell window.
    box((0.0, -0.55, -0.85), (0.34, 0.8, 0.5), body, 0.04, tilt_deg=12)
    box((0.0, -0.4, -0.88), (0.36, 0.12, 0.52), panel, 0.02, tilt_deg=12)
    box((0.18, -0.65, -0.82), (0.02, 0.32, 0.12), glow, 0.0, tilt_deg=12)

    # Top rail and holographic sight.
    box((0.0, 0.42, -0.6), (0.22, 0.08, 2.4), body, 0.01)
    for i in range(9):
        box((0.0, 0.48, -1.6 + i * 0.25), (0.24, 0.04, 0.1), body, 0.0)
    box((0.0, 0.66, -0.9), (0.3, 0.34, 0.5), body, 0.04)
    box((0.0, 0.7, -0.62), (0.22, 0.2, 0.04), glow, 0.0)

    # Handguard, vented, around the barrel.
    box((0.0, 0.05, 1.3), (0.46, 0.5, 1.7), panel, 0.05)
    for i in range(5):
        z = 0.75 + i * 0.28
        box((0.235, 0.12, z), (0.02, 0.2, 0.12), body, 0.0)
        box((-0.235, 0.12, z), (0.02, 0.2, 0.12), body, 0.0)
    box((0.0, -0.21, 1.3), (0.48, 0.06, 1.72), accent, 0.015)

    # Vertical foregrip for the front carrier.
    box((0.0, -0.5, 1.2), (0.22, 0.62, 0.24), body, 0.04)

    # Barrel, glowing coils and the muzzle brake.
    tube((0.0, 0.08, 2.75), 0.11, 1.2, body)
    for i in range(3):
        tube((0.0, 0.08, 2.35 + i * 0.22), 0.15, 0.06, glow, bevel=0.0)
    tube((0.0, 0.08, 3.38), 0.17, 0.3, body)
    box((0.0, 0.08, 3.38), (0.42, 0.08, 0.16), body, 0.01)

    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    rifle = bpy.context.active_object
    rifle.name = "PulseRifle"
    rifle.data.name = "PulseRifle"

    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "pulse_rifle.blend"))
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_DIR, "pulse_rifle.glb"),
        export_format="GLB",
        use_selection=False,
        export_apply=True,
    )


build()
