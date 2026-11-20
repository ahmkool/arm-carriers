"""Builds the night rooftops' props and exports them to assets/models/rooftops/, one .glb each.

Run: /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_rooftop_props.py

These were first built in Godot out of BoxMesh / CylinderMesh / SphereMesh nodes, one node per part, so an HVAC
unit cost ten draw calls. Here the same parts, at the same sizes and places, are joined into one mesh per model with
one surface per material, which is what Godot draws. Godot's look is kept exactly: every material slot is named
after a material in src/world/elements/rooftops/materials/, and each .glb's .import file maps the slot to that
material (`_subresources`), so the colours, unshaded HDR glows and the bridge deck's shader stay Godot's own.

Each model has up to three kinds of mesh object, because Godot sets shadows per mesh node:
- Body: parts that cast shadows.
- Glow: lit-up parts that don't (LEDs, lenses, the skylight glass). Its scene turns cast_shadow off on it.
- Named parts a script or shader needs on their own: the beacon's Bulb (beacon_pulse.gd tints it), the bridge's
  Deck (its shader reads the deck's own local vertex positions), and the HVAC fan's Blades (spun by rotor_spin.gd).

Parts are given in Godot space: sizes are BoxMesh / CylinderMesh / SphereMesh sizes, and a transform is either an
(x, y, z) offset or Godot's 12 Transform3D numbers (basis x, y, z columns, then origin). Cylinders and spheres are
made the way Godot makes them, first vertex on +Z, so their facets line up with the old ones.
"""
import math
import os

import bmesh
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "models", "rooftops")

# Level pieces are in level space, moved so the model's origin is where its scene is placed:
# the bridge framing round the bridge's middle, the helipad lights round the helipad, the mast at its foot.
FLOOR_TOP = -1.0
BRIDGE_MID_Z = -17.994
SOUTH_EDGE_Z = -11.996 - BRIDGE_MID_Z
NORTH_EDGE_Z = -23.992 - BRIDGE_MID_Z
NORTH_STRUT = (1, 0, 0, 0, 0.7431448, 0.6691306, 0, -0.6691306, 0.7431448)
SOUTH_STRUT = (1, 0, 0, 0, 0.7431448, -0.6691306, 0, 0.6691306, 0.7431448)


def _bridge_framing():
    parts = [
        ("Body", "box", (6.16, 0.04, 0.56), (0, FLOOR_TOP + 0.015, SOUTH_EDGE_Z + 0.24), "rooftop_steel_bright"),
        ("Body", "box", (6.16, 0.04, 0.56), (0, FLOOR_TOP + 0.015, NORTH_EDGE_Z - 0.24), "rooftop_steel_bright"),
    ]
    for px, pz in ((-3.16, SOUTH_EDGE_Z + 0.22), (3.16, SOUTH_EDGE_Z + 0.22), (-3.16, NORTH_EDGE_Z - 0.22), (3.16, NORTH_EDGE_Z - 0.22)):
        parts.append(("Body", "box", (0.36, 1.15, 0.36), (px, FLOOR_TOP + 0.575, pz), "rooftop_steel_dark"))
        parts.append(("Glow", "box", (0.18, 0.12, 0.18), (px, FLOOR_TOP + 1.21, pz), "rooftop_amber_glow"))
    for sx in (-2.75, -0.95, 0.95, 2.75):
        parts.append(("Body", "box", (0.20, 0.22, 2.75), NORTH_STRUT + (sx, -2.18, NORTH_EDGE_Z + 0.98), "rooftop_steel_dark"))
        parts.append(("Body", "box", (0.42, 0.90, 0.14), (sx, -3.05, NORTH_EDGE_Z + 0.05), "rooftop_steel_dark"))
        parts.append(("Body", "box", (0.20, 0.22, 2.75), SOUTH_STRUT + (sx, -2.18, SOUTH_EDGE_Z - 0.98), "rooftop_steel_dark"))
    return [("rooftop_bridge_framing",) + part for part in parts]


