#!/usr/bin/env python3
"""Night Rooftops level prototype: world_local_night_rooftops.tscn ("Night Rooftops", in the Dev tab).

Two high-rise skyscraper rooftops at night connected by an industrial 6 m x 12 m metallic truss skybridge:
- Building 1 (South Tower): concrete membrane slab, perimeter steel-capped parapet, stairwell bulkhead with warm
  security sconce, spinning HVAC units, and pulsing red corner aviation warning beacons.
- Metallic Bridge: brushed steel diamond-plate & slotted catwalk grating, yellow/black hazard curbs, open steel
  side trusses & handrails, cyan safety LED strips, and diagonal steel brackets bolted into the tower facades.
- Building 2 (North Tower): wider corporate high-rise rooftop with weathered helipad "H" markings, glowing glass
  atrium skylights, HVAC bank, and a north parapet comms mast, above a deep nocturnal cityscape of lit windows,
  drifting midnight mist, and moving street traffic 20+ stories below.

Run from the project root; see docs/level-creation-for-agents.md for the bake / regenerate steps.
"""
import sys

from levelgen import AREAS, BRIDGE_Y, CELL, EVENTS, FACE_SOUTH, Level, fmt, node_paths, rect, tf, world

OUT = "src/world/levels/world_local_night_rooftops.tscn"
FLOOR_TOP = -1.0

# ---- Building footprints (grid cells). Forward is -z; x in -5..4 centres on world x = 0. ----
B1_MAIN = rect(-5, 4, -4, 3)       # 30 m x 24 m south skyscraper rooftop
B1_WING = rect(-7, -6, -2, 2)      # 6 m x 15 m west architectural wing
BUILDING_1 = B1_MAIN | B1_WING

B2_MAIN = rect(-6, 5, -17, -9)     # 36 m x 27 m north skyscraper rooftop
B2_WING = rect(6, 7, -15, -11)     # 6 m x 15 m east architectural wing
BUILDING_2 = B2_MAIN | B2_WING

FLOOR = BUILDING_1 | BUILDING_2

# 6 m wide (columns -1 and 0 -> world x = -3..+3) x 12 m long (rows -5..-8 -> world z = -12..-24) metallic bridge.
BRIDGE_ROWS = (-5, -6, -7, -8)
BRIDGE_CELLS = [(cx, cz) for cz in BRIDGE_ROWS for cx in (-1, 0)]
OPEN_PARAPET_EDGES = {
    (-1, -4, "N"), (0, -4, "N"),
    (-1, -9, "S"), (0, -9, "S"),
}

SPAWN_B1 = (-0.5, -1.0)    # world (0.0, -1.5): dead-centre on Building 1, facing the metallic bridge
CHECKPOINT_B2 = (-0.5, -11.5)  # world (0.0, -33.0): dead-centre on Building 2
# Ninjas on Building 1's north half, woken when the carriers step about 3 m ahead of the spawn.
NINJAS = (("Ninja1", -3, -4), ("Ninja2", 2, -4))


def box_bounds(x0, x1, z0, z1, inset=0.04):
    """World (cx, cz, sx, sz) of an inclusive cell rectangle, inset slightly under the parapet overhang."""
    wx0 = x0 * CELL + inset
    wx1 = (x1 + 1) * CELL - inset
    wz0 = z0 * CELL + inset
    wz1 = (z1 + 1) * CELL - inset
    return (wx0 + wx1) * 0.5, (wz0 + wz1) * 0.5, wx1 - wx0, wz1 - wz0


