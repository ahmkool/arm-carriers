#!/usr/bin/env python3
"""Mysterious Jungle co-op level: world_local_mysterious_jungle.tscn ("Mysterious Jungle", in the Dev tab).

Authored for the Siege Bow (and compatible with all ranged weapons via WeaponCatalog swap), winding in an S-meander
through sunken ancient temple terraces, jade river channels, flooded shrines, and a stepped ziggurat sanctuary:

(1) Overgrown Causeway (Pierce Warm-up):
    Carriers spawn on a mossy stone causeway facing three aligned columns of idle temple skeletons (9 total).
    Stretching apart draws the Siege Bow to full power, piercing an entire 3-skeleton column in one golden arrow and
    charging SHOCKWAVE. Clearing them sets Checkpoint2 and raises Bridge 1 north.

(2) Sunken Courtyard & Ruin Crossbow Wall:
    Crossing Bridge 1 into the sunken courtyard lowers Bridge 1, frames the courtyard and the mossy ruin ledge across a
    one-cell river moat to the north, spawns 4 skeleton crossbowmen on that unreachable ledge, and unleashes 6 feral
    jungle orc raiders inside the courtyard. Carriers use SHOCKWAVE to knock chasers back while drawing full-power shots
    across the moat. Clearing both groups unfocuses the camera, sets Checkpoint3 (facing east), and raises Bridge 2.

(3) Twin River Walkways & Idol Pillars:
    Stepping onto the west river pad lowers Bridge 2, frames the river crossing, and wakes 4 stationary jungle shamans
    on 2x2 idol islets flanking two parallel wooden walkways (separated by an open 1.1 m river gap down the middle).
    Each walkway starts behind its own raised sinking platform + SinglePlayerAreaTrigger, so when the first carrier
    steps onto one walkway its entry sinks behind them, forcing their partner onto the opposite rail. Outward firing
    bays let Siege Bow carriers draw wide for full-power shots, while stepping to the inner edges lets them renock
    across the central gap. Clearing the 4 idol shamans unfocuses the camera, sets Checkpoint4, and raises Bridge 3.

(4) Flooded Lattice Shrine & Cursed Skulls:
    Crossing Bridge 3 north onto a 13x16 stone lattice island pierced by four 2x2 jade water wells lowers Bridge 3 and
    spawns 5 jungle shamans along the lattice intersections plus 5 flying skulls swooping across the wells. Everything
    here is on-island (normal camera zoom). Clearing both groups sets Checkpoint5 (facing west) and raises Bridge 4.

(5) Crushing Idol Trap Chamber:
    Crossing Bridge 4 west into the temple trap corridor lowers Bridge 4, starts a closing north/south SpikeTrap
    (two wooden pressure plates 3.0 m apart along x), and launches a 40 s survival wave of jungle orcs from the west.
    Standing on both plates stops the walls AND brings Siege Bow carriers within nocking distance; stepping back to
    draw lets the walls creep slowly until they snap back onto the plates. Surviving and clearing the wave retracts the
    spike walls, sets Checkpoint6 on the western ziggurat approach, and raises Bridge 5 west.

(6) Grand Ziggurat Sanctuary Finale:
    Crossing Bridge 5 onto the ziggurat approach and stepping north across the raised ArenaGate into the 11x13 Grand
    Ziggurat Arena sinks ArenaGate behind the pair, frames the arena plus two flanking shrine ledges across 3 m moats,
    and unleashes 4 shrine crossbowmen + 2 shrine shamans on the ledges alongside an endless horde of temple guardians
    in the arena. Sniping all 6 flanking shrine defenders stops new horde spawns; finishing the remaining guardians
    unfocuses the camera, sets Checkpoint7, and raises Bridge 7 north into the illuminated Ziggurat Sanctuary.

Run from the project root; see docs/level-creation-for-agents.md for the bake / regenerate steps.
"""
import math
import random
import sys

from levelgen import (
    AREAS,
    BRIDGE_Y,
    CELL,
    CHECKPOINT_Y,
    EVENTS,
    FACE_SOUTH,
    GROUPS,
    WATER_Y,
    Level,
    fmt,
    fmt_decimal,
    node_paths,
    rect,
    tf,
    triple_bridge,
    world,
)

OUT = "src/world/levels/world_local_mysterious_jungle.tscn"
FLOOR_TOP = -1.0

FACE_NORTH = "1, 0, 0, 0, 1, 0, 0, 0, 1"
FACE_EAST = "0, 0, -1, 0, 1, 0, 1, 0, 0"
FACE_WEST = "0, 0, 1, 0, 1, 0, -1, 0, 0"

# Siege Bow carrier offsets in checkpoint local space (-z is forward).
SETTER_OFFSET = (0.0, -0.51)
SHOOTER_OFFSET = (0.0, 2.1)


def rounded(x0, x1, z0, z1):
    """Inclusive cell rectangle with its four outer corners cut."""
    return rect(x0, x1, z0, z1) - {(x0, z0), (x0, z1), (x1, z0), (x1, z1)}


def east_bridge(x1, x2, z_center):
    """Triple-wide east-west bridge (9 m wide along z, 6 m long along x)."""
    return [(x, z) for x in (x1, x2) for z in (z_center - 1, z_center, z_center + 1)]


# ---- Playable & Enemy Island Regions (grid cells). Forward is -z; East is +x. ----
CAUSEWAY = rounded(-4, 4, -7, 6)

COURTYARD = rounded(-5, 5, -23, -10)
ARCHER_LEDGE = rect(-4, 4, -26, -25)

RIVER_WEST = rounded(8, 12, -20, -14)
IDOL_NW = rect(14, 15, -22, -21)
IDOL_SW = rect(16, 17, -13, -12)
IDOL_NE = rect(18, 19, -22, -21)
IDOL_SE = rect(20, 21, -13, -12)
RIVER_EAST = rounded(23, 28, -20, -14)

WELL_SW = rect(23, 24, -29, -28)
WELL_SE = rect(28, 29, -29, -28)
WELL_NW = rect(23, 24, -34, -33)
WELL_NE = rect(28, 29, -34, -33)
LATTICE_SHRINE = rounded(20, 32, -38, -23) - WELL_SW - WELL_SE - WELL_NW - WELL_NE

TRAP_CHAMBER = rounded(6, 17, -36, -30)
ZIGGURAT_APPROACH = rounded(-3, 3, -36, -30)