def _helipad_lights():
    return [("rooftop_helipad_lights", "Glow", "box", (0.22, 0.04, 0.22), (dx, 0.02, dz), "rooftop_heli_led")
            for dx, dz in ((-5.2, 0.0), (5.2, 0.0), (0.0, -5.2), (0.0, 5.2))]


def _comms_mast():
    arm = (1.65, 0.06, 0.06)
    return [
        ("rooftop_comms_mast", "Body", "cyl", (0.14, 0.28, 3.6, 8), (0, 1.8, 0), "rooftop_steel_dark"),
        ("rooftop_comms_mast", "Body", "cyl", (0.04, 0.12, 3.2, 8), (0, 5.1, 0), "rooftop_steel_bright"),
        ("rooftop_comms_mast", "Body", "box", arm, (0, 4.1, 0), "rooftop_steel_bright"),
        ("rooftop_comms_mast", "Body", "box", arm, (0.7, 0, 0.7, 0, 1, 0, -0.7, 0, 0.7, 0, 5.4, 0), "rooftop_steel_bright"),
    ]


def _cover_panel():
    """A steel billboard on a frame, standing in the Godot YZ plane with its face to -X (west). It is cover the
    carriers' shots can't pass (rooftop_cover_panel.tscn, a ShotCover): a plate 2.4 m wide from the roof up to
    2.4 m, framed, braced behind, with neon strips on its face and along its top, where the camera sees it."""
    brace = (0.885, 0.4646, 0, -0.4646, 0.885, 0, 0, 0, 1)
    parts = [
        ("Body", "box", (0.12, 2.3, 2.4), (0, 1.25, 0), "cover_panel_face"),
        ("Body", "box", (0.18, 0.12, 2.6), (0, 2.46, 0), "cover_panel_steel"),
        ("Body", "box", (0.18, 0.12, 2.6), (0, 0.06, 0), "cover_panel_steel"),
        ("Body", "box", (0.18, 2.52, 0.12), (0, 1.26, -1.24), "cover_panel_steel"),
        ("Body", "box", (0.18, 2.52, 0.12), (0, 1.26, 1.24), "cover_panel_steel"),
        ("Body", "box", (0.08, 2.26, 0.08), brace + (0.575, 1.0, -0.9), "cover_panel_steel"),
        ("Body", "box", (0.08, 2.26, 0.08), brace + (0.575, 1.0, 0.9), "cover_panel_steel"),
        ("Body", "box", (1.3, 0.05, 0.25), (0.55, 0.025, -0.9), "cover_panel_steel"),
        ("Body", "box", (1.3, 0.05, 0.25), (0.55, 0.025, 0.9), "cover_panel_steel"),
        ("Glow", "box", (0.03, 0.08, 2.2), (-0.075, 2.05, 0), "cover_panel_neon"),
        ("Glow", "box", (0.03, 0.08, 2.2), (-0.075, 0.45, 0), "cover_panel_neon"),
        ("Glow", "box", (0.03, 1.5, 0.08), (-0.075, 1.25, -1.0), "cover_panel_neon"),
        ("Glow", "box", (0.2, 0.03, 2.5), (0, 2.535, 0), "cover_panel_neon"),
    ]
    return [("rooftop_cover_panel",) + part for part in parts]


