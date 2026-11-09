"""Shared pieces for the medieval castle reskins: text helpers for writing .tscn files, the prop scenes in
src/world/elements/medieval/, the environment, and helpers that edit a copied level without touching its gameplay.
Used by build_medieval_02.py and build_medieval_level_2.py.
"""

import math
import os
import random
import re

ART = "src/world/elements/medieval"
RES_ART = "res://" + ART

STONE_SHADER = RES_ART + "/castle_stone.gdshader"
CLOTH_SHADER = RES_ART + "/heraldry_cloth.gdshader"
FLICKER_SCRIPT = "res://src/world/elements/dungeon/flicker_brazier.gd"
BOB_SCRIPT = "res://src/world/elements/sky/floating_bob.gd"
MUSIC_PATH = "res://assets/music/PerituneMaterial_OverWorld_Orchestra.mp3"
MUSIC_UID = "uid://duaul8r11ug66"

# Heraldry: (field colour, charge colour, charge). Charges: 0 cross, 1 chevron, 2 bend, 3 roundel.
HERALDRY = [
    ((0.6, 0.09, 0.1), (0.95, 0.76, 0.25), 0),
    ((0.12, 0.2, 0.5), (0.95, 0.85, 0.45), 1),
    ((0.6, 0.09, 0.1), (0.95, 0.76, 0.25), 2),
    ((0.12, 0.2, 0.5), (0.95, 0.85, 0.45), 3),
]


# ---------------------------------------------------------------- text helpers

def f(v):
    return ("%.4f" % v).rstrip("0").rstrip(".") if abs(v) > 1e-9 else "0"


def vec3(x, y, z):
    return "Vector3(%s, %s, %s)" % (f(x), f(y), f(z))


def color(c, a=1.0):
    return "Color(%s, %s, %s, %s)" % (f(c[0]), f(c[1]), f(c[2]), f(a))


def transform(pos=(0, 0, 0), yaw_deg=0.0, scale=(1, 1, 1), pitch_deg=0.0, roll_deg=0.0):
    """Row-major basis, as Godot writes Transform3D in scenes. Rotation order: yaw * pitch * roll, then scale."""
    cy, sy = math.cos(math.radians(yaw_deg)), math.sin(math.radians(yaw_deg))
    cp, sp = math.cos(math.radians(pitch_deg)), math.sin(math.radians(pitch_deg))
    cr, sr = math.cos(math.radians(roll_deg)), math.sin(math.radians(roll_deg))
    yaw = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    pitch = [[1, 0, 0], [0, cp, -sp], [0, sp, cp]]
    roll = [[cr, -sr, 0], [sr, cr, 0], [0, 0, 1]]
    m = matmul(matmul(yaw, pitch), roll)
    rows = [[m[i][j] * scale[j] for j in range(3)] for i in range(3)]
    values = [rows[i][j] for i in range(3) for j in range(3)] + list(pos)
    return "Transform3D(%s)" % ", ".join(f(v) for v in values)


def look_transform(direction, pos=(0, 0, 0)):
    """A basis whose -Z points along direction (for lights)."""
    d = normalize(direction)
    z = [-d[0], -d[1], -d[2]]
    up = [0, 1, 0]
    x = normalize(cross(up, z))
    y = cross(z, x)
    values = [x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2]] + list(pos)
    return "Transform3D(%s)" % ", ".join(f(v) for v in values)


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def normalize(v):
    length = math.sqrt(sum(c * c for c in v))
    return [c / length for c in v]


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