ZIGGURAT_ARENA = rounded(-5, 5, -51, -39)
SHRINE_WEST = rect(-8, -7, -48, -42)
SHRINE_EAST = rect(7, 8, -48, -42)
SANCTUARY = rounded(-3, 3, -60, -54)

REGIONS = (
    CAUSEWAY,
    COURTYARD,
    ARCHER_LEDGE,
    RIVER_WEST,
    IDOL_NW,
    IDOL_SW,
    IDOL_NE,
    IDOL_SE,
    RIVER_EAST,
    LATTICE_SHRINE,
    TRAP_CHAMBER,
    ZIGGURAT_APPROACH,
    ZIGGURAT_ARENA,
    SHRINE_WEST,
    SHRINE_EAST,
    SANCTUARY,
)


def _assert_regions_separated(regions):
    for index, first in enumerate(regions):
        expanded = {(x + dx, z + dz) for x, z in first for dx in (-1, 0, 1) for dz in (-1, 0, 1)}
        others = set().union(*regions[index + 1 :]) if index + 1 < len(regions) else set()
        overlap = expanded & others
        assert not overlap, f"region {index} touches another region near {sorted(overlap)[:4]}"


_assert_regions_separated(REGIONS)
FLOOR = set().union(*REGIONS)

# Bridges 1..5 & 7 start submerged; Bridge 6 (ArenaGate) starts raised and sinks when the finale begins.
BRIDGES = {
    1: triple_bridge(-8, -9),
    2: east_bridge(6, 7, -17),
    3: [(x, z) for z in (-21, -22) for x in (25, 26, 27)],
    4: east_bridge(18, 19, -33),
    5: east_bridge(4, 5, -33),
    6: triple_bridge(-37, -38),
    7: triple_bridge(-52, -53),
}

MOUTHS = (
    {(x, z) for x in (-1, 0, 1) for z in (-7, -10, -36, -39, -51, -54)}
    | {(x, z) for x in (5, 8) for z in (-18, -17, -16)}
    | {(x, z) for x in (12, 23) for z in (-18, -17, -16)}
    | {(x, z) for x in (25, 26, 27) for z in (-20, -23)}
    | {(x, z) for x in (17, 20) for z in (-34, -33, -32)}
    | {(x, z) for x in (3, 6) for z in (-34, -33, -32)}
)
assert MOUTHS <= FLOOR, sorted(MOUTHS - FLOOR)

# Solid interior cover props on floor plates (baked out of the navmesh).
INTERIOR_PROPS = {
    (-2, 1): ("TempleObelisk", 0),
    (2, 1): ("TempleObelisk", 0),
    (-3, -4): ("TemplePillar", 0),
    (3, -4): ("TemplePillar", 0),
    (-3, -15): ("TemplePillar", 0),
    (3, -15): ("TemplePillar", 0),
    (-3, -20): ("TempleObelisk", 0),
    (3, -20): ("TempleObelisk", 0),
    (26, -26): ("TempleObelisk", 0),
    (26, -36): ("TempleObelisk", 0),
    (-3, -42): ("TemplePillar", 0),
    (3, -42): ("TemplePillar", 0),
    (-3, -48): ("TemplePillar", 0),
    (3, -48): ("TemplePillar", 0),
}

HINT = (
    "[color=#7ef2b5]Sunken Temple[/color]\n\n"
    "Stretch apart to draw power and pierce lines of foes.\n"
    "Step back together to nock the next arrow.\n"
    "Hit an enemy to charge [color=#ffd966]SHOCKWAVE[/color]."
)

level = Level(
    OUT,
    palette="jungle",
    weapon="siege_bow",
    deco_seed=31,
    floor_seed=19,
    hint=HINT,
    music="secret_corridor",
)
level.use_jungle()
level.curve = (2.3, 1.2)
level.boxes = {
    "fall": (360, 1, 360),
    "courtyard": (24, 3, 13),
    "river_entry": (9, 3, 15),
    "rail_single": (4.5, 3, 2.0),
    "lattice": (20, 3, 12),
    "trap": (15, 3, 15),
    "approach": (7, 3, 13),
    "arena": (22, 3, 12),
    "sanctuary_reveal": (9, 3, 5),
    "end": (7.5, 3, 5.5),
}
level.extra_ext += [
    ("PackedScene", None, "res://src/enemy/enemy_orc.tscn", "orc"),
    ("PackedScene", None, "res://src/enemy/enemy_skeleton_crossbow.tscn", "crossbow"),
    ("PackedScene", "uid://cje8utfev8m5t", "res://src/enemy/enemy_flying_skull.tscn", "skull"),
    ("Script", None, "res://src/events/groups_defeated_gate.gd", "groups_gate"),
    ("Script", None, "res://src/events/stop_survival_event.gd", "stop_survival"),
    ("Script", None, "res://src/world/elements/single_player_area_trigger.gd", "single_player"),
    ("Script", None, "res://src/world/elements/trap/spike_trap.gd", "spike_trap"),
    ("Script", None, "res://src/events/spike_trap_event.gd", "spike_trap_event"),
    ("Shader", None, "res://src/world/elements/jungle/jungle_ruin_stone.gdshader", "jungle_stone"),
]
level.add_shell()
# Golden-amber aim guide & enchanted arrow shafts contrast crisply against mossy olive stone and jade water.
level.nodes[0] += "\naim_guide_color = Color(1, 0.86, 0.3, 0.95)\narrow_shaft_color = Color(0.95, 0.72, 0.22, 1)"
# Allow wider zoom headroom when framing across moats with a stretched 24 m-range Siege Bow.
level.nodes[1] += "\nmax_zoom_out = 18.5"


# ---- Helper builders for enemies, checkpoints, walkways, and scenery. ----
def add_orc(group, name, cx, cz, basis=FACE_SOUTH):
    wx, wz = world(cx, cz)
    level.node(
        name,
        f"Enemies/{group}/InstancedEnemies",
        instance="orc",
        props={"transform": tf(wx, 0, wz, basis), "is_offensive": "false"},
    )