# (model, object, kind, size, transform, material). Read off the original Godot scenes, part for part.
PARTS = [
    # rooftop_hvac.tscn
    ("rooftop_hvac", "Body", "box", (2.36, 0.16, 1.86), (0, 0.08, 0), "hvac_dark"),  # Plinth
    ("rooftop_hvac", "Body", "box", (2.2, 1.05, 1.7), (0, 0.68, 0), "hvac_casing"),  # Body
    ("rooftop_hvac", "Body", "cyl", (0.58, 0.62, 0.16, 16), (-0.38, 1.25, 0), "hvac_dark"),  # FanShroud
    ("rooftop_hvac", "Body", "cyl", (0.5, 0.5, 0.06, 16), (-0.38, 1.305, 0), "hvac_well"),  # FanWell
    ("rooftop_hvac", "Body", "box", (0.42, 0.36, 0.52), (0.62, 1.28, -0.22), "hvac_casing"),  # Duct
    ("rooftop_hvac", "Body", "box", (0.76, 0.62, 0.06), (-0.48, 0.68, 0.85), "hvac_dark"),  # LouverSouth1
    ("rooftop_hvac", "Body", "box", (0.76, 0.62, 0.06), (0.48, 0.68, 0.85), "hvac_dark"),  # LouverSouth2
    ("rooftop_hvac", "Glow", "box", (0.08, 0.08, 0.04), (0.94, 0.98, 0.85), "hvac_led"),  # StatusLed
    # The fan, spun by FanRotor in rooftop_hvac.tscn, so it is a model of its own.
    ("rooftop_hvac_fan", "Blades", "box", (0.88, 0.03, 0.16), (0, 0, 0), "hvac_casing"),  # Blade1
    ("rooftop_hvac_fan", "Blades", "box", (0.88, 0.03, 0.16), (0, 0, 1, 0, 1, 0, -1, 0, 0, 0, 0, 0), "hvac_casing"),  # Blade2
    # rooftop_beacon.tscn
    ("rooftop_beacon", "Body", "cyl", (0.11, 0.14, 0.12, 10), (0, 0.06, 0), "beacon_mast"),  # Base
    ("rooftop_beacon", "Body", "cyl", (0.035, 0.045, 0.55, 8), (0, 0.36, 0), "beacon_mast"),  # Post
    ("rooftop_beacon", "Bulb", "sphere", (0.095, 0.19, 12, 6), (0, 0.68, 0), "beacon_bulb"),  # Bulb
    # rooftop_light_post.tscn
    ("rooftop_light_post", "Body", "box", (0.24, 0.92, 0.24), (0, 0.46, 0), "light_post_body"),  # Post
    ("rooftop_light_post", "Glow", "box", (0.26, 0.14, 0.26), (0, 0.96, 0), "light_post_lamp"),  # Lens
    ("rooftop_light_post", "Body", "box", (0.32, 0.1, 0.32), (0, 1.07, 0), "light_post_body"),  # Cap
    # rooftop_penthouse.tscn
    ("rooftop_penthouse", "Body", "box", (2.55, 2.35, 2.45), (0, 1.175, 0), "penthouse_concrete"),  # Walls
    ("rooftop_penthouse", "Body", "box", (2.4, 0.12, 2.3), (0, 1.1, 0), "penthouse_concrete"),  # NavBaffle, inside the walls
    ("rooftop_penthouse", "Body", "box", (2.75, 0.18, 2.65), (0, 2.42, 0), "penthouse_cap"),  # RoofCap
    ("rooftop_penthouse", "Body", "cyl", (0.09, 0.09, 0.85, 10), (0.68, 2.86, 0.35), "penthouse_cap"),  # VentPipe2
    ("rooftop_penthouse", "Body", "box", (1.12, 1.88, 0.12), (0, 0.94, 1.22), "penthouse_cap"),  # DoorFrame
    ("rooftop_penthouse", "Body", "box", (0.94, 1.76, 0.08), (0, 0.88, 1.25), "penthouse_door"),  # Door
    ("rooftop_penthouse", "Body", "box", (1.36, 0.09, 0.46), (0, 1.96, 1.38), "penthouse_cap"),  # Canopy
    ("rooftop_penthouse", "Glow", "box", (0.32, 0.12, 0.14), (0, 2.12, 1.28), "penthouse_sconce"),  # Sconce
    ("rooftop_penthouse", "Body", "cyl", (0.09, 0.09, 0.85, 10), (-0.78, 2.86, -0.62), "penthouse_cap"),  # VentPipe
    # rooftop_skylight.tscn
    ("rooftop_skylight", "Body", "box", (2.5, 0.28, 2.5), (0, 0.14, 0), "skylight_frame"),  # Curb
    ("rooftop_skylight", "Glow", "box", (2.22, 0.12, 2.22), (0, 0.31, 0), "skylight_glass"),  # Glass
    ("rooftop_skylight", "Body", "box", (2.32, 0.16, 0.08), (0, 0.32, -0.56), "skylight_frame"),  # MullionX1
    ("rooftop_skylight", "Body", "box", (2.32, 0.16, 0.08), (0, 0.32, 0.56), "skylight_frame"),  # MullionX2
    ("rooftop_skylight", "Body", "box", (0.08, 0.16, 2.32), (-0.56, 0.32, 0), "skylight_frame"),  # MullionZ1
    ("rooftop_skylight", "Body", "box", (0.08, 0.16, 2.32), (0.56, 0.32, 0), "skylight_frame"),  # MullionZ2
    # rooftop_metal_bridge_platform.tscn, relative to AnimatableBody3D/Visual
    ("rooftop_metal_bridge_platform", "Deck", "box", (2.999, 0.18, 2.999), (0, -0.09, 0), "bridge_deck"),  # Deck
    ("rooftop_metal_bridge_platform", "Body", "box", (0.18, 0.44, 2.999), (-1.41, -0.08, 0), "bridge_girder"),  # OuterGirder
    ("rooftop_metal_bridge_platform", "Body", "box", (0.12, 0.1, 2.999), (-1.41, -0.68, 0), "bridge_girder"),  # LowerChord
    ("rooftop_metal_bridge_platform", "Body", "box", (0.07, 0.07, 1.48), (1, 0, 0, 0, 0.9455186, -0.3255682, 0, 0.3255682, 0.9455186, -1.41, -0.45, -0.72), "bridge_girder"),  # TrussBrace1
    ("rooftop_metal_bridge_platform", "Body", "box", (0.07, 0.07, 1.48), (1, 0, 0, 0, 0.9455186, 0.3255682, 0, -0.3255682, 0.9455186, -1.41, -0.45, 0.72), "bridge_girder"),  # TrussBrace2
    ("rooftop_metal_bridge_platform", "Body", "box", (2.98, 0.24, 0.16), (0, -0.28, -0.75), "bridge_girder"),  # CrossBeam1
    ("rooftop_metal_bridge_platform", "Body", "box", (2.98, 0.24, 0.16), (0, -0.28, 0.75), "bridge_girder"),  # CrossBeam2
    ("rooftop_metal_bridge_platform", "Body", "box", (0.08, 0.06, 2.999), (-1.42, 0.5, 0), "bridge_rail"),  # HandrailTop
    ("rooftop_metal_bridge_platform", "Body", "box", (0.045, 0.035, 2.999), (-1.42, 0.3, 0), "bridge_rail"),  # HandrailMid
    ("rooftop_metal_bridge_platform", "Body", "box", (0.09, 0.52, 0.1), (-1.42, 0.25, -0.75), "bridge_girder"),  # Stanchion1
    ("rooftop_metal_bridge_platform", "Body", "box", (0.09, 0.52, 0.1), (-1.42, 0.25, 0.75), "bridge_girder"),  # Stanchion2
    ("rooftop_metal_bridge_platform", "Glow", "box", (0.035, 0.035, 2.86), (-1.3, 0.08, 0), "bridge_led"),  # SafetyLedStrip
] + _bridge_framing() + _helipad_lights() + _comms_mast() + _cover_panel()

