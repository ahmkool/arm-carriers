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
- Building 3: a third rooftop past a second, identical bridge north of Building 2.

The fight, in rounds, staged like the medieval levels: clearing a building saves a checkpoint on it and raises the
bridge to the next; both carriers stepping onto the next building closes the bridge behind them, and that spawns the
building's enemies, so they can't be shot from across the gap first. A death respawns on the building just cleared.
1. Building 1: three ninjas that never wake (they stand still and never throw): two on its north half and the
   billboard ninja hiding on the east tower, which only the launcher's kunai reach. Killing all three saves
   Checkpoint2 by the bridge and raises bridge 1.
2. Building 2: landing closes bridge 1 and spawns four circling ninjas. Killing them saves Checkpoint3 by bridge 2
   and raises it.
3. Building 3: landing closes bridge 2 and spawns the Shuriken Master, a 30 HP ninja with two giant shurikens
   circling him (enemy_ninja_boss.tscn). Beating him saves Checkpoint4 on Building 3.

Run from the project root; see docs/level-creation-for-agents.md for the bake / regenerate steps. Bake with
BAKE_PLATFORMS_UNDER=Level/Bridges BAKE_PLATFORM_ITEM=0 so the navmesh runs over the lowered bridges.
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

# A small tower east of Building 1, across a 6 m gap: the billboard ninja's. The carriers can't get onto it.
EAST_TOWER = rect(7, 8, 1, 3)      # 6 m x 9 m, world x = 21..27, z = 3..12

B3_MAIN = rect(-5, 4, -27, -22)    # 30 m x 18 m north rooftop, past the second bridge (world z = -63..-81)
BUILDING_3 = B3_MAIN

FLOOR = BUILDING_1 | BUILDING_2 | EAST_TOWER | BUILDING_3

# 6 m wide (columns -1 and 0 -> world x = -3..+3) x 12 m long metallic bridges:
# bridge 1 (rows -5..-8, world z = -12..-24) from Building 1 to 2, bridge 2 (rows -18..-21, z = -51..-63) from 2 to 3.
BRIDGE_ROWS = (-5, -6, -7, -8)
BRIDGE_CELLS = [(cx, cz) for cz in BRIDGE_ROWS for cx in (-1, 0)]
BRIDGE2_ROWS = (-18, -19, -20, -21)
BRIDGE2_CELLS = [(cx, cz) for cz in BRIDGE2_ROWS for cx in (-1, 0)]
OPEN_PARAPET_EDGES = {
    (-1, -4, "N"), (0, -4, "N"),
    (-1, -9, "S"), (0, -9, "S"),
    (-1, -17, "N"), (0, -17, "N"),
    (-1, -22, "S"), (0, -22, "S"),
}

SPAWN_B1 = (-0.5, -1.0)    # world (0.0, -1.5): dead-centre on Building 1, facing the metallic bridge
# Each round's checkpoint is on the building it cleared, in front of the bridge it raises.
CHECKPOINT_B1_CLEARED = (-0.5, -2.5)   # world (0.0, -6.0): Building 1, facing bridge 1
CHECKPOINT_B2_CLEARED = (-0.5, -15.0)  # world (0.0, -43.5): Building 2, facing bridge 2
CHECKPOINT_B3_CLEARED = (-0.5, -24.5)  # world (0.0, -72.0): Building 3
# The Shuriken Master stands at the back of Building 3, facing the bridge he is waiting for the carriers to cross.
BOSS = (0.0, -76.0)
# Building 1's guards never wake: two ninjas on its north half and the billboard ninja on the east tower.
# Killing all three raises the first bridge.
B1_NINJAS = (("Ninja1", -3, -4), ("Ninja2", 2, -4))
# Building 2's four ninjas spawn when both carriers land on it, which closes bridge 1 behind them.
B2_NINJAS = (("Ninja3", -3, -13), ("Ninja4", 2, -13), ("Ninja5", -1, -16), ("Ninja6", 1, -16))
# The billboard stands across x, 0.8 m in from the tower's west edge; the ninja hides 1.8 m behind it, facing west.
# The star hangs 10.8 m ahead of the front carrier, so it reaches the billboard from 2 to 4 m in from Building 1's
# east edge (x = 15), in the clear lane north of the east HVAC units.
COVER_PANEL = (21.8, 7.5)
PEEKER = (23.6, 7.5)
FACE_WEST = "0, 0, -1, 0, 1, 0, 1, 0, 0"


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
        """[sub_resource type="PlaneMesh" id="PlaneMesh_city"]
size = Vector2(540, 540)""",
        """[sub_resource type="PlaneMesh" id="PlaneMesh_helipad"]
material = SubResource("ShaderMaterial_helipad")
size = Vector2(11.2, 11.2)""",
    ]
    return blocks