def add_crossbowman(group, name, cx, cz, basis, cast_max=22.0, cooldown=3.2):
    wx, wz = world(cx, cz)
    path = f"Enemies/{group}/InstancedEnemies/{name}"
    level.node(
        name,
        f"Enemies/{group}/InstancedEnemies",
        instance="crossbow",
        props={"transform": tf(wx, 0, wz, basis), "is_offensive": "false", "holds_position": "true"},
    )
    level.node(
        "MageBehavior",
        path,
        props={
            "mobility": "1",
            "cast_max_distance": fmt_decimal(cast_max),
            "cast_cooldown": fmt_decimal(cooldown),
            "cast_cooldown_jitter": "0.9",
        },
    )


def add_skull(group, name, cx, cz):
    wx, wz = world(cx, cz)
    level.node(
        name,
        f"Enemies/{group}/InstancedEnemies",
        instance="skull",
        props={"transform": tf(wx, 0, wz, FACE_SOUTH), "is_offensive": "false"},
    )


# ---- Section 1: Overgrown Causeway (3 aligned columns of 3 temple skeletons). ----
level.enemy_group("CausewayGuard")
CAUSEWAY_GUARD_CELLS = [(cx, cz) for cx in (-2, 0, 2) for cz in (-2, -4, -6)]
for index, (cx, cz) in enumerate(CAUSEWAY_GUARD_CELLS, 1):
    assert (cx, cz) in CAUSEWAY
    level.melee("CausewayGuard", f"Skeleton{index}", cx, cz)

# ---- Section 2: Sunken Courtyard (4 ruin crossbowmen across the moat + 6 feral orc raiders). ----
level.enemy_group("CourtyardArchers", spawn_on_trigger=True)
for index, cx in enumerate((-3, -1, 1, 3), 1):
    assert (cx, -25) in ARCHER_LEDGE
    add_crossbowman("CourtyardArchers", f"Crossbowman{index}", cx, -25, FACE_SOUTH, cast_max=23.0, cooldown=3.2)

level.enemy_group("CourtyardRaiders", spawn_on_trigger=True)
COURTYARD_RAIDER_CELLS = ((-4, -21), (-2, -22), (-1, -20), (1, -20), (2, -22), (4, -21))
for index, (cx, cz) in enumerate(COURTYARD_RAIDER_CELLS, 1):
    assert (cx, cz) in COURTYARD
    add_orc("CourtyardRaiders", f"OrcRaider{index}", cx, cz)

# ---- Section 3: Twin River Walkways (4 stationary jungle shamans on river idol islets). ----
level.enemy_group("RiverIdolMages", spawn_on_trigger=True)
IDOL_MAGE_CELLS = ((15, -21), (16, -13), (19, -21), (20, -13))
for index, (cx, cz) in enumerate(IDOL_MAGE_CELLS, 1):
    assert (cx, cz) in FLOOR
    level.mage("RiverIdolMages", f"IdolShaman{index}", cx, cz, cast_max=20.0, cooldown=3.2, holds_position=True, cooldown_jitter=0.8)

# ---- Section 4: Flooded Lattice Shrine (5 shamans + 5 flying skulls). ----
level.enemy_group("LatticeMages", spawn_on_trigger=True)
LATTICE_MAGE_CELLS = ((21, -28), (26, -31), (31, -28), (21, -35), (31, -35))
for index, (cx, cz) in enumerate(LATTICE_MAGE_CELLS, 1):
    assert (cx, cz) in LATTICE_SHRINE
    level.mage("LatticeMages", f"LatticeShaman{index}", cx, cz, cast_max=16.0, cooldown=3.0, holds_position=True, cooldown_jitter=0.7)

level.enemy_group("LatticeSkulls", spawn_on_trigger=True)
LATTICE_SKULL_CELLS = ((21, -33), (26, -35), (31, -33), (22, -26), (30, -26))
for index, (cx, cz) in enumerate(LATTICE_SKULL_CELLS, 1):
    assert (cx, cz) in LATTICE_SHRINE
    add_skull("LatticeSkulls", f"CursedSkull{index}", cx, cz)

# ---- Section 5: Crushing Idol Trap Chamber (40 s orc survival wave from the west). ----
TRAP_SPAWNS = ((7, -33), (8, -34), (8, -32), (7, -33))
for cell in TRAP_SPAWNS:
    assert cell in TRAP_CHAMBER
level.survival_scene = "orc"
level.survival_group(TRAP_SPAWNS[:3], duration=40.0)

# ---- Section 6: Grand Ziggurat Sanctuary Finale (6 shrine defenders + endless guardian horde). ----
level.enemy_group("ZigguratShrineArchers", spawn_on_trigger=True)
add_crossbowman("ZigguratShrineArchers", "WestCrossbow1", -7, -47, FACE_EAST, cast_max=24.0, cooldown=3.4)
add_crossbowman("ZigguratShrineArchers", "WestCrossbow2", -7, -43, FACE_EAST, cast_max=24.0, cooldown=3.4)
add_crossbowman("ZigguratShrineArchers", "EastCrossbow1", 7, -47, FACE_WEST, cast_max=24.0, cooldown=3.4)
add_crossbowman("ZigguratShrineArchers", "EastCrossbow2", 7, -43, FACE_WEST, cast_max=24.0, cooldown=3.4)
level.mage("ZigguratShrineArchers", "WestHighShaman", -7, -45, cast_max=22.0, cooldown=3.5, holds_position=True, cooldown_jitter=0.8)
level.mage("ZigguratShrineArchers", "EastHighShaman", 7, -45, cast_max=22.0, cooldown=3.5, holds_position=True, cooldown_jitter=0.8)

ZIGGURAT_HORDE_SPAWNS = ((-4, -49), (4, -49), (-4, -41), (4, -41), (0, -50))
level.node(
    "ZigguratHorde",
    "Enemies",
    "Node3D",
    props={
        "script": 'ExtResource("survival_group")',
        "enemy_scene": 'ExtResource("orc")',
        "spawn_interval_curve": 'SubResource("Curve_survival")',
        "fight_duration": "60.0",
        "endless": "true",
        "max_alive": "7",
        "show_timer_ui": "false",
    },
)
level.node("Enemies", "Enemies/ZigguratHorde", "Node3D")
level.node("SpawnPoints", "Enemies/ZigguratHorde", "Node3D")
for index, (cx, cz) in enumerate(ZIGGURAT_HORDE_SPAWNS, 1):
    assert (cx, cz) in ZIGGURAT_ARENA
    wx, wz = world(cx, cz)
    level.node(f"Node3D{index}", "Enemies/ZigguratHorde/SpawnPoints", "Node3D", props={"transform": tf(wx, 0, wz)})