class Scene:
    """Collects ext_resources, sub_resources and nodes, then writes a .tscn."""

    def __init__(self, root_name, root_type="Node3D", root_props=None):
        # Set root_instance to an ExtResource to make an inherited scene.
        self.root_instance = None
        self.ext = []
        self.sub = []
        self.nodes = []
        self.root_props = root_props or {}
        self.root_name = root_name
        self.root_type = root_type

    def ext_resource(self, kind, path, uid=None):
        rid = "%d_%s" % (len(self.ext) + 1, kind.lower()[:6])
        self.ext.append((kind, path, uid, rid))
        return 'ExtResource("%s")' % rid

    def sub_resource(self, kind, props):
        rid = "%s_%d" % (kind, len(self.sub) + 1)
        self.sub.append((kind, rid, props))
        return 'SubResource("%s")' % rid

    def node(self, name, kind, parent=".", props=None, instance=None):
        self.nodes.append((name, kind, parent, props or {}, instance))
        return name if parent == "." else parent + "/" + name

    def text(self):
        out = ["[gd_scene format=3]", ""]
        for kind, path, uid, rid in self.ext:
            uid_text = ' uid="%s"' % uid if uid else ""
            out.append('[ext_resource type="%s"%s path="%s" id="%s"]' % (kind, uid_text, path, rid))
        if self.ext:
            out.append("")
        for kind, rid, props in self.sub:
            out.append('[sub_resource type="%s" id="%s"]' % (kind, rid))
            out += ["%s = %s" % (k, v) for k, v in props.items()]
            out.append("")
        if self.root_instance:
            out.append('[node name="%s" instance=%s]' % (self.root_name, self.root_instance))
        else:
            out.append('[node name="%s" type="%s"]' % (self.root_name, self.root_type))
        out += ["%s = %s" % (k, v) for k, v in self.root_props.items()]
        out.append("")
        for name, kind, parent, props, instance in self.nodes:
            out.append(node_header(name, kind, parent, instance))
            out += ["%s = %s" % (k, v) for k, v in props.items()]
            out.append("")
        return "\n".join(out)


def node_header(name, kind, parent, instance):
    if instance:
        return '[node name="%s" parent="%s" instance=%s]' % (name, parent, instance)
    if kind is None:  # overrides a node of the inherited scene
        return '[node name="%s" parent="%s"]' % (name, parent)
    return '[node name="%s" type="%s" parent="%s"]' % (name, kind, parent)


def mesh(scene, name, parent, mesh_ref, xform, shadow=True):
    props = {"transform": xform, "mesh": mesh_ref}
    if not shadow:
        props["cast_shadow"] = "0"
    return scene.node(name, "MeshInstance3D", parent, props)


def plain_material(scene, albedo, roughness=0.85, metallic=0.0, unshaded=False):
    props = {"albedo_color": color(albedo), "roughness": f(roughness)}
    if metallic:
        props["metallic"] = f(metallic)
    if unshaded:
        props = {"shading_mode": "0", "albedo_color": color(albedo)}
    return scene.sub_resource("StandardMaterial3D", props)


def stone_material(scene):
    shader = scene.ext_resource("Shader", STONE_SHADER)
    return scene.sub_resource("ShaderMaterial", {"render_priority": "0", "shader": shader})


def box(scene, size, material):
    return scene.sub_resource("BoxMesh", {"material": material, "size": vec3(*size)})


def cylinder(scene, top, bottom, height, material, segments=16):
    return scene.sub_resource("CylinderMesh", {
        "material": material, "top_radius": f(top), "bottom_radius": f(bottom), "height": f(height),
        "radial_segments": str(segments), "rings": "1",
    })


def write(path, text):
    with open(path, "w") as handle:
        handle.write(text)
    print("wrote", path)


# ---------------------------------------------------------------- prop scenes
# Every prop has its origin where it meets the water (or the wall it hangs on). None has collision.

def tower_scene():
    """A round tower standing in the moat: 8 m of masonry, a corbelled parapet, a slate cone and a pennant."""
    s = Scene("CastleTower")
    stone = stone_material(s)
    slate = s.sub_resource("StandardMaterial3D", {"albedo_color": color((0.24, 0.29, 0.42)), "roughness": "0.7"})
    dark = plain_material(s, (0.05, 0.045, 0.05), 1.0)
    wood = plain_material(s, (0.32, 0.22, 0.14))
    cloth = s.sub_resource("ShaderMaterial", {
        "render_priority": "0", "shader": s.ext_resource("Shader", CLOTH_SHADER), "shader_parameter/pennant": "true",
        "shader_parameter/sway": "0.1",
    })
    mesh(s, "Body", ".", cylinder(s, 2.1, 2.25, 8.0, stone, 20), transform((0, 4.0, 0)))
    mesh(s, "Corbel", ".", cylinder(s, 2.55, 2.1, 0.55, stone, 20), transform((0, 8.27, 0)))
    merlon = box(s, (0.75, 0.8, 0.45), stone)
    for index in range(10):
        angle = index * 36.0
        x = math.sin(math.radians(angle)) * 2.3
        z = math.cos(math.radians(angle)) * 2.3
        mesh(s, "Merlon%d" % index, ".", merlon, transform((x, 8.95, z), angle))
    mesh(s, "Roof", ".", cylinder(s, 0.0, 2.25, 3.8, slate, 16), transform((0, 10.45, 0)))
    slit = box(s, (0.22, 1.0, 0.3), dark)
    for index, (angle, y) in enumerate([(0, 4.6), (0, 6.6), (70, 5.6), (-70, 5.6), (180, 6.0)]):
        x = math.sin(math.radians(angle)) * 2.1
        z = math.cos(math.radians(angle)) * 2.1
        mesh(s, "Slit%d" % index, ".", slit, transform((x, y, z), angle), shadow=False)
    mesh(s, "Pole", ".", cylinder(s, 0.05, 0.06, 2.4, wood, 6), transform((0, 13.3, 0)))
    pennant = s.sub_resource("QuadMesh", {
        "material": cloth, "size": "Vector2(2, 0.85)", "subdivide_width": "10", "subdivide_depth": "2",
    })
    s.node("Pennant", "MeshInstance3D", ".", {
        "transform": transform((1.02, 14.05, 0)), "cast_shadow": "0", "mesh": pennant,
        "instance_shader_parameters/field_color": color((0.6, 0.09, 0.1)),
        "instance_shader_parameters/charge_color": color((0.95, 0.76, 0.25)),
    })
    write(ART + "/castle_tower.tscn", s.text())