# Objects whose origin isn't the model's: the deck's shader works in the deck's own space.
OBJECT_ORIGINS = {("rooftop_metal_bridge_platform", "Deck"): (0, -0.09, 0)}


def _to_blender(p):
    # Godot (x, y, z) -> Blender (x, -z, y): the glTF exporter maps Blender -Y back to Godot +Z.
    return (p[0], -p[2], p[1])


def _transform(t, origin):
    """A function taking a Godot-space point through `t`, then relative to the object's origin."""
    if len(t) == 3:
        basis = (1, 0, 0, 0, 1, 0, 0, 0, 1)
        offset = t
    else:
        basis = t[:9]
        offset = t[9:]

    def apply(p):
        x = basis[0] * p[0] + basis[3] * p[1] + basis[6] * p[2] + offset[0] - origin[0]
        y = basis[1] * p[0] + basis[4] * p[1] + basis[7] * p[2] + offset[1] - origin[1]
        z = basis[2] * p[0] + basis[5] * p[1] + basis[8] * p[2] + offset[2] - origin[2]
        return _to_blender((x, y, z))
    return apply


def _box(size):
    hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    corners = [(sx * hx, sy * hy, sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return corners, faces, set()


def _cylinder(size):
    """Like Godot's CylinderMesh: a ring of `segments` round the Y axis, first vertex on +Z."""
    top, bottom, height, segments = size
    verts = []
    for radius, y in ((bottom, -height / 2.0), (top, height / 2.0)):
        for i in range(segments):
            a = i * math.tau / segments
            verts.append((math.sin(a) * radius, y, math.cos(a) * radius))
    sides = [(i, (i + 1) % segments, segments + (i + 1) % segments, segments + i) for i in range(segments)]
    caps = [tuple(range(segments)), tuple(range(segments, 2 * segments))]
    return verts, sides + caps, set(range(len(sides)))


def _sphere(size):
    """Like Godot's SphereMesh: `rings` bands between the poles, `segments` round, first meridian on +Z."""
    radius, height, segments, rings = size
    verts = [(0.0, height / 2.0, 0.0)]
    for j in range(1, rings + 1):
        v = j / (rings + 1)
        w = math.sin(math.pi * v)
        y = math.cos(math.pi * v) * height / 2.0
        for i in range(segments):
            a = i * math.tau / segments
            verts.append((math.sin(a) * radius * w, y, math.cos(a) * radius * w))
    verts.append((0.0, -height / 2.0, 0.0))
    south = len(verts) - 1
    faces = [(0, 1 + (i + 1) % segments, 1 + i) for i in range(segments)]
    for j in range(rings - 1):
        row = 1 + j * segments
        nxt = row + segments
        faces += [(row + i, row + (i + 1) % segments, nxt + (i + 1) % segments, nxt + i) for i in range(segments)]
    last = 1 + (rings - 1) * segments
    faces += [(last + i, last + (i + 1) % segments, south) for i in range(segments)]
    return verts, faces, set(range(len(faces)))


SHAPES = {"box": _box, "cyl": _cylinder, "sphere": _sphere}


def _material(name):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    return mat


def _build_object(model, obj_name, parts):
    origin = OBJECT_ORIGINS.get((model, obj_name), (0, 0, 0))
    mesh = bpy.data.meshes.new(obj_name)
    obj = bpy.data.objects.new(obj_name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = _to_blender(origin)
    slots = []
    bm = bmesh.new()
    for kind, size, t, mat_name in parts:
        if mat_name not in slots:
            slots.append(mat_name)
            mesh.materials.append(_material(mat_name))
        apply = _transform(t, origin)
        verts, faces, smooth = SHAPES[kind](size)
        bverts = [bm.verts.new(apply(v)) for v in verts]
        for index, face in enumerate(faces):
            f = bm.faces.new([bverts[i] for i in face])
            f.material_index = slots.index(mat_name)
            f.smooth = index in smooth
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # A smooth side meeting a flat cap is a hard edge, as in Godot's cylinders.
    for edge in bm.edges:
        if len(edge.link_faces) == 2 and edge.link_faces[0].smooth != edge.link_faces[1].smooth:
            edge.smooth = False
    bm.to_mesh(mesh)
    bm.free()
    return obj


def build(model):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects = {}
    for part in PARTS:
        if part[0] != model:
            continue
        objects.setdefault(part[1], []).append(part[2:])
    for obj_name, parts in objects.items():
        _build_object(model, obj_name, parts)
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, model + ".blend"))
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_DIR, model + ".glb"),
        export_format="GLB",
        use_selection=False,
        export_apply=True,
    )


for name in sorted({part[0] for part in PARTS}):
    build(name)