# ---- Checkpoints (oriented along travel direction so both Siege Bow and swapped weapons spawn facing ahead). ----
def build_checkpoint_dict(events=(), reset=(), defeated=(), react=(), done=()):
    table = {}
    specs = (
        ("events_completed", "../../Level/Events/", events),
        ("enemy_groups_reset", "../../Enemies/", reset),
        ("enemy_groups_defeated", "../../Enemies/", defeated),
        ("areas_to_reactivate", "../../Level/Areas/", react),
        ("areas_already_activated", "../../Level/Areas/", done),
    )
    for key, prefix, names in specs:
        if names:
            table[key] = node_paths([prefix + item for item in names])
    return table


CHECKPOINT_SPECS = (
    (
        "Checkpoint",
        0,
        3,
        FACE_NORTH,
        build_checkpoint_dict(reset=("CausewayGuard",)),
    ),
    (
        "Checkpoint2",
        0,
        -5,
        FACE_NORTH,
        build_checkpoint_dict(
            events=("OpenBridge1",),
            reset=("CourtyardArchers", "CourtyardRaiders"),
            defeated=("CausewayGuard",),
            react=("CourtyardTrigger",),
        ),
    ),
    (
        "Checkpoint3",
        3,
        -17,
        FACE_EAST,
        build_checkpoint_dict(
            events=("OpenBridge2", "OpenSplitRails"),
            reset=("RiverIdolMages",),
            defeated=("CausewayGuard", "CourtyardArchers", "CourtyardRaiders"),
            react=("RiverWestTrigger", "NorthRailTrigger", "SouthRailTrigger"),
            done=("CourtyardTrigger",),
        ),
    ),
    (
        "Checkpoint4",
        26,
        -17,
        FACE_NORTH,
        build_checkpoint_dict(
            events=("OpenBridge3",),
            reset=("LatticeMages", "LatticeSkulls"),
            defeated=("CausewayGuard", "CourtyardArchers", "CourtyardRaiders", "RiverIdolMages"),
            react=("LatticeTrigger",),
            done=("CourtyardTrigger", "RiverWestTrigger", "NorthRailTrigger", "SouthRailTrigger"),
        ),
    ),
    (
        "Checkpoint5",
        22,
        -33,
        FACE_WEST,
        build_checkpoint_dict(
            events=("OpenBridge4",),
            reset=("SurvivalEnemyGroup",),
            defeated=("CausewayGuard", "CourtyardArchers", "CourtyardRaiders", "RiverIdolMages", "LatticeMages", "LatticeSkulls"),
            react=("TrapTrigger",),
            done=("CourtyardTrigger", "RiverWestTrigger", "NorthRailTrigger", "SouthRailTrigger", "LatticeTrigger"),
        ),
    ),
    (
        "Checkpoint6",
        -1,
        -33,
        FACE_NORTH,
        build_checkpoint_dict(
            events=("OpenArenaGate",),
            reset=("ZigguratShrineArchers", "ZigguratHorde"),
            defeated=(
                "CausewayGuard",
                "CourtyardArchers",
                "CourtyardRaiders",
                "RiverIdolMages",
                "LatticeMages",
                "LatticeSkulls",
                "SurvivalEnemyGroup",
            ),
            react=("ZigguratArenaTrigger",),
            done=(
                "CourtyardTrigger",
                "RiverWestTrigger",
                "NorthRailTrigger",
                "SouthRailTrigger",
                "LatticeTrigger",
                "TrapTrigger",
                "ApproachTrigger",
            ),
        ),
    ),
    (
        "Checkpoint7",
        0,
        -48,
        FACE_NORTH,
        build_checkpoint_dict(
            events=("OpenBridge7",),
            defeated=(
                "CausewayGuard",
                "CourtyardArchers",
                "CourtyardRaiders",
                "RiverIdolMages",
                "LatticeMages",
                "LatticeSkulls",
                "SurvivalEnemyGroup",
                "ZigguratShrineArchers",
                "ZigguratHorde",
            ),
            react=("SanctuaryRevealTrigger",),
            done=(
                "CourtyardTrigger",
                "RiverWestTrigger",
                "NorthRailTrigger",
                "SouthRailTrigger",
                "LatticeTrigger",
                "TrapTrigger",
                "ApproachTrigger",
                "ZigguratArenaTrigger",
            ),
        ),
    ),
)

level.node(
    "CheckpointManager",
    ".",
    "Node",
    paths=["current_checkpoint"],
    props={"script": 'ExtResource("cp_manager")', "current_checkpoint": 'NodePath("Checkpoint")'},
)
for cp_name, cx, cz, basis, arrays in CHECKPOINT_SPECS:
    assert (cx, cz) in FLOOR, (cp_name, cx, cz)
    wx, wz = world(cx, cz)
    props = {"transform": tf(wx, CHECKPOINT_Y, wz, basis), "script": 'ExtResource("checkpoint")', **arrays}
    level.node(cp_name, "CheckpointManager", "Node3D", paths=list(arrays.keys()) or None, props=props)
    level.node(
        "PositionDirectionSetter",
        f"CheckpointManager/{cp_name}",
        "Marker3D",
        props={"transform": tf(SETTER_OFFSET[0], 0, SETTER_OFFSET[1])},
    )
    level.node(
        "PositionShooter",
        f"CheckpointManager/{cp_name}",
        "Marker3D",
        props={"transform": tf(SHOOTER_OFFSET[0], 0, SHOOTER_OFFSET[1])},
    )


# ---- Terrain, Twin River Walkways, Spike Trap, Surrounding Jungle Scenery, and Monuments. ----
level.add_jungle_terrain(
    FLOOR,
    MOUTHS,
    INTERIOR_PROPS,
    decoration_count=46,
    fall_z=-80,
    water_z=-80,
    fall_x=28,
    water_x=28,
)


def add_walkway_materials():
    level.extra_sub_resources.append(
        '[sub_resource type="ShaderMaterial" id="Material_jungle_deck"]\n'
        'render_priority = 0\nshader = ExtResource("jungle_stone")\n'
        "shader_parameter/timber_top = true\nshader_parameter/water_y = -4.6\nshader_parameter/moss_height = 1.9"
    )
    level.extra_sub_resources.append(
        '[sub_resource type="StandardMaterial3D" id="Material_jungle_beam"]\n'
        "albedo_color = Color(0.22, 0.14, 0.08, 1)\nroughness = 0.86"
    )
    level.extra_sub_resources.append(
        '[sub_resource type="CylinderMesh" id="CylinderMesh_river_pile"]\n'
        'material = SubResource("Material_jungle_beam")\n'
        "top_radius = 0.22\nbottom_radius = 0.26\nheight = 6.5\nradial_segments = 8\nrings = 1"
    )