def extra_sub_resources():
    blocks = [
        """[sub_resource type="ShaderMaterial" id="ShaderMaterial_facade_b1"]
render_priority = 0
shader = ExtResource("facade_shader")
shader_parameter/roof_y = -1.0
shader_parameter/lit_ratio = 0.36
shader_parameter/emission_strength = 2.1
shader_parameter/seed_offset = 0.0""",
        """[sub_resource type="ShaderMaterial" id="ShaderMaterial_facade_b2"]
render_priority = 0
shader = ExtResource("facade_shader")
shader_parameter/wall_color = Color(0.19, 0.24, 0.33, 1)
shader_parameter/warm_window = Color(1, 0.80, 0.48, 1)
shader_parameter/cool_window = Color(0.48, 0.82, 1, 1)
shader_parameter/roof_y = -1.0
shader_parameter/lit_ratio = 0.40
shader_parameter/emission_strength = 2.25
shader_parameter/seed_offset = 23.0""",
        """[sub_resource type="ShaderMaterial" id="ShaderMaterial_facade_distant"]
render_priority = 0
shader = ExtResource("facade_shader")
shader_parameter/wall_color = Color(0.06, 0.08, 0.13, 1)
shader_parameter/roof_y = -24.0
shader_parameter/lit_ratio = 0.28
shader_parameter/emission_strength = 1.35
shader_parameter/fade_start_depth = 10.0
shader_parameter/fade_end_depth = 42.0
shader_parameter/seed_offset = 51.0""",
        """[sub_resource type="ShaderMaterial" id="ShaderMaterial_streets"]
render_priority = -3
shader = ExtResource("streets_shader")""",
        """[sub_resource type="ShaderMaterial" id="ShaderMaterial_mist_upper"]
render_priority = -1
shader = ExtResource("mist_shader")
shader_parameter/cloud_color = Color(0.12, 0.18, 0.32, 1)
shader_parameter/shade_color = Color(0.04, 0.07, 0.14, 1)
shader_parameter/sky_color = Color(0.02, 0.03, 0.07, 1)
shader_parameter/sky_opacity = 0.0
shader_parameter/coverage = 0.22
shader_parameter/softness = 0.16
shader_parameter/noise_scale = 0.026
shader_parameter/drift = Vector2(0.85, 0.22)""",
        """[sub_resource type="ShaderMaterial" id="ShaderMaterial_mist_lower"]
render_priority = -2
shader = ExtResource("mist_shader")
shader_parameter/cloud_color = Color(0.09, 0.13, 0.24, 1)
shader_parameter/shade_color = Color(0.03, 0.05, 0.10, 1)
shader_parameter/sky_color = Color(0.015, 0.024, 0.052, 1)
shader_parameter/sky_opacity = 0.22
shader_parameter/coverage = 0.34
shader_parameter/softness = 0.18
shader_parameter/noise_scale = 0.016
shader_parameter/drift = Vector2(0.45, 0.12)""",
        """[sub_resource type="ShaderMaterial" id="ShaderMaterial_helipad"]
render_priority = 0
shader = ExtResource("helipad_shader")""",
        """[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_steel_dark"]
albedo_color = Color(0.16, 0.19, 0.24, 1)
metallic = 0.80
roughness = 0.34""",
        """[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_steel_bright"]
albedo_color = Color(0.38, 0.43, 0.50, 1)
metallic = 0.84
roughness = 0.28""",
        """[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_amber_glow"]
shading_mode = 0
albedo_color = Color(2.0, 1.25, 0.35, 1)""",
        """[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_heli_led"]
shading_mode = 0
albedo_color = Color(0.25, 1.85, 0.72, 1)""",
        """[sub_resource type="PlaneMesh" id="PlaneMesh_city"]
size = Vector2(540, 540)""",
        """[sub_resource type="PlaneMesh" id="PlaneMesh_helipad"]
material = SubResource("ShaderMaterial_helipad")
size = Vector2(11.2, 11.2)""",
        """[sub_resource type="BoxMesh" id="BoxMesh_threshold"]
material = SubResource("StandardMaterial3D_steel_bright")
size = Vector3(6.16, 0.04, 0.56)""",
        """[sub_resource type="BoxMesh" id="BoxMesh_pylon"]
material = SubResource("StandardMaterial3D_steel_dark")
size = Vector3(0.36, 1.15, 0.36)""",
        """[sub_resource type="BoxMesh" id="BoxMesh_pylon_lamp"]
material = SubResource("StandardMaterial3D_amber_glow")
size = Vector3(0.18, 0.12, 0.18)""",
        """[sub_resource type="BoxMesh" id="BoxMesh_facade_strut"]
material = SubResource("StandardMaterial3D_steel_dark")
size = Vector3(0.20, 0.22, 2.75)""",
        """[sub_resource type="BoxMesh" id="BoxMesh_gusset"]
material = SubResource("StandardMaterial3D_steel_dark")
size = Vector3(0.42, 0.90, 0.14)""",
        """[sub_resource type="BoxMesh" id="BoxMesh_heli_light"]
material = SubResource("StandardMaterial3D_heli_led")
size = Vector3(0.22, 0.04, 0.22)""",
        """[sub_resource type="CylinderMesh" id="CylinderMesh_mast_lower"]
material = SubResource("StandardMaterial3D_steel_dark")
top_radius = 0.14
bottom_radius = 0.28
height = 3.6
radial_segments = 8""",
        """[sub_resource type="CylinderMesh" id="CylinderMesh_mast_upper"]
material = SubResource("StandardMaterial3D_steel_bright")
top_radius = 0.04
bottom_radius = 0.12
height = 3.2
radial_segments = 8""",
        """[sub_resource type="BoxMesh" id="BoxMesh_mast_arm"]
material = SubResource("StandardMaterial3D_steel_bright")
size = Vector3(1.65, 0.06, 0.06)""",
    ]
    return blocks