def wall_scene():
    """A 6 m curtain wall segment along local X, 7 m tall from the water, with merlons on both edges of the wall walk."""
    s = Scene("CastleWall")
    stone = stone_material(s)
    length, thick, height = 6.0, 1.6, 7.0
    mesh(s, "Wall", ".", box(s, (length, height, thick), stone), transform((0, height / 2, 0)))
    mesh(s, "Coping", ".", box(s, (length, 0.25, thick + 0.3), stone), transform((0, height + 0.12, 0)))
    merlon = box(s, (0.85, 0.75, 0.38), stone)
    for index in range(4):
        x = -length / 2 + 0.75 + index * 1.5
        mesh(s, "MerlonN%d" % index, ".", merlon, transform((x, height + 0.62, -thick / 2 + 0.05)))
        mesh(s, "MerlonS%d" % index, ".", merlon, transform((x, height + 0.62, thick / 2 - 0.05)))
    write(ART + "/castle_wall.tscn", s.text())


def gatehouse_scene():
    """A gatehouse facing +Z: a wide block over an arch, a raised portcullis and a pitched roof."""
    s = Scene("CastleGatehouse")
    stone = stone_material(s)
    dark = plain_material(s, (0.04, 0.035, 0.035), 1.0)
    iron = plain_material(s, (0.14, 0.13, 0.13), 0.55, 0.3)
    roof = s.sub_resource("StandardMaterial3D", {"albedo_color": color((0.5, 0.2, 0.14)), "roughness": "0.75"})
    width, depth, height = 7.0, 3.6, 8.2
    mesh(s, "Block", ".", box(s, (width, height, depth), stone), transform((0, height / 2, 0)))
    mesh(s, "Arch", ".", box(s, (3.0, 4.2, 0.1), dark), transform((0, 2.1 + 0.7, depth / 2 + 0.02)), shadow=False)
    mesh(s, "ArchTop", ".", cylinder(s, 1.5, 1.5, 0.1, dark, 16),
         transform((0, 4.9, depth / 2 + 0.02), 0, (1, 1, 1), 90), shadow=False)
    bar = box(s, (0.12, 2.2, 0.12), iron)
    for index in range(6):
        mesh(s, "Bar%d" % index, ".", bar, transform((-1.25 + index * 0.5, 4.3, depth / 2 + 0.12)))
    mesh(s, "CrossBar", ".", box(s, (3.0, 0.14, 0.14), iron), transform((0, 3.35, depth / 2 + 0.12)))
    merlon = box(s, (0.85, 0.8, 0.4), stone)
    for index in range(5):
        x = -width / 2 + 0.7 + index * 1.4
        mesh(s, "Merlon%d" % index, ".", merlon, transform((x, height + 0.4, depth / 2 - 0.1)))
    prism = s.sub_resource("PrismMesh", {"material": roof, "size": vec3(width - 1.2, 2.4, depth - 0.8)})
    mesh(s, "Roof", ".", prism, transform((0, height + 1.2, -0.3)))
    write(ART + "/castle_gatehouse.tscn", s.text())