def add_timber_span(parent, name, x_center, z_center, size_x, size_z):
    level.extra_sub_resources.append(
        f'[sub_resource type="BoxMesh" id="BoxMesh_{name}"]\n'
        f'material = SubResource("Material_jungle_deck")\nsize = Vector3({size_x:.3f}, 0.55, {size_z:.3f})'
    )
    level.extra_sub_resources.append(
        f'[sub_resource type="BoxShape3D" id="BoxShape3D_{name}"]\n'
        f"size = Vector3({size_x:.3f}, 0.55, {size_z:.3f})"
    )
    path = f"{parent}/{name}"
    level.node(
        name,
        parent,
        "StaticBody3D",
        props={
            "transform": tf(x_center, FLOOR_TOP - 0.275, z_center),
            "collision_layer": "4",
            "collision_mask": "0",
            "metadata/footstep_surface": '&"wood"',
        },
    )
    level.node("Mesh", path, "MeshInstance3D", props={"mesh": f'SubResource("BoxMesh_{name}")'})
    level.node("CollisionShape3D", path, "CollisionShape3D", props={"shape": f'SubResource("BoxShape3D_{name}")'})


def add_twin_river_walkways():
    """Two parallel 2.2 m wide wooden jungle walkways from cx=14..22, separated by a 1.1 m river gap down the middle,
    with outward firing bays so Siege Bow carriers can draw wide for full-power shots and step inward to renock."""
    add_walkway_materials()
    level.node("RiverWalkways", "Level", "Node3D")
    x0, _ = world(14, -17)
    x1, center_z = world(22, -17)
    span_x = (x1 - x0) + CELL + 0.5  # reaches 0.25 m onto SplitRails (cx=13) and RIVER_EAST (cx=23)
    mid_x = (x0 + x1) * 0.5
    rail_offset_z = 1.65  # inner edges at +-0.55 m (1.1 m river gap); centres 3.3 m apart
    add_timber_span("Level/RiverWalkways", "NorthWalkway", mid_x, center_z - rail_offset_z, span_x, 2.2)
    add_timber_span("Level/RiverWalkways", "SouthWalkway", mid_x, center_z + rail_offset_z, span_x, 2.2)
    # Outward firing bays so Siege Bow carriers can stretch up to 7.8 m laterally or diagonally without crossing rails.
    for index, cx in enumerate((16, 19, 21), 1):
        bx, _ = world(cx, -17)
        add_timber_span("Level/RiverWalkways", f"NorthBay{index}", bx, center_z - 3.65, 3.6, 1.9)
        add_timber_span("Level/RiverWalkways", f"SouthBay{index}", bx, center_z + 3.65, 3.6, 1.9)
    for index, cx in enumerate((14, 16, 18, 20, 22), 1):
        px, _ = world(cx, -17)
        level.node(
            f"PileN{index}",
            "Level/RiverWalkways",
            "MeshInstance3D",
            props={"transform": tf(px, FLOOR_TOP - 3.4, center_z - rail_offset_z), "mesh": 'SubResource("CylinderMesh_river_pile")'},
        )
        level.node(
            f"PileS{index}",
            "Level/RiverWalkways",
            "MeshInstance3D",
            props={"transform": tf(px, FLOOR_TOP - 3.4, center_z + rail_offset_z), "mesh": 'SubResource("CylinderMesh_river_pile")'},
        )


add_twin_river_walkways()

# ---- Section 5 SpikeTrap (centred on cz = -33; bridges enter east & exit west between the spike walls). ----
trap_x, trap_z = world(13, -33)
chamber_x0 = world(6, -33)[0] - CELL * 0.5
chamber_x1 = world(17, -33)[0] + CELL * 0.5
level.node(
    "SpikeTrap",
    "Level",
    "Node3D",
    props={
        "transform": tf(trap_x, FLOOR_TOP, trap_z),
        "script": 'ExtResource("spike_trap")',
        "start_half_gap": "7.6",
        "wall_width": "38.0",
        "wall_offset_x": fmt((chamber_x0 + chamber_x1) * 0.5 - trap_x),
        "close_speed": "0.28",
        "slowed_speed": "0.09",
        "plate_spacing": "3.0",
    },
)

# ---- Bridges (standard bridges + the two start-up SplitBridge platforms at cx = 13 + start-up ArenaGate). ----
level.set_bridges(BRIDGES)
level.node("Bridges", "Level", "Node")
for number, cells in BRIDGES.items():
    start_up = number == 6
    for platform_name, (cx, cz) in zip(level.platforms[number], cells):
        wx, wz = world(cx, cz)
        props = {"transform": tf(wx, BRIDGE_Y, wz)}
        if start_up:
            props["start_at_bottom"] = "false"
        level.node(platform_name, "Level/Bridges", instance="bridge", props=props)

split_x, split_center_z = world(13, -17)
level.node(
    "SplitBridgeNorth",
    "Level/Bridges",
    instance="bridge",
    props={"transform": tf(split_x, BRIDGE_Y, split_center_z - 1.7), "start_at_bottom": "false"},
)
level.node(
    "SplitBridgeSouth",
    "Level/Bridges",
    instance="bridge",
    props={"transform": tf(split_x, BRIDGE_Y, split_center_z + 1.7), "start_at_bottom": "false"},
)

# ---- Glowing Totem Braziers, Ancient Ruin Arches, Grand Temple Ziggurat, and Lush Perimeter Jungle Isles. ----
BRAZIER_CELLS = (
    (-3, 5),
    (3, 5),
    (-2, -7),
    (2, -7),
    (-4, -11),
    (4, -11),
    (-4, -23),
    (4, -23),
    (-4, -26),
    (4, -26),
    (9, -19),
    (9, -15),
    (14, -22),
    (17, -12),
    (18, -22),
    (21, -12),
    (27, -19),
    (27, -15),
    (24, -23),
    (28, -23),
    (21, -37),
    (31, -37),
    (16, -35),
    (16, -31),
    (7, -35),
    (7, -31),
    (-2, -35),
    (2, -35),
    (-4, -40),
    (4, -40),
    (-4, -50),
    (4, -50),
    (-8, -48),
    (-8, -42),
    (8, -48),
    (8, -42),
    (-2, -55),
    (2, -55),
)
for cell in BRAZIER_CELLS:
    assert cell in FLOOR, cell