# Skyscraper hull blocks: (name, x0, x1, z0, z1, height, top_y, material_id).
HULL_BLOCKS = (
    ("B1MainHull", -5, 4, -4, 3, 56.0, -1.02, "ShaderMaterial_facade_b1"),
    ("B1WingHull", -7, -6, -2, 2, 56.0, -1.02, "ShaderMaterial_facade_b1"),
    ("B2MainHull", -6, 5, -17, -9, 56.0, -1.02, "ShaderMaterial_facade_b2"),
    ("B2WingHull", 6, 7, -15, -11, 56.0, -1.02, "ShaderMaterial_facade_b2"),
)

# Distant non-colliding lower skyscrapers far below the nocturnal mist layer (tops at y = -24 .. -33).
DISTANT_TOWERS = (
    ("DistantWest1", -44.0, -25.0, -10.0, 18.0, 44.0, 20.0),
    ("DistantWest2", -52.0, -29.0, -38.0, 22.0, 40.0, 22.0),
    ("DistantEast1", 44.0, -26.0, -8.0, 20.0, 43.0, 18.0),
    ("DistantEast2", 54.0, -24.0, -36.0, 22.0, 45.0, 24.0),
    ("DistantNorth1", -34.0, -27.0, -76.0, 22.0, 42.0, 20.0),
    ("DistantNorth2", 0.0, -31.0, -82.0, 26.0, 38.0, 20.0),
    ("DistantNorth3", 36.0, -26.0, -78.0, 22.0, 43.0, 20.0),
    ("DistantGapWest", -48.0, -32.0, -22.0, 18.0, 37.0, 16.0),
)


def add_hull_sub_resources(level):
    for name, x0, x1, z0, z1, height, _top_y, mat in HULL_BLOCKS:
        _cx, _cz, sx, sz = box_bounds(x0, x1, z0, z1)
        level.extra_sub_resources.append(
            f'[sub_resource type="BoxMesh" id="BoxMesh_{name}"]\n'
            f'material = SubResource("{mat}")\n'
            f"size = Vector3({fmt(sx)}, {fmt(height)}, {fmt(sz)})"
        )
    for name, _x, _top_y, _z, sx, sy, sz in DISTANT_TOWERS:
        level.extra_sub_resources.append(
            f'[sub_resource type="BoxMesh" id="BoxMesh_{name}"]\n'
            f'material = SubResource("ShaderMaterial_facade_distant")\n'
            f"size = Vector3({fmt(sx)}, {fmt(sy)}, {fmt(sz)})"
        )