def banner_scene():
    """A banner hanging from an iron rod, its top edge at the origin, facing +Z."""
    s = Scene("WallBanner")
    cloth = s.sub_resource("ShaderMaterial", {
        "render_priority": "0", "shader": s.ext_resource("Shader", CLOTH_SHADER),
    })
    iron = plain_material(s, (0.12, 0.11, 0.11), 0.6, 0.3)
    quad = s.sub_resource("QuadMesh", {
        "material": cloth, "size": "Vector2(1.3, 3)", "subdivide_width": "2", "subdivide_depth": "12",
    })
    s.node("Cloth", "MeshInstance3D", ".", {"transform": transform((0, -1.55, 0.03)), "mesh": quad})
    mesh(s, "Rod", ".", box(s, (1.7, 0.09, 0.09), iron), transform((0, -0.02, 0.05)))
    write(ART + "/wall_banner.tscn", s.text())


def torch_scene():
    """A wall torch facing +Z: an iron bracket, a flame and a flickering light (reuses the dungeon brazier's script)."""
    s = Scene("WallTorch")
    s.root_props = {"script": s.ext_resource("Script", FLICKER_SCRIPT), "base_energy": "1.4", "flicker_amount": "0.25"}
    iron = plain_material(s, (0.12, 0.11, 0.11), 0.6, 0.3)
    wood = plain_material(s, (0.3, 0.2, 0.12))
    flame = plain_material(s, (2.2, 0.75, 0.15), unshaded=True)
    core = plain_material(s, (2.6, 1.9, 0.6), unshaded=True)
    mesh(s, "Plate", ".", box(s, (0.3, 0.45, 0.08), iron), transform((0, 0, 0.04)))
    mesh(s, "Arm", ".", box(s, (0.08, 0.08, 0.45), iron), transform((0, 0, 0.26)))
    mesh(s, "Stick", ".", cylinder(s, 0.08, 0.05, 0.6, wood, 6), transform((0, 0.18, 0.48), 0, (1, 1, 1), 15))
    flame_mesh = s.sub_resource("SphereMesh", {
        "material": flame, "radius": "0.17", "height": "0.5", "radial_segments": "8", "rings": "4",
    })
    core_mesh = s.sub_resource("SphereMesh", {
        "material": core, "radius": "0.09", "height": "0.28", "radial_segments": "6", "rings": "3",
    })
    mesh(s, "Flame", ".", flame_mesh, transform((0, 0.6, 0.56)), shadow=False)
    mesh(s, "Core", "Flame", core_mesh, transform((0, -0.04, 0)), shadow=False)
    s.node("Light", "OmniLight3D", ".", {
        "transform": transform((0, 0.8, 0.9)), "light_color": color((1, 0.62, 0.3)), "light_energy": "1.4",
        "omni_range": "6.5", "omni_attenuation": "1.2",
    })
    write(ART + "/wall_torch.tscn", s.text())


def rowboat_scene():
    """A moored rowboat, bobbing gently. Origin at the waterline."""
    s = Scene("Rowboat")
    s.root_props = {"script": s.ext_resource("Script", BOB_SCRIPT), "amplitude": "0.06", "period_seconds": "3.2"}
    hull = plain_material(s, (0.4, 0.26, 0.15))
    inside = plain_material(s, (0.24, 0.15, 0.09))
    mesh(s, "Hull", ".", cylinder(s, 0.62, 0.42, 0.5, hull, 14), transform((0, 0.1, 0), 0, (2.3, 1, 1)))
    mesh(s, "Inside", ".", cylinder(s, 0.54, 0.4, 0.42, inside, 14), transform((0, 0.16, 0), 0, (2.3, 1, 1)))
    bench = box(s, (0.22, 0.06, 1.0), hull)
    mesh(s, "Bench1", ".", bench, transform((-0.35, 0.3, 0)))
    mesh(s, "Bench2", ".", bench, transform((0.55, 0.3, 0)))
    oar = box(s, (2.2, 0.04, 0.12), hull)
    mesh(s, "Oar1", ".", oar, transform((0.05, 0.36, 0.3), 12))
    mesh(s, "Oar2", ".", oar, transform((0.05, 0.36, -0.3), -12))
    write(ART + "/rowboat.tscn", s.text())