level.add_braziers(BRAZIER_CELLS)

# Monuments & arches strictly on northern/flank edges so nothing ever obscures the south-looking camera.
level.extra_sub_resources.append(
    '[sub_resource type="StandardMaterial3D" id="Material_sanctuary_ring"]\n'
    "shading_mode = 0\nalbedo_color = Color(0.28, 1.45, 0.88, 1)"
)
level.extra_sub_resources.append(
    '[sub_resource type="TorusMesh" id="TorusMesh_sanctuary_ring"]\n'
    'material = SubResource("Material_sanctuary_ring")\n'
    "inner_radius = 2.2\nouter_radius = 2.55\nrings = 32\nring_segments = 8"
)
level.node("Monuments", "Level", "Node3D")
zig_x, zig_z = world(0, -60.0)
level.node("GrandZiggurat", "Level/Monuments", instance="ziggurat", props={"transform": tf(zig_x, FLOOR_TOP, zig_z)})
altar_x, altar_z = world(0, -55.5)
level.node(
    "SanctuaryAltarRing",
    "Level/Monuments",
    "MeshInstance3D",
    props={"transform": tf(altar_x, FLOOR_TOP + 0.04, altar_z), "cast_shadow": "0", "mesh": 'SubResource("TorusMesh_sanctuary_ring")'},
)
for index, (cx, cz, basis) in enumerate(
    (
        (0, -26, FACE_NORTH),
        (26, -38, FACE_NORTH),
        (-3, -51, FACE_NORTH),
        (3, -51, FACE_NORTH),
    ),
    1,
):
    ax, az = world(cx, cz)
    level.node(f"RuinArch{index}", "Level/Monuments", instance="ruin_arch", props={"transform": tf(ax, FLOOR_TOP, az - 0.8, basis)})


def _scatter_flora(shape, seed):
    rng = random.Random(seed)
    choices = ("IsleTreeA", "IsleTreeB", "IsleTreeC", "IsleTreeD", "IsleTreeE", "IsleBushA", "IsleBushB", "IsleBushC", "IsleRockA", "IsleRockB")
    rots = (0, 10, 16, 22)
    interior = [c for c in sorted(shape) if all((c[0] + dx, c[1] + dz) in shape for dx in (-1, 0, 1) for dz in (-1, 0, 1))]
    picked = rng.sample(interior, max(1, int(len(interior) * 0.72)))
    return {cell: (rng.choice(choices), rng.choice(rots)) for cell in picked}


# Perimeter jungle islands (kept clear of any walkable island's south camera frustum and separated from FLOOR).
JUNGLE_ISLES = (
    ("WestCanopySouth", (0, 0, 0), rounded(-13, -7, -6, 6), _scatter_flora(rounded(-13, -7, -6, 6), 101)),
    ("WestCanopyMid", (0, 0, 0), rounded(-14, -8, -25, -10), _scatter_flora(rounded(-14, -8, -25, -10), 102)),
    ("EastCausewayIsle", (0, 0, 0), rounded(7, 13, -4, 6), _scatter_flora(rounded(7, 13, -4, 6), 103)),
    ("EastRiverIsle", (0, 0, 0), rounded(31, 37, -21, -13), _scatter_flora(rounded(31, 37, -21, -13), 104)),
    ("EastLatticeIsle", (0, 0, 0), rounded(35, 41, -38, -24), _scatter_flora(rounded(35, 41, -38, -24), 105)),
    ("NorthLatticeIsle", (0, 0, 0), rounded(22, 33, -46, -41), _scatter_flora(rounded(22, 33, -46, -41), 106)),
    ("NorthTrapIsle", (0, 0, 0), rounded(12, 19, -45, -39), _scatter_flora(rounded(12, 19, -45, -39), 107)),
    ("WestZigguratIsle", (0, 0, 0), rounded(-16, -11, -56, -34), _scatter_flora(rounded(-16, -11, -56, -34), 108)),
    ("EastZigguratIsle", (0, 0, 0), rounded(11, 17, -60, -50), _scatter_flora(rounded(11, 17, -60, -50), 109)),
)
for isle_name, _, isle_shape, _ in JUNGLE_ISLES:
    expanded_isle = {(x + dx, z + dz) for x, z in isle_shape for dx in (-1, 0, 1) for dz in (-1, 0, 1)}
    assert not (expanded_isle & FLOOR), f"{isle_name} touches playable FLOOR"
level.add_jungle_isles(JUNGLE_ISLES)


def add_lily_pads():
    """Low floating jungle lily pads on the jade river channels and lattice water wells (no collision, y near water)."""
    level.extra_sub_resources.append(
        '[sub_resource type="StandardMaterial3D" id="Material_lily_pad"]\n'
        "albedo_color = Color(0.16, 0.44, 0.2, 1)\nroughness = 0.72"
    )
    level.extra_sub_resources.append(
        '[sub_resource type="CylinderMesh" id="CylinderMesh_lily_pad"]\n'
        'material = SubResource("Material_lily_pad")\n'
        "top_radius = 0.85\nbottom_radius = 0.85\nheight = 0.06\nradial_segments = 10\nrings = 1"
    )
    level.node("LilyPads", "Level", "Node3D")
    rng = random.Random(77)
    well_cells = sorted(WELL_SW | WELL_SE | WELL_NW | WELL_NE)
    river_spots = [
        (-5, -8),
        (4, -9),
        (-3, -24),
        (3, -24),
        (6, -20),
        (7, -14),
        (15, -19),
        (18, -15),
        (21, -19),
        (23, -22),
        (29, -22),
        (18, -36),
        (19, -30),
        (4, -36),
        (-6, -45),
        (6, -45),
        (-3, -53),
        (3, -53),
    ]
    for index, (cx, cz) in enumerate(well_cells + river_spots, 1):
        wx, wz = world(cx, cz)
        scale = rng.uniform(0.7, 1.25)
        yaw = rng.uniform(0.0, math.tau)
        c, s = math.cos(yaw) * scale, math.sin(yaw) * scale
        basis = f"{c:.3f}, 0, {s:.3f}, 0, 1, 0, {-s:.3f}, 0, {c:.3f}"
        level.node(
            f"LilyPad{index}",
            "Level/LilyPads",
            "MeshInstance3D",
            props={
                "transform": tf(wx + rng.uniform(-0.7, 0.7), WATER_Y + 0.05, wz + rng.uniform(-0.7, 0.7), basis),
                "cast_shadow": "0",
                "mesh": 'SubResource("CylinderMesh_lily_pad")',
            },
        )