def add_skyscraper_hulls(level):
    level.node("SkyscraperHulls", "Level", "Node3D")
    for name, x0, x1, z0, z1, height, top_y, _mat in HULL_BLOCKS:
        cx, cz, _sx, _sz = box_bounds(x0, x1, z0, z1)
        level.node(name, "Level/SkyscraperHulls", "MeshInstance3D", props={
            "transform": tf(cx, top_y - height * 0.5, cz),
            "cast_shadow": "0",
            "mesh": f'SubResource("BoxMesh_{name}")',
        })


def add_metallic_bridge_nodes(level):
    """Places 2x4 metallic bridge bays, rotating the east column 180° so girders & handrails flank both outer sides."""
    level.node("Bridges", "Level", "Node")
    for name, (cx, cz) in zip(level.platforms[1], BRIDGE_CELLS):
        wx, wz = world(cx, cz)
        basis = "1, 0, 0, 0, 1, 0, 0, 0, 1" if cx == -1 else FACE_SOUTH
        level.node(name, "Level/Bridges", instance="bridge", props={
            "transform": tf(wx, BRIDGE_Y, wz, basis),
            "start_at_bottom": "false",
        })


def add_bridge_framing(level):
    """Bolted steel thresholds, portal stanchions, diagonal facade struts, and subtle deck wash lights."""
    south_edge_z = -4 * CELL          # Building 1 north face (~ -11.996)
    north_edge_z = -8 * CELL          # Building 2 south face (~ -23.992)
    level.node("BridgeFraming", "Level", "Node3D")

    # Steel transition plates where the metallic bridge docks into each concrete rooftop.
    level.node("ThresholdSouth", "Level/BridgeFraming", "MeshInstance3D", props={
        "transform": tf(0, FLOOR_TOP + 0.015, south_edge_z + 0.24),
        "mesh": 'SubResource("BoxMesh_threshold")',
    })
    level.node("ThresholdNorth", "Level/BridgeFraming", "MeshInstance3D", props={
        "transform": tf(0, FLOOR_TOP + 0.015, north_edge_z - 0.24),
        "mesh": 'SubResource("BoxMesh_threshold")',
    })

    # Four bolted steel portal pylons with amber indicator lenses at the bridge mouths.
    pylons = (
        ("PylonSW", -3.16, south_edge_z + 0.22),
        ("PylonSE", 3.16, south_edge_z + 0.22),
        ("PylonNW", -3.16, north_edge_z - 0.22),
        ("PylonNE", 3.16, north_edge_z - 0.22),
    )
    for name, px, pz in pylons:
        level.node(name, "Level/BridgeFraming", "MeshInstance3D", props={
            "transform": tf(px, FLOOR_TOP + 0.575, pz),
            "mesh": 'SubResource("BoxMesh_pylon")',
        })
        level.node(f"{name}Lamp", "Level/BridgeFraming", "MeshInstance3D", props={
            "transform": tf(px, FLOOR_TOP + 1.21, pz),
            "cast_shadow": "0",
            "mesh": 'SubResource("BoxMesh_pylon_lamp")',
        })

    # Diagonal 42-degree structural steel struts bolting the bridge underside into Building 2's south facade
    # (directly visible to the camera!) and mirrored on Building 1's north facade.
    north_strut_basis = "1, 0, 0, 0, 0.7431448, 0.6691306, 0, -0.6691306, 0.7431448"
    south_strut_basis = "1, 0, 0, 0, 0.7431448, -0.6691306, 0, 0.6691306, 0.7431448"
    for idx, sx in enumerate((-2.75, -0.95, 0.95, 2.75), 1):
        level.node(f"NorthStrut{idx}", "Level/BridgeFraming", "MeshInstance3D", props={
            "transform": tf(sx, -2.18, north_edge_z + 0.98, north_strut_basis),
            "mesh": 'SubResource("BoxMesh_facade_strut")',
        })
        level.node(f"NorthGusset{idx}", "Level/BridgeFraming", "MeshInstance3D", props={
            "transform": tf(sx, -3.05, north_edge_z + 0.05),
            "mesh": 'SubResource("BoxMesh_gusset")',
        })
        level.node(f"SouthStrut{idx}", "Level/BridgeFraming", "MeshInstance3D", props={
            "transform": tf(sx, -2.18, south_edge_z - 0.98, south_strut_basis),
            "mesh": 'SubResource("BoxMesh_facade_strut")',
        })

    # Cool steel-sheen lights above the bridge so the diamond-plate and side trusses catch specular highlights.
    for idx, lz in enumerate((-15.0, -21.0), 1):
        level.node(f"BridgeWashLight{idx}", "Level/BridgeFraming", "OmniLight3D", props={
            "transform": tf(0, 2.2, lz),
            "light_color": "Color(0.66, 0.84, 1, 1)",
            "light_energy": "0.45",
            "omni_range": "8.5",
        })