def reeds_scene():
    """A clump of reeds and cattails. Origin at the waterline."""
    s = Scene("Reeds")
    green = plain_material(s, (0.36, 0.48, 0.18))
    yellow = plain_material(s, (0.55, 0.55, 0.22))
    brown = plain_material(s, (0.3, 0.18, 0.1))
    blade_a = cylinder(s, 0.0, 0.05, 1.6, green, 4)
    blade_b = cylinder(s, 0.0, 0.05, 1.2, yellow, 4)
    head = cylinder(s, 0.07, 0.07, 0.32, brown, 6)
    rng = random.Random(7)
    for index in range(14):
        x, z = rng.uniform(-0.9, 0.9), rng.uniform(-0.6, 0.6)
        tall = index % 3 != 0
        tilt_x, tilt_z = rng.uniform(-14, 14), rng.uniform(-14, 14)
        mesh(s, "Blade%d" % index, ".", blade_a if tall else blade_b,
             transform((x, 0.7 if tall else 0.5, z), rng.uniform(0, 360), (1, 1, 1), tilt_x, tilt_z), shadow=False)
        if index % 4 == 0:
            mesh(s, "Head%d" % index, ".", head, transform((x, 1.3, z)), shadow=False)
    write(ART + "/reeds.tscn", s.text())


def lily_pads_scene():
    """A few lily pads with a flower, lying on the water."""
    s = Scene("LilyPads")
    pad_mat = plain_material(s, (0.22, 0.45, 0.16))
    flower_mat = plain_material(s, (0.96, 0.8, 0.86))
    pad = cylinder(s, 0.42, 0.42, 0.03, pad_mat, 12)
    flower = s.sub_resource("SphereMesh", {
        "material": flower_mat, "radius": "0.12", "height": "0.14", "radial_segments": "8", "rings": "3",
    })
    rng = random.Random(3)
    for index in range(6):
        x, z = rng.uniform(-1.4, 1.4), rng.uniform(-1.0, 1.0)
        size = rng.uniform(0.6, 1.2)
        mesh(s, "Pad%d" % index, ".", pad, transform((x, 0.03, z), 0, (size, 1, size)), shadow=False)
        if index % 3 == 0:
            mesh(s, "Flower%d" % index, ".", flower, transform((x, 0.08, z)), shadow=False)
    write(ART + "/lily_pads.tscn", s.text())



def bridge_scene():
    """bridge_platform.tscn with its wooden pillar hidden behind a stone pier and a plank deck. Inherited, so the
    script, animations, collision and footstep metadata are the original's. The pier moves, so its shader works in
    local space."""
    s = Scene("CastleBridgePlatform")
    s.root_instance = s.ext_resource("PackedScene", "res://src/world/elements/bridge_platform.tscn", "uid://chaj7v8uajl4q")
    pier = s.sub_resource("ShaderMaterial", {
        "render_priority": "0", "shader": s.ext_resource("Shader", STONE_SHADER),
        "shader_parameter/timber_top": "true", "shader_parameter/local_space": "true",
        "shader_parameter/water_y": "-4.2", "shader_parameter/damp_height": "1.4",
    })
    beam_mat = plain_material(s, (0.26, 0.16, 0.09))
    s.node("Wooden_Platform_Top", None, "AnimatableBody3D", {"visible": "false"})
    mesh(s, "Pier", "AnimatableBody3D", box(s, (3.0, 5.18, 3.0), pier), transform((0, -2.59, 0)))
    beam = box(s, (3.0, 0.16, 0.2), beam_mat)
    mesh(s, "EdgeBeamA", "AnimatableBody3D", beam, transform((0, -0.07, 1.4)))
    mesh(s, "EdgeBeamB", "AnimatableBody3D", beam, transform((0, -0.07, -1.4)))
    write(ART + "/castle_bridge_platform.tscn", s.text())


def turret_scene():
    """Dresses a mage pillar as a little stone turret. Origin where the pillar's mesh sits: its collision is a
    0.95 m column from y = -6.93 to 0.85, which this matches. No collision of its own."""
    s = Scene("MageTurret")
    stone = stone_material(s)
    torch = s.ext_resource("PackedScene", RES_ART + "/wall_torch.tscn")
    top = 0.85
    mesh(s, "Shaft", ".", cylinder(s, 0.97, 1.08, 7.8, stone, 14), transform((0, top - 3.9, 0)))
    mesh(s, "Corbel", ".", cylinder(s, 1.32, 0.97, 0.5, stone, 14), transform((0, top - 0.25, 0)))
    merlon = box(s, (0.42, 0.45, 0.28), stone)
    for index in range(8):
        angle = index * 45.0 + 22.5
        x = math.sin(math.radians(angle)) * 1.18
        z = math.cos(math.radians(angle)) * 1.18
        mesh(s, "Merlon%d" % index, ".", merlon, transform((x, top + 0.22, z), angle))
    s.node("Torch", None, ".", {"transform": transform((0, top - 1.1, 1.02))}, instance=torch)
    write(ART + "/mage_turret.tscn", s.text())