add_lily_pads()


# ---- Events, Gates, Camera Focus, and Area Triggers. ----
for number in (1, 2, 3, 4, 5, 7):
    level.bridge_event(f"OpenBridge{number}", number)

level.bridge_event("OpenArenaGate", 6, camera_focus=False)
level.node(
    "OpenSplitRails",
    "Level/Events",
    "Node",
    paths=["platforms"],
    props={
        "script": 'ExtResource("toggle_bridge")',
        "platforms": node_paths(["../../Bridges/SplitBridgeNorth", "../../Bridges/SplitBridgeSouth"]),
        "use_camera_focus": "false",
    },
)
level.node(
    "CloseSplitNorth",
    "Level/Events",
    "Node",
    paths=["platforms"],
    props={
        "script": 'ExtResource("toggle_bridge")',
        "platforms": node_paths(["../../Bridges/SplitBridgeNorth"]),
        "use_camera_focus": "false",
        "event_type": "1",
    },
)
level.node(
    "CloseSplitSouth",
    "Level/Events",
    "Node",
    paths=["platforms"],
    props={
        "script": 'ExtResource("toggle_bridge")',
        "platforms": node_paths(["../../Bridges/SplitBridgeSouth"]),
        "use_camera_focus": "false",
        "event_type": "1",
    },
)


def add_offensive(name, group, next_event=None):
    props = {"script": 'ExtResource("change_behavior")', "enemy_group": f'NodePath("../../../Enemies/{group}")'}
    paths = ["enemy_group"]
    if next_event:
        props["next_event"] = f'NodePath("../{next_event}")'
        paths.append("next_event")
    level.node(name, "Level/Events", "Node", paths=paths, props=props)


# Section 2 events.
level.bridge_event("CloseBridge1", 1, close=True)
add_offensive("WakeCourtyardArchers", "CourtyardArchers", "WakeCourtyardRaiders")
add_offensive("WakeCourtyardRaiders", "CourtyardRaiders")
level.node(
    "CourtyardCleared",
    "Level/Events",
    "Node",
    paths=["next_event", "groups", "checkpoint", "also_trigger"],
    props={
        "script": 'ExtResource("groups_gate")',
        "next_event": 'NodePath("../OpenBridge2")',
        "groups": node_paths(["../../../Enemies/CourtyardArchers", "../../../Enemies/CourtyardRaiders"]),
        "checkpoint": 'NodePath("../../../CheckpointManager/Checkpoint3")',
        "also_trigger": node_paths(["../UnfocusCamera"]),
    },
)

# Section 3 events.
level.bridge_event("CloseBridge2", 2, close=True)
add_offensive("WakeRiverIdolMages", "RiverIdolMages")
level.node(
    "RiverCleared",
    "Level/Events",
    "Node",
    paths=["next_event", "groups", "checkpoint", "also_trigger"],
    props={
        "script": 'ExtResource("groups_gate")',
        "next_event": 'NodePath("../OpenBridge3")',
        "groups": node_paths(["../../../Enemies/RiverIdolMages"]),
        "checkpoint": 'NodePath("../../../CheckpointManager/Checkpoint4")',
        "also_trigger": node_paths(["../UnfocusCamera"]),
    },
)

# Section 4 events.
level.bridge_event("CloseBridge3", 3, close=True)
add_offensive("WakeLatticeMages", "LatticeMages", "WakeLatticeSkulls")
add_offensive("WakeLatticeSkulls", "LatticeSkulls")
level.node(
    "LatticeCleared",
    "Level/Events",
    "Node",
    paths=["next_event", "groups", "checkpoint"],
    props={
        "script": 'ExtResource("groups_gate")',
        "next_event": 'NodePath("../OpenBridge4")',
        "groups": node_paths(["../../../Enemies/LatticeMages", "../../../Enemies/LatticeSkulls"]),
        "checkpoint": 'NodePath("../../../CheckpointManager/Checkpoint5")',
    },
)

# Section 5 events.
level.bridge_event("CloseBridge4", 4, close=True)
level.node(
    "StartTrap",
    "Level/Events",
    "Node",
    paths=["trap", "next_event"],
    props={"script": 'ExtResource("spike_trap_event")', "trap": 'NodePath("../../SpikeTrap")', "next_event": 'NodePath("../WakeTrapHorde")'},
)
add_offensive("WakeTrapHorde", "SurvivalEnemyGroup")
level.node(
    "RetractTrap",
    "Level/Events",
    "Node",
    paths=["trap"],
    props={"script": 'ExtResource("spike_trap_event")', "trap": 'NodePath("../../SpikeTrap")', "action": "1"},
)
level.node(
    "TrapCleared",
    "Level/Events",
    "Node",
    paths=["next_event", "groups", "also_trigger"],
    props={
        "script": 'ExtResource("groups_gate")',
        "next_event": 'NodePath("../OpenBridge5")',
        "groups": node_paths(["../../../Enemies/SurvivalEnemyGroup"]),
        "also_trigger": node_paths(["../RetractTrap"]),
    },
)

# Section 6 approach & finale events.
level.bridge_event("CloseBridge5", 5, close=True)
level.node(
    "SetCheckpoint6",
    "Level/Events",
    "Node",
    paths=["checkpoint", "also_trigger"],
    props={
        "script": 'ExtResource("groups_gate")',
        "checkpoint": 'NodePath("../../../CheckpointManager/Checkpoint6")',
        "also_trigger": node_paths(["../CloseBridge5"]),
    },
)
level.bridge_event("CloseArenaGate", 6, close=True)
add_offensive("WakeZigguratArchers", "ZigguratShrineArchers", "WakeZigguratHorde")
add_offensive("WakeZigguratHorde", "ZigguratHorde")
level.node(
    "StopZigguratHorde",
    "Level/Events",
    "Node",
    paths=["survival_group"],
    props={"script": 'ExtResource("stop_survival")', "survival_group": 'NodePath("../../../Enemies/ZigguratHorde")'},
)
level.node(
    "ZigguratCleared",
    "Level/Events",
    "Node",
    paths=["next_event", "groups", "checkpoint", "also_trigger"],
    props={
        "script": 'ExtResource("groups_gate")',
        "next_event": 'NodePath("../OpenBridge7")',
        "groups": node_paths(["../../../Enemies/ZigguratShrineArchers", "../../../Enemies/ZigguratHorde"]),
        "checkpoint": 'NodePath("../../../CheckpointManager/Checkpoint7")',
        "also_trigger": node_paths(["../UnfocusCamera"]),
    },
)
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})