def add_rooftop_props(level):
    """Colliding rooftop equipment under NavigationRegion3D (`bake_walkways`) so the navmesh carves around them."""
    level.node("RooftopProps", "Level/NavigationRegion3D", "Node3D", props={
        "metadata/bake_walkways": "true",
    })
    # Stairwell access bulkheads near the north edges of each roof (doors & warm sconces face south toward camera).
    level.node("PenthouseB1", "Level/NavigationRegion3D/RooftopProps", instance="penthouse", props={
        "transform": tf(-10.5, FLOOR_TOP, -8.8),
    })
    level.node("PenthouseB2", "Level/NavigationRegion3D/RooftopProps", instance="penthouse", props={
        "transform": tf(11.8, FLOOR_TOP, -47.2),
    })

    # Galvanized HVAC air-handling units with spinning fans along the outer wings & flanks.
    hvacs = (
        ("HvacB1West", -18.0, 1.5, "0, 0, -1, 0, 1, 0, 1, 0, 0"),
        ("HvacB1East1", 11.2, -4.5, "1, 0, 0, 0, 1, 0, 0, 0, 1"),
        ("HvacB1East2", 11.2, 3.2, "1, 0, 0, 0, 1, 0, 0, 0, 1"),
        ("HvacB2West1", -13.8, -45.5, "1, 0, 0, 0, 1, 0, 0, 0, 1"),
        ("HvacB2West2", -10.2, -46.2, "1, 0, 0, 0, 1, 0, 0, 0, 1"),
        ("HvacB2SouthEast", 13.5, -28.0, "1, 0, 0, 0, 1, 0, 0, 0, 1"),
    )
    for name, hx, hz, basis in hvacs:
        level.node(name, "Level/NavigationRegion3D/RooftopProps", instance="hvac", props={
            "transform": tf(hx, FLOOR_TOP, hz, basis),
        })

    # Glowing glass atrium skylights on Building 2.
    level.node("SkylightB2East", "Level/NavigationRegion3D/RooftopProps", instance="skylight", props={
        "transform": tf(20.6, FLOOR_TOP, -37.5),
    })
    level.node("SkylightB2West", "Level/NavigationRegion3D/RooftopProps", instance="skylight", props={
        "transform": tf(-13.2, FLOOR_TOP, -32.5),
    })