def write_props():
    tower_scene()
    wall_scene()
    gatehouse_scene()
    banner_scene()
    torch_scene()
    rowboat_scene()
    reeds_scene()
    lily_pads_scene()
    bridge_scene()
    turret_scene()


PROPS = {
    "tower": "castle_tower", "wall": "castle_wall", "gatehouse": "castle_gatehouse", "banner": "wall_banner",
    "torch": "wall_torch", "boat": "rowboat", "reeds": "reeds", "lilies": "lily_pads", "turret": "mage_turret",
}


# ---------------------------------------------------------------- shared level pieces

TOWER_CLEARANCE = 2.4
SEGMENT = 6.0


def wall_segments(x0, z0, x1, z1):
    length = math.hypot(x1 - x0, z1 - z0)
    usable = length - 2 * TOWER_CLEARANCE
    count = max(1, math.ceil(usable / SEGMENT - 0.05))
    yaw = -math.degrees(math.atan2(z1 - z0, x1 - x0))
    stretch = usable / (count * SEGMENT)
    out = []
    for index in range(count):
        t = (TOWER_CLEARANCE + (index + 0.5) * usable / count) / length
        out.append((x0 + (x1 - x0) * t, z0 + (z1 - z0) * t, yaw, stretch))
    return out


def heraldry_params(index):
    field, charge_color, charge = HERALDRY[index % len(HERALDRY)]
    return {
        "instance_shader_parameters/charge": str(charge),
        "instance_shader_parameters/charge_color": color(charge_color),
        "instance_shader_parameters/field_color": color(field),
    }


def make_replacer():
    def replace_once(text, old, new):
        assert text.count(old) == 1, "expected exactly one match for: " + old[:90]
        return text.replace(old, new)
    return replace_once


# Golden afternoon over the moat. The sky stays the original panorama, because the sword's blade reflects it:
# a warm procedural sky turned the blade purple. Ambient light comes from a warm colour instead of that sky.
ENVIRONMENT = """[sub_resource type="Environment" id="Environment_msrya"]
background_mode = 2
sky = SubResource("Sky_8eeh1")
ambient_light_source = 2
ambient_light_color = Color(0.8, 0.74, 0.66, 1)
ambient_light_energy = 0.6
reflected_light_source = 2
tonemap_mode = 3
tonemap_white = 6.0
ssao_enabled = true
ssao_radius = 1.2
ssao_intensity = 1.6
glow_enabled = true
glow_intensity = 0.5
glow_bloom = 0.03
glow_hdr_threshold = 1.05
fog_enabled = true
fog_light_color = Color(0.86, 0.76, 0.64, 1)
fog_density = 0.0022
fog_aerial_perspective = 0.35
fog_sky_affect = 0.3

"""

WATER_MATERIAL = """[sub_resource type="ShaderMaterial" id="ShaderMaterial_moat"]
render_priority = 0
shader = ExtResource("m_water")
shader_parameter/water_color = Color(0.05, 0.19, 0.2, 1)
shader_parameter/foam_color = Color(0.42, 0.56, 0.5, 1)
shader_parameter/wave_scale = 0.8
shader_parameter/wave_scale_detail = 1.2

"""

# Low sun from the west, a little north, so shadows fall east and slightly towards the camera.
LIGHT = "transform = %s\nlight_color = Color(1, 0.87, 0.7, 1)\nlight_energy = 1.3\nshadow_enabled = true\n" % look_transform(
    (0.62, -0.72, 0.3), (0, 8, 0))




# ---------------------------------------------------------------- editing a copied level

DECORATION_ROOT = "Level/Medieval"
CELL = 2.999