# Framed camera sections ONLY where enemies sit across unwalkable water moats/islets, plus the Grand Ziggurat reveal.
level.add_focus(
    {
        "Courtyard": (-5, 5, -18, -28),
        "River": (11, 22, -13, -21),
        "Ziggurat": (-8, 8, -40, -50),
        "Sanctuary": (-5, 5, -58, -66),
    }
)

# Triggers (sized deep enough for an 8 m stretched Siege Bow pair, never overlapping checkpoints or bridges).
level.add_triggers(
    (
        ("CourtyardTrigger", 0, -13, "courtyard"),
        ("RiverWestTrigger", 10, -17, "river_entry"),
        ("LatticeTrigger", 26, -26, "lattice"),
        ("TrapTrigger", 13, -33, "trap"),
        ("ApproachTrigger", 1, -33, "approach"),
        ("ZigguratArenaTrigger", 0, -42, "arena"),
        ("SanctuaryRevealTrigger", 0, -53, "sanctuary_reveal"),
    )
)

# Single-player triggers just onto each river walkway so the first carrier's entry platform sinks behind them.
rail_trigger_x, _ = world(15, -17)
for rail_name, z_shift in (("NorthRailTrigger", -1.65), ("SouthRailTrigger", 1.65)):
    level.node(
        rail_name,
        "Level/Areas",
        "Area3D",
        props={"transform": tf(rail_trigger_x, 0, split_center_z + z_shift), "script": 'ExtResource("single_player")'},
    )
    level.node(
        "CollisionShape3D",
        f"Level/Areas/{rail_name}",
        "CollisionShape3D",
        props={"shape": 'SubResource("BoxShape3D_rail_single")'},
    )

level.add_end_area(0, -55.5)

spawn_x, spawn_z = world(0, 3)
level.add_weapon("SiegeBow", tf(spawn_x, 0.593, spawn_z))
level.add_audio_and_hint()

# ---- Signal wiring (wake events fire immediately on trigger entry in parallel with bridge closes). ----
level.connect("enemies_defeated", GROUPS + "CausewayGuard", "CheckpointManager/Checkpoint2", "_trigger_checkpoint")
level.connect("enemies_defeated", GROUPS + "CausewayGuard", EVENTS + "OpenBridge1")

level.connect("all_players_inside", AREAS + "CourtyardTrigger", EVENTS + "CloseBridge1")
level.connect("all_players_inside", AREAS + "CourtyardTrigger", EVENTS + "WakeCourtyardArchers")
for corner in ("SW", "SE", "NW", "NE"):
    level.connect("all_players_inside", AREAS + "CourtyardTrigger", f"{EVENTS}FocusCourtyard{corner}")
level.connect("enemies_defeated", GROUPS + "CourtyardArchers", EVENTS + "CourtyardCleared")
level.connect("enemies_defeated", GROUPS + "CourtyardRaiders", EVENTS + "CourtyardCleared")

level.connect("all_players_inside", AREAS + "RiverWestTrigger", EVENTS + "CloseBridge2")
level.connect("all_players_inside", AREAS + "RiverWestTrigger", EVENTS + "WakeRiverIdolMages")
for corner in ("SW", "SE", "NW", "NE"):
    level.connect("all_players_inside", AREAS + "RiverWestTrigger", f"{EVENTS}FocusRiver{corner}")
level.connect("player_inside", AREAS + "NorthRailTrigger", EVENTS + "CloseSplitNorth")
level.connect("player_inside", AREAS + "SouthRailTrigger", EVENTS + "CloseSplitSouth")
level.connect("enemies_defeated", GROUPS + "RiverIdolMages", EVENTS + "RiverCleared")

level.connect("all_players_inside", AREAS + "LatticeTrigger", EVENTS + "CloseBridge3")
level.connect("all_players_inside", AREAS + "LatticeTrigger", EVENTS + "WakeLatticeMages")
level.connect("enemies_defeated", GROUPS + "LatticeMages", EVENTS + "LatticeCleared")
level.connect("enemies_defeated", GROUPS + "LatticeSkulls", EVENTS + "LatticeCleared")

level.connect("all_players_inside", AREAS + "TrapTrigger", EVENTS + "CloseBridge4")
level.connect("all_players_inside", AREAS + "TrapTrigger", EVENTS + "StartTrap")
level.connect("enemies_defeated", GROUPS + "SurvivalEnemyGroup", EVENTS + "TrapCleared")

level.connect("all_players_inside", AREAS + "ApproachTrigger", EVENTS + "SetCheckpoint6")
level.connect("all_players_inside", AREAS + "ZigguratArenaTrigger", EVENTS + "CloseArenaGate")
level.connect("all_players_inside", AREAS + "ZigguratArenaTrigger", EVENTS + "WakeZigguratArchers")
for corner in ("SW", "SE", "NW", "NE"):
    level.connect("all_players_inside", AREAS + "ZigguratArenaTrigger", f"{EVENTS}FocusZiggurat{corner}")
level.connect("enemies_defeated", GROUPS + "ZigguratShrineArchers", EVENTS + "StopZigguratHorde")
level.connect("enemies_defeated", GROUPS + "ZigguratShrineArchers", EVENTS + "ZigguratCleared")
level.connect("enemies_defeated", GROUPS + "ZigguratHorde", EVENTS + "ZigguratCleared")

for corner in ("SW", "SE", "NW", "NE"):
    level.connect("all_players_inside", AREAS + "SanctuaryRevealTrigger", f"{EVENTS}FocusSanctuary{corner}")
level.connect("all_players_inside", "Level/EndLevelArea", EVENTS + "LevelSucceeded")

level.write(sys.argv[1:])