# Skyscraper hull blocks: (name, x0, x1, z0, z1, height, top_y, material_id).
HULL_BLOCKS = (
    ("B1MainHull", -5, 4, -4, 3, 56.0, -1.02, "ShaderMaterial_facade_b1"),
    ("B1WingHull", -7, -6, -2, 2, 56.0, -1.02, "ShaderMaterial_facade_b1"),
    ("B2MainHull", -6, 5, -17, -9, 56.0, -1.02, "ShaderMaterial_facade_b2"),
    ("B2WingHull", 6, 7, -15, -11, 56.0, -1.02, "ShaderMaterial_facade_b2"),
    ("EastTowerHull", 7, 8, 1, 3, 56.0, -1.02, "ShaderMaterial_facade_b1"),
    ("B3MainHull", -5, 4, -27, -22, 56.0, -1.02, "ShaderMaterial_facade_b1"),
)

# Distant non-colliding lower skyscrapers far below the nocturnal mist layer (tops at y = -24 .. -33).
DISTANT_TOWERS = (
    ("DistantWest1", -44.0, -25.0, -10.0, 18.0, 44.0, 20.0),
    ("DistantWest2", -52.0, -29.0, -38.0, 22.0, 40.0, 22.0),
    ("DistantEast1", 44.0, -26.0, -8.0, 20.0, 43.0, 18.0),
    ("DistantEast2", 54.0, -24.0, -36.0, 22.0, 45.0, 24.0),
    ("DistantNorth1", -34.0, -27.0, -100.0, 22.0, 42.0, 20.0),
    ("DistantNorth2", 0.0, -31.0, -106.0, 26.0, 38.0, 20.0),
    ("DistantNorth3", 36.0, -26.0, -102.0, 22.0, 43.0, 20.0),
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
    """Places 2x4 metallic bridge bays per bridge, rotating the east column 180° so girders & handrails flank both
    outer sides. Both start lowered: bridge 1 rises when Building 1's guards fall, bridge 2 when Building 2's do."""
    level.node("Bridges", "Level", "Node")
    for number, cells in ((1, BRIDGE_CELLS), (2, BRIDGE2_CELLS)):
        for name, (cx, cz) in zip(level.platforms[number], cells):
            wx, wz = world(cx, cz)
            basis = "1, 0, 0, 0, 1, 0, 0, 0, 1" if cx == -1 else FACE_SOUTH
            level.node(name, "Level/Bridges", instance="bridge", props={
                "transform": tf(wx, BRIDGE_Y, wz, basis),
            })


def add_bridge_framing(level):
    """Bolted steel thresholds, portal stanchions, diagonal facade struts (one model per bridge,
    rooftop_bridge_framing.tscn, built by tools/blender/build_rooftop_props.py round the bridge's middle), and subtle
    deck wash lights. Both bridges are 12 m long, so the one model fits both."""
    level.node("BridgeFraming", "Level", "Node3D")
    # (name, south face of the building it leaves, north face... of the building it reaches): z of each end.
    spans = (("Framing", -4 * CELL, -8 * CELL), ("Framing2", -17 * CELL, -21 * CELL))
    light = 0
    for name, south_edge_z, north_edge_z in spans:
        level.node(name, "Level/BridgeFraming", instance="bridge_framing", props={
            "transform": tf(0, 0, (south_edge_z + north_edge_z) / 2),
        })
        # Cool steel-sheen lights above the bridge so the diamond-plate and side trusses catch specular highlights.
        for lz in (south_edge_z - 3.0, north_edge_z + 3.0):
            light += 1
            level.node(f"BridgeWashLight{light}", "Level/BridgeFraming", "OmniLight3D", props={
                "transform": tf(0, 2.2, round(lz, 3)),
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
    level.node("PenthouseB3", "Level/NavigationRegion3D/RooftopProps", instance="penthouse", props={
        "transform": tf(-9.5, FLOOR_TOP, -78.2),
    })

    # Galvanized HVAC air-handling units with spinning fans along the outer wings & flanks.
    hvacs = (
        ("HvacB1West", -18.0, 1.5, "0, 0, -1, 0, 1, 0, 1, 0, 0"),
        ("HvacB1East1", 11.2, -4.5, "1, 0, 0, 0, 1, 0, 0, 0, 1"),
        ("HvacB1East2", 11.2, 3.2, "1, 0, 0, 0, 1, 0, 0, 0, 1"),
        ("HvacB2West1", -13.8, -45.5, "1, 0, 0, 0, 1, 0, 0, 0, 1"),
        ("HvacB2West2", -10.2, -46.2, "1, 0, 0, 0, 1, 0, 0, 0, 1"),
        ("HvacB2SouthEast", 13.5, -28.0, "1, 0, 0, 0, 1, 0, 0, 0, 1"),
        ("HvacB3West", -11.2, -73.5, "1, 0, 0, 0, 1, 0, 0, 0, 1"),
        ("HvacB3East", 11.2, -76.5, "1, 0, 0, 0, 1, 0, 0, 0, 1"),
    )
    for name, hx, hz, basis in hvacs:
        level.node(name, "Level/NavigationRegion3D/RooftopProps", instance="hvac", props={
            "transform": tf(hx, FLOOR_TOP, hz, basis),
        })

    # Glowing glass atrium skylights on Building 2.
    # The billboard ninja's cover on the east tower: a ShotCover, so the carriers' star and kunai stop on it.
    level.node("CoverPanel", "Level/NavigationRegion3D/RooftopProps", instance="cover_panel", props={
        "transform": tf(COVER_PANEL[0], FLOOR_TOP, COVER_PANEL[1]),
    })
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
    # The four lights are one model, rooftop_helipad_lights.tscn, round the helipad's middle.
    level.node("HelipadLights", "Level/RooftopDetails", instance="helipad_lights", props={
        "transform": tf(hx, FLOOR_TOP, hz),
    })

    # Architectural bollard lights flanking the metallic bridge approaches on both buildings.
    lamps = (
        ("BridgeLampB1W", -4.0, -10.8),
        ("BridgeLampB1E", 4.0, -10.8),
        ("BridgeLampB2W", -4.0, -25.2),
        ("BridgeLampB2E", 4.0, -25.2),
        ("BridgeLampB2NW", -4.0, -49.8),
        ("BridgeLampB2NE", 4.0, -49.8),
        ("BridgeLampB3W", -4.0, -64.2),
        ("BridgeLampB3E", 4.0, -64.2),
    )
    for name, lx, lz in lamps:
        level.node(name, "Level/RooftopDetails", instance="light_post", props={
            "transform": tf(lx, FLOOR_TOP, lz),
        })

    # Tall comms antenna mast on Building 2's far north parapet.
    # West of the second bridge's lamps.
    mx, mz = -9.5, -50.2
    level.node("CommsMast", "Level/RooftopDetails", instance="comms_mast", props={
        "transform": tf(mx, FLOOR_TOP, mz),
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
        (26.82, 3.18), (26.82, 11.82),
        (-14.82, -63.16), (14.82, -63.16), (-14.82, -80.80), (14.82, -80.80),
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
        "peeker_approach": (12, 3, 12),
    }
    level.extra_sub_resources.extend(extra_sub_resources())
    add_hull_sub_resources(level)

    level.add_shell()
    level.nodes[0] += "\nskip_save = true"

    level.set_bridges({1: BRIDGE_CELLS, 2: BRIDGE2_CELLS})
    level.enemy_group("Building1")
    for name, cx, cz in B1_NINJAS:
        level.ninja("Building1", name, cx, cz)
    level.ninja_peeker("Building1", "BillboardNinja", PEEKER[0], PEEKER[1], FACE_WEST)
    level.enemy_group("Building2", spawn_on_trigger=True)
    for name, cx, cz in B2_NINJAS:
        level.ninja("Building2", name, cx, cz)
    level.extra_ext += [
        ("PackedScene", None, "res://src/enemy/enemy_ninja_boss.tscn", "ninja_boss"),
    ]
    level.enemy_group("Building3", spawn_on_trigger=True)
    level.node("ShurikenMaster", "Enemies/Building3/InstancedEnemies", instance="ninja_boss", props={
        "transform": tf(BOSS[0], 0, BOSS[1], FACE_SOUTH), "is_offensive": "false"})
    cp_entries = [
        ("Checkpoint", SPAWN_B1[0], SPAWN_B1[1], {
            "enemy_groups_reset": ["../../Enemies/Building1", "../../Enemies/Building2", "../../Enemies/Building3"],
            "areas_to_reactivate": ["../../Level/Areas/NorthBuildingLanding", "../../Level/Areas/PeekerApproach",
                                    "../../Level/Areas/Building3Landing"],
        }),
        ("Checkpoint2", CHECKPOINT_B1_CLEARED[0], CHECKPOINT_B1_CLEARED[1], {
            "events_completed": ["../../Level/Events/OpenBridge1"],
            "enemy_groups_reset": ["../../Enemies/Building2"],
            "enemy_groups_defeated": ["../../Enemies/Building1"],
            "areas_to_reactivate": ["../../Level/Areas/NorthBuildingLanding"],
            "areas_already_activated": ["../../Level/Areas/PeekerApproach"],
        }),
        ("Checkpoint3", CHECKPOINT_B2_CLEARED[0], CHECKPOINT_B2_CLEARED[1], {
            "events_completed": ["../../Level/Events/OpenBridge2"],
            "enemy_groups_reset": ["../../Enemies/Building3"],
            "enemy_groups_defeated": ["../../Enemies/Building1", "../../Enemies/Building2"],
            "areas_to_reactivate": ["../../Level/Areas/Building3Landing"],
            "areas_already_activated": ["../../Level/Areas/NorthBuildingLanding", "../../Level/Areas/PeekerApproach"],
        }),
        ("Checkpoint4", CHECKPOINT_B3_CLEARED[0], CHECKPOINT_B3_CLEARED[1], {
            "enemy_groups_defeated": ["../../Enemies/Building1", "../../Enemies/Building2", "../../Enemies/Building3"],
            "areas_already_activated": ["../../Level/Areas/NorthBuildingLanding", "../../Level/Areas/PeekerApproach",
                                        "../../Level/Areas/Building3Landing"],
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
    level.bridge_event("CloseBridge1", 1, close=True, next_event="WakeBuilding2")
    level.bridge_event("OpenBridge2", 2, camera_focus=False)
    level.bridge_event("CloseBridge2", 2, close=True, next_event="WakeBuilding3")
    add_metallic_bridge_nodes(level)
    level.offensive_event("WakeBuilding2", "Building2")
    level.offensive_event("WakeBuilding3", "Building3")
    # Framing for the east tower, which can't be walked to: on while the carriers are on Building 1's east side.
    level.add_focus({"Tower": (7, 8, 3, 1)})
    # Over Building 1's east third (world x = 3..15, z = 0..12), where the carriers line up a throw at the billboard.
    # NorthBuildingLanding starts Building 2's round once both carriers are a couple of metres off bridge 1.
    level.add_triggers((("NorthBuildingLanding", -0.5, -9.8, "landing"), ("PeekerApproach", 2.5, 1.5, "peeker_approach"),
                        ("Building3Landing", -0.5, -22.8, "landing")))

    wx, wz = world(*SPAWN_B1)
    level.add_weapon("ShurikenLauncher", tf(wx, 0.593, wz))
    level.add_audio_and_hint()

    level.connect("all_players_inside", AREAS + "NorthBuildingLanding", EVENTS + "CloseBridge1")
    for corner in ("SW", "SE", "NW", "NE"):
        level.connect("all_players_inside", AREAS + "PeekerApproach", EVENTS + f"FocusTower{corner}")
    level.connect("enemies_defeated", "Enemies/Building1", "CheckpointManager/Checkpoint2", "_trigger_checkpoint")
    for target in (EVENTS + "OpenBridge1", EVENTS + "UnfocusCamera"):
        level.connect("enemies_defeated", "Enemies/Building1", target)
    level.connect("enemies_defeated", "Enemies/Building2", "CheckpointManager/Checkpoint3", "_trigger_checkpoint")
    level.connect("enemies_defeated", "Enemies/Building2", EVENTS + "OpenBridge2")
    level.connect("all_players_inside", AREAS + "Building3Landing", EVENTS + "CloseBridge2")
    level.connect("enemies_defeated", "Enemies/Building3", "CheckpointManager/Checkpoint4", "_trigger_checkpoint")

    level.write(sys.argv[1:])


if __name__ == "__main__":
    main()