class Reskin:
    """Edits a copy of a level's .tscn text. Each edit must match exactly once, so a changed source fails loudly
    instead of quietly producing something else. Nothing here touches gameplay nodes' transforms or collision."""

    def __init__(self, source):
        text = open(source).read()
        header = text.split("\n", 1)[0]
        assert header.startswith("[gd_scene"), header
        # A new scene: drop the original's uid so the two don't collide. load_steps is optional, but the format
        # must stay: format 4 stores packed arrays (meshes) in base64.
        file_format = re.search(r"format=(\d+)", header).group(1)
        self.text = "[gd_scene format=%s]" % file_format + text[len(header):]
        self.ext_lines = []
        self.sub_blocks = []
        self.refs = {}

    def replace(self, old, new):
        assert self.text.count(old) == 1, "expected exactly one match for: " + old[:100]
        self.text = self.text.replace(old, new)

    def find(self, pattern):
        matches = list(re.finditer(pattern, self.text))
        assert len(matches) == 1, "expected exactly one match for /%s/, got %d" % (pattern, len(matches))
        return matches[0]

    def swap_ext(self, old_path, new_path, uid=None):
        """Points an ext_resource at another file, keeping its id. Returns the id."""
        m = self.find(r'\[ext_resource type="([^"]+)"(?: uid="[^"]*")? path="%s" id="([^"]+)"\]' % re.escape(old_path))
        uid_text = ' uid="%s"' % uid if uid else ""
        self.replace(m.group(0), '[ext_resource type="%s"%s path="%s" id="%s"]' % (m.group(1), uid_text, new_path, m.group(2)))
        return m.group(2)

    def add_ext(self, kind, path, rid, uid=None):
        uid_text = ' uid="%s"' % uid if uid else ""
        self.ext_lines.append('[ext_resource type="%s"%s path="%s" id="%s"]' % (kind, uid_text, path, rid))
        return 'ExtResource("%s")' % rid

    def add_props(self):
        for key, file_name in PROPS.items():
            self.refs[key] = self.add_ext("PackedScene", "%s/%s.tscn" % (RES_ART, file_name), "m_" + key)

    def castle_arrow_colors(self):
        """The siege bow's pale aim guide and arrow shafts blend into the sandstone: heraldic crimson and walnut."""
        root = self.find(r'\[node name="WorldLocal" type="Node3D"\]\nscript = ExtResource\("[^"]+"\)\n')
        self.replace(root.group(0), root.group(0) + ARROW_COLORS)

    def castle_tiles(self):
        self.swap_ext("res://assets/mesh_library/tiles_Color7_no_shadows.tres", RES_ART + "/castle_tiles.tres")

    def castle_music(self):
        m = self.find(r'\[ext_resource type="AudioStream"[^\n]*\]')
        rid = re.search(r' id="([^"]+)"\]', m.group(0)).group(1)
        self.replace(m.group(0), '[ext_resource type="AudioStream" uid="%s" path="%s" id="%s"]' % (MUSIC_UID, MUSIC_PATH, rid))
        self.text = self.text.replace("volume_db = -20.14", "volume_db = -18.0")

    def castle_environment(self):
        block = self.find(r'\[sub_resource type="Environment" id="([^"]+)"\]\n[\s\S]*?\n\n')
        sky = self.find(r'\[sub_resource type="Sky" id="([^"]+)"\]').group(1)
        new = ENVIRONMENT.replace('id="Environment_msrya"', 'id="%s"' % block.group(1)).replace('"Sky_8eeh1"', '"%s"' % sky)
        self.replace(block.group(0), new)

    def castle_light(self):
        block = self.find(r'(\[node name="DirectionalLight3D" type="DirectionalLight3D" parent="\."\]\n)([\s\S]*?\n)\n')
        extras = [line for line in block.group(2).splitlines() if line.startswith("shadow_") and not line.startswith("shadow_enabled")]
        self.replace(block.group(0), block.group(1) + LIGHT + "".join(line + "\n" for line in extras) + "\n")

    def moat(self):
        water = self.find(r'\[node name="Water" parent="Level" instance=ExtResource\("[^"]+"\)\]\n(?:transform = [^\n]*\n)?')
        self.replace(water.group(0), water.group(0) + 'surface_material_override/0 = SubResource("ShaderMaterial_moat")\n')
        self.add_ext("Shader", "res://water.gdshader", "m_water", "uid://1omvlp44jb2k")
        self.sub_blocks.append(WATER_MATERIAL)

    def water_y(self):
        water = self.find(r'\[node name="Water" parent="Level" instance=ExtResource\("[^"]+"\)\]\n(?:transform = Transform3D\(([^)]*)\)\n)?')
        if not water.group(1):
            return 0.0
        return float(water.group(1).split(",")[10])

    def _used(self, ext_line):
        rid = re.search(r' id="([^"]+)"\]', ext_line).group(1)
        return 'ExtResource("%s")' % rid in self.text + "".join(self.sub_blocks)

    def insert_decoration(self, decoration, before='[node name="Bridges" type="Node" parent="Level"]'):
        self.replace(before, decoration.text() + "\n" + before)

    def write(self, out, force):
        if os.path.exists(out) and not force:
            raise SystemExit("%s exists; pass --force to overwrite it (diff a copy first: it may hold editor changes)" % out)
        # Leave out props this level doesn't use.
        used = [line for line in self.ext_lines if self._used(line)]
        first_sub = self.text.index("[sub_resource")
        text = self.text[:first_sub] + "\n".join(used) + "\n\n" + self.text[first_sub:]
        first_node = text.index("[node ")
        text = text[:first_node] + "".join(self.sub_blocks) + text[first_node:]
        write(out, text)