def add_rooftop_details(level):
    """Non-colliding rooftop markings, corner aviation beacons, bridge approach lamps, and comms mast."""
    level.node("RooftopDetails", "Level", "Node3D")

    # Helipad paint decal & 4 recessed green deck lights on Building 2's central concrete slab.
    hx, hz = 0.0, -37.5
    level.node("HelipadMarking", "Level/RooftopDetails", "MeshInstance3D", props={
        "transform": tf(hx, FLOOR_TOP + 0.015, hz),
        "cast_shadow": "0",
        "mesh": 'SubResource("PlaneMesh_helipad")',
    })
    for idx, (dx, dz) in enumerate(((-5.2, 0.0), (5.2, 0.0), (0.0, -5.2), (0.0, 5.2)), 1):
        level.node(f"HelipadLight{idx}", "Level/RooftopDetails", "MeshInstance3D", props={
            "transform": tf(hx + dx, FLOOR_TOP + 0.02, hz + dz),
            "cast_shadow": "0",
            "mesh": 'SubResource("BoxMesh_heli_light")',
        })

    # Architectural bollard lights flanking the metallic bridge approaches on both buildings.
    lamps = (
        ("BridgeLampB1W", -4.0, -10.8),
        ("BridgeLampB1E", 4.0, -10.8),
        ("BridgeLampB2W", -4.0, -25.2),
        ("BridgeLampB2E", 4.0, -25.2),
    )
    for name, lx, lz in lamps:
        level.node(name, "Level/RooftopDetails", instance="light_post", props={
            "transform": tf(lx, FLOOR_TOP, lz),
        })

    # Tall comms antenna mast on Building 2's far north parapet.
    mx, mz = -3.8, -50.2
    level.node("CommsMastLower", "Level/RooftopDetails", "MeshInstance3D", props={
        "transform": tf(mx, FLOOR_TOP + 1.8, mz),
        "mesh": 'SubResource("CylinderMesh_mast_lower")',
    })
    level.node("CommsMastUpper", "Level/RooftopDetails", "MeshInstance3D", props={
        "transform": tf(mx, FLOOR_TOP + 5.1, mz),
        "mesh": 'SubResource("CylinderMesh_mast_upper")',
    })
    level.node("CommsMastArm1", "Level/RooftopDetails", "MeshInstance3D", props={
        "transform": tf(mx, FLOOR_TOP + 4.1, mz),
        "mesh": 'SubResource("BoxMesh_mast_arm")',
    })
    level.node("CommsMastArm2", "Level/RooftopDetails", "MeshInstance3D", props={
        "transform": tf(mx, FLOOR_TOP + 5.4, mz, "0.7, 0, 0.7, 0, 1, 0, -0.7, 0, 0.7"),
        "mesh": 'SubResource("BoxMesh_mast_arm")',
    })
    level.node("CommsMastBeacon", "Level/RooftopDetails", instance="beacon", props={
        "transform": tf(mx, FLOOR_TOP + 6.65, mz),
    })

    # Pulsing red aviation warning beacons perched on the outer parapet corners of both skyscrapers.
    coping_top = -0.66
    corner_beacons = (
        (-14.82, -11.82), (14.82, -11.82), (-14.82, 11.82), (14.82, 11.82),
        (-20.82, -5.82), (-20.82, 8.82),
        (-17.82, -24.16), (17.82, -24.16), (-17.82, -50.80), (17.82, -50.80),
        (23.80, -30.16), (23.80, -44.80),
    )
    for idx, (bx, bz) in enumerate(corner_beacons, 1):
        level.node(f"CornerBeacon{idx}", "Level/RooftopDetails", instance="beacon", props={
            "transform": tf(bx, coping_top, bz),
        })


def add_night_cityscape(level):
    """Glowing street grid 68 m down, two drifting nocturnal mist sheets, and lower background towers."""
    level.node("NightCityscape", "Level", "Node3D")
    level.node("StreetGrid", "Level/NightCityscape", "MeshInstance3D", props={
        "transform": tf(0, -68.0, -24.0),
        "cast_shadow": "0",
        "mesh": 'SubResource("PlaneMesh_city")',
        "material_override": 'SubResource("ShaderMaterial_streets")',
    })
    level.node("NightMistLower", "Level/NightCityscape", "MeshInstance3D", props={
        "transform": tf(0, -42.0, -24.0),
        "cast_shadow": "0",
        "mesh": 'SubResource("PlaneMesh_city")',
        "material_override": 'SubResource("ShaderMaterial_mist_lower")',
    })
    level.node("NightMistUpper", "Level/NightCityscape", "MeshInstance3D", props={
        "transform": tf(0, -21.0, -24.0),
        "cast_shadow": "0",
        "mesh": 'SubResource("PlaneMesh_city")',
        "material_override": 'SubResource("ShaderMaterial_mist_upper")',
    })
    for idx, (name, tx, top_y, tz, sx, sy, sz) in enumerate(DISTANT_TOWERS, 1):
        level.node(name, "Level/NightCityscape", "MeshInstance3D", props={
            "transform": tf(tx, top_y - sy * 0.5, tz),
            "cast_shadow": "0",
            "mesh": f'SubResource("BoxMesh_{name}")',
        })
        level.node(f"{name}Beacon", "Level/NightCityscape", instance="beacon", props={
            "transform": tf(tx + sx * 0.44, top_y, tz + sz * 0.44),
        })


def main():
    level = Level(
        OUT,
        palette="rooftops",
        weapon="shuriken_launcher",
        deco_seed=1,
        floor_seed=1,
        follow_offset="Vector3(0, 8.4, 3.6)",
        music="cyber_noir",
    )
    level.use_rooftops()
    level.curve = (2.0, 1.0)
    level.boxes = {
        "fall": (280, 1, 280),
        "landing": (12, 3, 5),
        "ninja_wake": (30, 3, 3),
    }
    level.extra_sub_resources.extend(extra_sub_resources())
    add_hull_sub_resources(level)

    level.add_shell()
    level.nodes[0] += "\nskip_save = true"

    level.set_bridges({1: BRIDGE_CELLS})
    level.enemy_group("Ninjas")
    for name, cx, cz in NINJAS:
        level.ninja("Ninjas", name, cx, cz)
    cp_entries = [
        ("Checkpoint", SPAWN_B1[0], SPAWN_B1[1], {
            "events_completed": ["../../Level/Events/OpenBridge1"],
            "enemy_groups_reset": ["../../Enemies/Ninjas"],
            "areas_to_reactivate": ["../../Level/Areas/NorthBuildingLanding", "../../Level/Areas/NinjaWake"],
        }),
        ("Checkpoint2", CHECKPOINT_B2[0], CHECKPOINT_B2[1], {
            "events_completed": ["../../Level/Events/OpenBridge1"],
            "areas_already_activated": ["../../Level/Areas/NorthBuildingLanding"],
        }),
    ]
    level.checkpoints(cp_entries, setter_marker=(0, -0.5083), shooter_marker=(0, 2.1002))

    level.add_rooftop_terrain(FLOOR, OPEN_PARAPET_EDGES, fall_z=-20, fall_y=-17)
    add_rooftop_props(level)
    add_skyscraper_hulls(level)
    add_bridge_framing(level)
    add_rooftop_details(level)
    add_night_cityscape(level)

    level.bridge_event("OpenBridge1", 1, camera_focus=False)
    add_metallic_bridge_nodes(level)
    level.offensive_event("WakeNinjas", "Ninjas")
    level.add_triggers((("NorthBuildingLanding", -0.5, -9.8, "landing"), ("NinjaWake", -0.5, -2.0, "ninja_wake")))

    wx, wz = world(*SPAWN_B1)
    level.add_weapon("ShurikenLauncher", tf(wx, 0.593, wz))
    level.add_audio_and_hint()

    level.connect("all_players_inside", AREAS + "NorthBuildingLanding", "CheckpointManager/Checkpoint2", "_trigger_checkpoint")
    level.connect("all_players_inside", AREAS + "NinjaWake", EVENTS + "WakeNinjas")

    level.write(sys.argv[1:])


if __name__ == "__main__":
    main()