class Decoration:
    """Builds the Level/Medieval node and its groups of prop instances, as scene text."""

    def __init__(self, refs, groups):
        self.refs = refs
        self.groups = groups
        self.blocks = []
        self.counts = {}

    def add(self, group, prop, xform, extra=None, name=None):
        assert group in self.groups, group
        self.counts[prop] = self.counts.get(prop, 0) + 1
        name = name or "%s%d" % (PROPS[prop].title().replace("_", ""), self.counts[prop])
        lines = ['[node name="%s" parent="%s/%s" instance=%s]' % (name, DECORATION_ROOT, group, self.refs[prop]),
                 "transform = " + xform]
        lines += ["%s = %s" % (k, v) for k, v in (extra or {}).items()]
        self.blocks.append("\n".join(lines) + "\n")

    def text(self):
        parent, name = DECORATION_ROOT.rsplit("/", 1)
        head = ['[node name="%s" type="Node3D" parent="%s"]\n' % (name, parent)]
        head += ['[node name="%s" type="Node3D" parent="%s"]\n' % (group, DECORATION_ROOT) for group in self.groups]
        return "\n".join(head + self.blocks)


def gridmap_cells(text, node_name):
    """(x, y, z, item, orientation) for every cell of the named GridMap in a scene's text."""
    m = re.search(r'\[node name="%s" type="GridMap"[\s\S]*?"cells": PackedInt32Array\(([^)]*)\)' % re.escape(node_name), text)
    values = [int(v) for v in m.group(1).split(",")]
    cells = []
    for index in range(0, len(values), 3):
        packed = values[index]
        x = signed16(packed & 0xFFFF)
        y = signed16((packed >> 16) & 0xFFFF)
        z = signed16(values[index + 1] & 0xFFFF)
        cells.append((x, y, z, values[index + 2] & 0xFFFF, (values[index + 2] >> 16) & 0xFF))
    return cells


def signed16(v):
    return v - 65536 if v >= 32768 else v


def cell_centre(cx, cz):
    return ((cx + 0.5) * CELL, (cz + 0.5) * CELL)


ARROW_COLORS = "aim_guide_color = Color(0.85, 0.12, 0.1, 0.5)\narrow_shaft_color = Color(0.3, 0.18, 0.1, 1)\n"


# Where props hang, shared by the levels.
WALL_HEIGHT = 7.0
# Measured from the hill tiles (GridMap cells at y = -1 with 2 m cells put a tile's top at y = -1):
# the walkable top is at y = -1; its rounded lip hangs 0.7 m down and reaches 0.25 m short of the cell edge;
# the cliff below runs from y = -1.3 to the water, its bulges reaching 0.5 m short of the cell edge.
FLOOR_TOP_Y = -1.0
CLIFF_LIP_DEPTH = 0.7
# Banners hang from just under the lip, shortened so they stay above the water.
CLIFF_TOP_Y = FLOOR_TOP_Y - CLIFF_LIP_DEPTH - 0.05
CLIFF_BANNER_SCALE = (1.0, 0.8, 1.0)
CLIFF_TORCH_Y = FLOOR_TOP_Y - 1.5
# A south cliff face's frontmost point relative to the cell edge (negative: behind it). Banners and torch
# brackets go here so they touch the stone.
CLIFF_OUT = -0.48
# How far below the wall top a torch hangs, and a banner's rod.
WALL_TORCH_DROP = 2.3
WALL_BANNER_DROP = 0.3
