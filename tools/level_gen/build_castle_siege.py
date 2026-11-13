#!/usr/bin/env python3
"""Prototype of a castle siege: world_local_castle_siege.tscn ("Castle Siege", in the Dev tab). Played with the catapult.

The carriers attack a castle from the desert canyon outside it, heading north along its west wall, in three sections.

(1) The wall: a sandstone ledge with the castle wall on its right (east), across a one-cell chasm. Four skeleton
    crossbowmen (src/enemy/enemy_skeleton_crossbow.tscn) stand on its wall walk (top at y = 3, 4 m above the ledge) and
    shoot down at the carriers; the catapult's steep lobs land on the wall walk, so the pair has to step into their
    range to hit them. On the left, terraced hills rise in three tiers; a sinkhole in the ledge is another way to fall.
    Walking north wakes the crossbowmen and frames the ledge and the wall. Killing them sets Checkpoint2 and raises
    bridge 1 north.
(2) The catapult: a second ledge. On its west edge a hill one tier tall hides a pocket where a skeleton works a
    catapult (src/enemy/enemy_skeleton_catapult.tscn), lobbing bombs over the hill at the carriers. Stepping onto the
    ledge lowers bridge 1, wakes him and frames the pocket and the ledge. Killing him sets Checkpoint3 and raises
    bridge 2 north.
(3) The islands: six islands over the void, two columns of three, joined by fixed wooden bridges. Stepping onto the
    first lowers bridge 2 and brings in six skeletons that chase the carriers across the bridges, a catapult skeleton
    on each of the other five islands, and a crossbowman on each of two stone towers standing out of the void. Killing
    all of them sets Checkpoint4 and raises bridge 3 to a pad.
(4) The S-bridge: from the pad, a one-cell-wide wooden deck snakes north in an S, over the void, while four catapult
    skeletons on islands of their own throw at the carriers. Four outcrops stick out of the bridge's side, each toward
    one island, with just enough room for the pair to stand in line along it and reach that island. Stepping onto
    the pad lowers bridge 3 and wakes the catapults; killing all four sets Checkpoint5 and raises bridge 4, at the S's
    end.
(5) The castle front: a field with the castle's wall on its right (east), as in the first sections, across a one-cell
    chasm, the gate in its middle. Six crossbowmen stand on the wall walk, and three catapult skeletons on wooden
    balconies behind the wall throw over it; the carriers reach them by lobbing over the wall. Skeletons keep appearing in the field (an endless SurvivalEnemyGroup) until the wall's
    crossbowmen and catapults are all dead, which stops them, sets Checkpoint6 and raises the stone bridge over the
    chasm, through the gate, to a pad inside holding the end area. The castle's inside is the next section.

The wall and the towers are generated here: StaticBody3Ds on layer 4, the level's collision layer, so bombs land on
them and crossbowmen stand on them. The island bridges are StaticBody3D decks baked into the navmesh, so skeletons
chase across them.

Run from the project root; see docs/level-creation-for-agents.md.
"""
import sys

import math
import random

from levelgen import (AREAS, CELL, EVENTS, GROUPS, TRIGGER as T, Level, node_paths, rect, tf, world)

OUT = "src/world/levels/world_local_castle_siege.tscn"


def rounded(x0, x1, z0, z1):
    """A rectangle with its corners cut."""
    return rect(x0, x1, z0, z1) - {(x0, z0), (x0, z1), (x1, z0), (x1, z1)}


# ---- Layout, in grid cells. Forward is -z; the castle is east (+x). ----
# The chasm between the ledges and the wall is one cell (3 m) where the crossbowmen stand: the catapult only lands on a
# wall walk from close in, with the front carrier near the edge. It widens at the south end, where nobody needs to shoot.
SINKHOLE = rect(-3, -2, -3, -1)
LEDGE_A = rounded(-5, 2, -5, 9) - SINKHOLE - {(2, 9), (2, 8), (2, 7), (1, 9)}
# A hill one tier (two GridMap layers, 4 m) tall on the second ledge's west edge, and behind it a pocket carved into
# the terraces at the ledge's height, walled in on every side, where a skeleton works a catapult. The carriers can't
# walk to him: they lob bombs over the hill, as he does at them. The hill runs a row past the pocket at each end, so
# no gap opens between its corners and the terraces.
MOUND = rect(-5, -4, -15, -9)
POCKET = rect(-10, -6, -14, -10)
LEDGE_B = rounded(-5, 2, -17, -7) - MOUND
# Six islands, two columns of three (5 x 5 cells, corners cut), two cells apart.
ISLAND_COLUMNS = {"E": -1, "W": -8}
ISLAND_ROWS = (-21, -28, -35)
ISLANDS = {f"{col}{row + 1}": (cx, cz) for row, cz in enumerate(ISLAND_ROWS) for col, cx in ISLAND_COLUMNS.items()}
ISLAND_CELLS = set().union(*(rounded(cx - 2, cx + 2, cz - 2, cz + 2) for cx, cz in ISLANDS.values()))
START_PAD = rounded(-3, 1, -44, -40)
# Section 4: a one-cell-wide S of wooden decks north from the pad, as straight runs between corner cells.
S_BRIDGE = ((-1, -45), (-1, -48), (5, -48), (5, -54), (-7, -54), (-7, -60), (-1, -60), (-1, -62))
# Outcrops off its side, 2 cells long, each pointing at a catapult island 5 cells from the bridge's centre line, one
# cell of void beyond the outcrop's tip: (junction cell on the bridge, direction).
OUTCROPS = (((-1, -46), (-1, 0)), ((5, -51), (1, 0)), ((3, -54), (0, -1)), ((-7, -57), (-1, 0)))
OUTCROP_LENGTH = 2
BRIDGE_ISLAND_REACH = 5  # cells from the bridge's centre line to an island's centre
# Section 5: the field before the castle, the castle wall on its right (east) across a one-cell chasm, like the first
# sections' wall, with a gate in its middle, and a small pad inside the gate (a placeholder for the castle's inside).
FIELD = rounded(-7, 5, -76, -64)
FRONT_WALL_X = 7
GATE_Z = (-71, -69)
FRONT_WALL_RUNS = ((-80, GATE_Z[0] - 1), (GATE_Z[1] + 1, -60))  # cell z ranges, north to south
GATE = rect(FRONT_WALL_X, FRONT_WALL_X, GATE_Z[0], GATE_Z[1])
INSIDE_PAD = rect(FRONT_WALL_X + 1, FRONT_WALL_X + 5, GATE_Z[0], GATE_Z[1])
# Wooden balconies behind the wall, 2 m below its walk (cell z ranges; 2 cells deep against its east face).
BALCONIES = ((-79, -77), (-75, -73), (-66, -64))
BALCONY_COLUMNS = (FRONT_WALL_X + 1, FRONT_WALL_X + 2)
BALCONY_TOP = 1.0


def _s_cells():
    cells = set()
    for (x0, z0), (x1, z1) in zip(S_BRIDGE, S_BRIDGE[1:]):
        for x in range(min(x0, x1), max(x0, x1) + 1):
            for z in range(min(z0, z1), max(z0, z1) + 1):
                cells.add((x, z))
    return cells


def _outcrop_cells():
    return {(jx + dx * step, jz + dz * step) for (jx, jz), (dx, dz) in OUTCROPS for step in range(1, OUTCROP_LENGTH + 1)}


S_CELLS = _s_cells()
OUTCROP_CELLS = _outcrop_cells()
BRIDGE_ISLAND_CENTRES = [(jx + dx * BRIDGE_ISLAND_REACH, jz + dz * BRIDGE_ISLAND_REACH) for (jx, jz), (dx, dz) in OUTCROPS]
BRIDGE_ISLANDS = set().union(*(rect(cx - 1, cx + 1, cz - 1, cz + 1) for cx, cz in BRIDGE_ISLAND_CENTRES))
FLOOR = LEDGE_A | LEDGE_B | ISLAND_CELLS | START_PAD | FIELD | GATE | INSIDE_PAD
BALCONY_CELLS = {(x, z) for z0, z1 in BALCONIES for z in range(z0, z1 + 1) for x in range(BALCONY_COLUMNS[0], BALCONY_COLUMNS[1] + 1)}
assert not (BALCONY_CELLS & FLOOR) and not any((FRONT_WALL_X, z) in FLOOR for z0, z1 in FRONT_WALL_RUNS for z in range(z0, z1 + 1))
assert all((FRONT_WALL_X - 1, z) not in FLOOR for z in range(-80, -59)), "the chasm before the castle wall must be open"
assert all(max(x for x, _ in FIELD if z_ == z) == FRONT_WALL_X - 2 for z in range(-75, -64) for z_ in [z]), "the field runs to the chasm"
DECK_CELLS = S_CELLS | OUTCROP_CELLS  # walkable, but decks, not tiles
GROUND = FLOOR | POCKET | BRIDGE_ISLANDS  # every cell at the ledges' height, reachable or not
assert all((jx, jz) in S_CELLS for (jx, jz), _ in OUTCROPS)
assert not (DECK_CELLS & GROUND), DECK_CELLS & GROUND
for cell in BRIDGE_ISLANDS:
    near = [(cell[0] + dx, cell[1] + dz) for dx in (-1, 0, 1) for dz in (-1, 0, 1)]
    assert not any(n in DECK_CELLS or n in FLOOR for n in near), ("catapult island touches the bridge", cell)
CHASM_X = 3
WALL_X = 4
# Raised by events: 1 joins the ledges, 2 the second ledge and the first island, 3 the last island and the end pad.
# 2 and 3 are centred on the islands' east column: one cell off, they landed on the islands' cut corners.
BRIDGES = {1: [(x, -6) for x in (-1, 0, 1)], 2: [(x, -18) for x in (-2, -1, 0)],
           3: [(x, z) for z in (-38, -39) for x in (-2, -1, 0)], 4: [(-1, -63)],
           5: [(FRONT_WALL_X - 1, z) for z in range(GATE_Z[0], GATE_Z[1] + 1)]}
# Fixed wooden bridges between the islands: (first gap cell, last gap cell), in a straight line.
ISLAND_BRIDGES = (
    ((-5, -21), (-4, -21)), ((-1, -24), (-1, -25)), ((-8, -24), (-8, -25)), ((-5, -28), (-4, -28)),
    ((-1, -31), (-1, -32)), ((-8, -31), (-8, -32)), ((-5, -35), (-4, -35)),
)


def _island_bridge_mouths():
    """The island cells each fixed bridge lands on, one either end."""
    mouths = set()
    for (x0, z0), (x1, z1) in ISLAND_BRIDGES:
        if z0 == z1:
            mouths |= {(min(x0, x1) - 1, z0), (max(x0, x1) + 1, z0)}
            continue
        mouths |= {(x0, min(z0, z1) - 1), (x0, max(z0, z1) + 1)}
    return mouths


MOUTHS = ({(x, z) for x in (-1, 0, 1) for z in (-5, -7)} | {(x, z) for x in (-2, -1, 0) for z in (-17, -19, -37, -40)}
          | {(-1, -44), (-1, -64)} | {(x, z) for z in range(GATE_Z[0], GATE_Z[1] + 1) for x in (FRONT_WALL_X - 2, FRONT_WALL_X)}
          | _island_bridge_mouths())
assert MOUTHS <= FLOOR, MOUTHS - FLOOR
assert not any((x, z) in FLOOR for x in (CHASM_X, WALL_X) for z in range(-17, 10))

FLOOR_TOP = -1.0
WALL_TOP = 3.0
WALL_Z0, WALL_Z1 = -21, 9  # cells; it runs on past the section, north and south
CANYON_FLOOR_Y = -30.0  # far below; it and everything near it render black
FALL_TOP = -4.5  # above the lowered bridge's block (top at y = -5.99), so nobody lands on it

# Four crossbowmen 2 cells (6 m) apart: a bomb between two catches both, one on a crossbowman catches only it. With six
# (30 m end to end) one was always off screen from the firing line, past the camera's zoom-out limit.
WALL_GUARDS = (2, 0, -2, -4)
GUARD_RANGE = 18.0
FACE_WEST = "0, 0, 1, 0, 1, 0, -1, 0, 0"

level = Level(OUT, palette="canyon", weapon="catapult", floor_seed=5, deco_seed=5,
              hint="[color=#ff8888]Castle siege[/color]\n\nCrossbowmen on the castle wall shoot down at you.\nFront carrier: walk further ahead to throw further.\n"
                   "Back carrier: press shoot when the ring is on the wall walk !",
              music="rising_tension")
level.bridge_scene = (None, "res://src/world/elements/medieval/castle_bridge_platform.tscn")
# A hot, hazy afternoon. Depth comes from canyon_rock.gdshader, which darkens faces the deeper they go.
level.sky_material = """[sub_resource type="ProceduralSkyMaterial" id="PanoramaSkyMaterial_sky"]
sky_top_color = Color(0.36, 0.56, 0.82, 1)
sky_horizon_color = Color(0.92, 0.8, 0.62, 1)
sky_curve = 0.12
ground_bottom_color = Color(0.42, 0.26, 0.16, 1)
ground_horizon_color = Color(0.92, 0.8, 0.62, 1)"""
level.environment = """background_mode = 2
sky = SubResource("Sky_level")
ambient_light_source = 3
ambient_light_color = Color(0.95, 0.82, 0.66, 1)
ambient_light_sky_contribution = 0.5
ambient_light_energy = 0.6
tonemap_mode = 3
tonemap_white = 6.0
ssao_enabled = true
ssao_radius = 1.2
ssao_intensity = 1.4
fog_enabled = true
fog_light_color = Color(0.9, 0.74, 0.56, 1)
fog_density = 0.0025
fog_aerial_perspective = 0.3
fog_sky_affect = 0.0"""
level.sun_extra = {"light_color": "Color(1, 0.9, 0.74, 1)", "light_energy": "1.35"}
level.extra_ext += [
    ("Shader", None, "res://src/world/elements/medieval/castle_stone_chasm.gdshader", "castle_stone_chasm"),
    ("PackedScene", None, "res://src/world/elements/medieval/castle_tower.tscn", "tower"),
    ("PackedScene", None, "res://src/enemy/enemy_skeleton_crossbow.tscn", "crossbow"),
    ("PackedScene", None, "res://src/enemy/enemy_skeleton_catapult.tscn", "siege_crew"),
    ("Script", None, "res://src/events/groups_defeated_gate.gd", "groups_gate"),
    ("PackedScene", "uid://cif7328pvepge", "res://src/enemy/enemy_local.tscn", "skeleton"),
    ("Script", None, "res://src/events/stop_survival_event.gd", "stop_survival"),
]
level.curve = (2.5, 1.5)  # the castle front's endless horde: a skeleton every 2.5 s at first, 1.5 s after a minute
# Triggers fire only with both carriers inside, and the catapult's carriers stand up to 7.5 m apart in line: at 6 m
# deep, a stretched-out pair never fitted. Each starts 3 m past the bridge before it, so the bridge can't drop from
# under the back carrier.
level.boxes = {"fall": (400, 1, 400), "approach": (24, 3, 12), "island": (15, 3, 12), "end": (15, 3, 9)}
level.add_shell()

# ---- Enemies. ----


def crossbowman(group, name, cx, cz, top, cooldown):
    """A stationary crossbowman on the wall walk, facing the ledge. Its scene has its own MageBehavior (aimed bolts that
    fly down at the carriers), which this tunes."""
    wx, wz = world(cx, cz)
    path = f"Enemies/{group}/InstancedEnemies/{name}"
    level.node(name, f"Enemies/{group}/InstancedEnemies", instance="crossbow", props={
        "transform": tf(wx, top + 1.0, wz, FACE_WEST), "is_offensive": "false", "holds_position": "true"})
    level.node("MageBehavior", path, props={"mobility": "1", "cast_max_distance": f"{GUARD_RANGE:.1f}",
                                            "cast_cooldown": f"{cooldown:.1f}", "cast_cooldown_jitter": "1.0"})


level.enemy_group("WallGuards")
for i, cz in enumerate(WALL_GUARDS, 1):
    crossbowman("WallGuards", f"Crossbowman{i}", WALL_X, cz, WALL_TOP, 3.0)

# The catapult skeleton in the pocket, facing east with his catapult's stake on the hill: he walks round the stake to
# aim it at the ledge (src/enemy/enemy_skeleton_catapult.tscn).
# The carriers' front carrier can't stand on the hill, so from its foot only their flattest throws clear it, landing
# 0 to 2.7 m past its west face (6.2 m with the blast); steeper ones come down on top. With his stake in the pocket he
# stood 4 to 6 m past that face, out of reach. So the stake stands on the hill's crest, 1.2 m in from its west face,
# the catapult tilting up to rest on it, and he works it over a shorter gap than its default (3 to 5.5 m, not 4 to
# 7.5): he stands 1.8 to 4.3 m behind the hill.
STAKE_X = world(min(x for x, _ in MOUND), 0)[0] - CELL / 2 + 1.2  # on the hill, 1.2 m in from its west face
CREW_Z = -12
CREW_GAPS = (3.0, 5.5)  # SiegeCatapult.min_gap, max_gap
CREW_STAKE_DISTANCE = 4.25  # SiegeCatapult.stake_distance: where he starts
FACE_EAST = "0, 0, -1, 0, 1, 0, 1, 0, 0"


def catapult_skeleton(group, name, stake_x, stake_z, gaps=CREW_GAPS):
    """A catapult skeleton standing west of his stake, facing east, working it over the short gaps."""
    start = (gaps[0] + gaps[1]) / 2
    level.node(name, f"Enemies/{group}/InstancedEnemies", instance="siege_crew", props={
        "transform": tf(stake_x - start, 0, stake_z, FACE_EAST), "is_offensive": "false"})
    level.node("SiegeCatapult", f"Enemies/{group}/InstancedEnemies/{name}", props={
        "stake_distance": f"{start}", "min_gap": f"{gaps[0]}", "max_gap": f"{gaps[1]}"})


level.enemy_group("CatapultCrew")
catapult_skeleton("CatapultCrew", "CatapultSkeleton", STAKE_X, world(0, CREW_Z)[1])

# Section 3. Its groups appear only when it starts: from the second ledge they're in sight and in reach.
# Six skeletons that chase the carriers across the bridges, on the four far islands.
ISLAND_CHASERS = (("E2", -1, 1), ("W2", 1, -1), ("W2", -1, 1), ("E3", 1, 0), ("W3", -1, -1), ("W3", 1, 1))
# A catapult skeleton on every island but the first, his stake in its middle: he circles it within the island.
ISLAND_CATAPULTS = ("W1", "E2", "W2", "E3", "W3")
# Two stone towers out of the void, a cell beyond an island's edge, each with a crossbowman on top.
TOWERS = (("TowerEast", 3, -28), ("TowerWest", -12, -35))
TOWER_RADIUS = 2.0
level.enemy_group("IslandChasers", spawn_on_trigger=True)
for index, (island, dx, dz) in enumerate(ISLAND_CHASERS, 1):
    cx, cz = ISLANDS[island]
    wx, wz = world(cx + dx, cz + dz)
    level.node(f"Skeleton{index}", "Enemies/IslandChasers/InstancedEnemies", instance="skeleton", props={
        "transform": tf(wx, 0, wz, "-1, 0, 8.742278e-08, 0, 1, 0, -8.742278e-08, 0, -1"), "is_offensive": "false"})
level.enemy_group("IslandCatapults", spawn_on_trigger=True)
for index, island in enumerate(ISLAND_CATAPULTS, 1):
    wx, wz = world(*ISLANDS[island])
    catapult_skeleton("IslandCatapults", f"CatapultSkeleton{index}", wx, wz)
level.enemy_group("TowerGuards", spawn_on_trigger=True)
for index, (_name, cx, cz) in enumerate(TOWERS, 1):
    crossbowman("TowerGuards", f"Crossbowman{index}", cx, cz, WALL_TOP, 3.0)
# Section 4: a catapult skeleton alone on each 3 x 3 island off the S-bridge, his stake in its middle. He works
# gaps of 3 to 4 m (the full 82 to 45 degrees) so he stays on his island.
BRIDGE_CATAPULT_GAPS = (3.0, 4.0)
level.enemy_group("BridgeCatapults")
for index, (cx, cz) in enumerate(BRIDGE_ISLAND_CENTRES, 1):
    wx, wz = world(cx, cz)
    catapult_skeleton("BridgeCatapults", f"CatapultSkeleton{index}", wx, wz, BRIDGE_CATAPULT_GAPS)
# Section 5: six crossbowmen on the castle wall, three catapult skeletons on the balconies behind it, and the horde.
FRONT_GUARDS = (-79, -76, -73, -67, -64, -61)
level.enemy_group("FrontGuards")
for index, cz in enumerate(FRONT_GUARDS, 1):
    assert any(z0 <= cz <= z1 for z0, z1 in FRONT_WALL_RUNS), cz
    crossbowman("FrontGuards", f"Crossbowman{index}", FRONT_WALL_X, cz, WALL_TOP, 3.0)
# The balcony catapults' stakes stand 0.6 m off the wall's east face: like the hill's skeleton, he stands 3 to 4 m
# behind it, where a full-stretch throw over the wall from the chasm's edge comes down (build notes in the docs).
BALCONY_STAKE_X = world(FRONT_WALL_X, 0)[0] + CELL / 2 + 0.6
level.enemy_group("FrontCatapults")
for index, (z0, z1) in enumerate(BALCONIES, 1):
    stake_z = (world(0, z0)[1] + world(0, z1)[1]) / 2
    start = sum(BRIDGE_CATAPULT_GAPS) / 2
    name = f"CatapultSkeleton{index}"
    level.node(name, "Enemies/FrontCatapults/InstancedEnemies", instance="siege_crew", props={
        "transform": tf(BALCONY_STAKE_X + start, BALCONY_TOP + 1.0, stake_z, FACE_WEST), "is_offensive": "false"})
    level.node("SiegeCatapult", f"Enemies/FrontCatapults/InstancedEnemies/{name}", props={
        "stake_distance": f"{start}", "min_gap": f"{BRIDGE_CATAPULT_GAPS[0]}", "max_gap": f"{BRIDGE_CATAPULT_GAPS[1]}"})
# Skeletons appear on the field's far side from the wall, and its north and south ends, until the wall is cleared, at
# most 8 alive at once.
FRONT_HORDE_SPAWNS = ((-6, -70), (-5, -75), (-5, -65), (2, -75), (2, -65), (-6, -73))
level.node("FrontHorde", "Enemies", "Node3D", props={
    "script": 'ExtResource("survival_group")', "spawn_interval_curve": 'SubResource("Curve_survival")',
    "fight_duration": "60.0", "endless": "true", "max_alive": "8", "show_timer_ui": "false"})
level.node("Enemies", "Enemies/FrontHorde", "Node3D")
level.node("SpawnPoints", "Enemies/FrontHorde", "Node3D")
for index, (cx, cz) in enumerate(FRONT_HORDE_SPAWNS, 1):
    assert (cx, cz) in FIELD, (cx, cz)
    wx, wz = world(cx, cz)
    level.node(f"Node3D{index}", "Enemies/FrontHorde/SpawnPoints", "Node3D", props={"transform": tf(wx, 0, wz)})
FRONT_GROUPS = ["FrontGuards", "FrontCatapults", "FrontHorde"]
for _name, cx, cz in TOWERS:
    assert (cx, cz) not in FLOOR and all((cx + dx, cz + dz) not in FLOOR for dx in (-1, 0, 1) for dz in (-1, 0, 1))

# ---- Checkpoints. ----
SETTER, SHOOTER = (0, -2.25), (0, 2.25)  # in line, the front carrier ahead, 4.5 m apart (the catapult takes 4 to 7.5)
EVENTS_AT = "../../Level/Events/"
GROUPS_AT = "../../Enemies/"
AREAS_AT = "../../Level/Areas/"
ISLAND_GROUPS = ["IslandChasers", "IslandCatapults", "TowerGuards"]
CHECKPOINTS = [
    ("Checkpoint", -1, 7, {}),
    ("Checkpoint2", -1, -4, {
        "events_completed": [EVENTS_AT + "OpenBridge1"],
        "enemy_groups_defeated": [GROUPS_AT + "WallGuards"],
        "enemy_groups_reset": [GROUPS_AT + "CatapultCrew"],
        "areas_already_activated": [AREAS_AT + T],
        "areas_to_reactivate": [AREAS_AT + T + "2"]}),
    ("Checkpoint3", -1, -15, {
        "events_completed": [EVENTS_AT + "OpenBridge2"],
        "enemy_groups_defeated": [GROUPS_AT + "WallGuards", GROUPS_AT + "CatapultCrew"],
        "enemy_groups_reset": [GROUPS_AT + g for g in ISLAND_GROUPS],
        "areas_already_activated": [AREAS_AT + T, AREAS_AT + T + "2"],
        "areas_to_reactivate": [AREAS_AT + T + "3"]}),
    ("Checkpoint4", -1, -35, {
        "events_completed": [EVENTS_AT + "OpenBridge3"],
        "enemy_groups_defeated": [GROUPS_AT + g for g in ["WallGuards", "CatapultCrew"] + ISLAND_GROUPS],
        "enemy_groups_reset": [GROUPS_AT + "BridgeCatapults"],
        "areas_already_activated": [AREAS_AT + T, AREAS_AT + T + "2", AREAS_AT + T + "3"],
        "areas_to_reactivate": [AREAS_AT + T + "4"]}),
    # On the S's last run, facing north to bridge 4: wherever on the S the last catapult falls, the carriers go on.
    ("Checkpoint5", -1, -61, {
        "events_completed": [EVENTS_AT + "OpenBridge4"],
        "enemy_groups_defeated": [GROUPS_AT + g for g in ["WallGuards", "CatapultCrew"] + ISLAND_GROUPS + ["BridgeCatapults"]],
        "enemy_groups_reset": [GROUPS_AT + g for g in FRONT_GROUPS],
        "areas_already_activated": [AREAS_AT + T + suffix for suffix in ("", "2", "3", "4")],
        "areas_to_reactivate": [AREAS_AT + T + "5"]}),
    # In the field before the gate, facing it (east): the front carrier east of the back one.
    ("Checkpoint6", 1, -70, {
        "events_completed": [EVENTS_AT + "OpenBridge5"],
        "enemy_groups_defeated": [GROUPS_AT + g for g in ["WallGuards", "CatapultCrew"] + ISLAND_GROUPS + ["BridgeCatapults"] + FRONT_GROUPS],
        "areas_already_activated": [AREAS_AT + T + suffix for suffix in ("", "2", "3", "4", "5")]}, ((2.25, 0), (-2.25, 0))),
]
for _, cx, cz, _arrays, *_markers in CHECKPOINTS:
    assert all((cx, cz + d) in FLOOR | DECK_CELLS for d in (-1, 0, 1)), (cx, cz)
level.checkpoints(CHECKPOINTS, setter_marker=SETTER, shooter_marker=SHOOTER)

# ---- Terrain. ----
# Terraced hills fill the canyon west of the ledge: three tiers, each 4 m (two GridMap layers) above the one before,
# stepping back from the ledge's west edge. The first tier stands flush against the ledge: stepping it back a cell
# left a one-cell slot between them. The upper tiers' edges wander a cell every three rows: changing them row by row
# left one-cell slivers, which the tiles can't edge.
HILL_WEST = -14
HILL_Z0, HILL_Z1 = -15, 11  # 27 rows: nine blocks of three; they end before the islands
HILL_TIERS = 3


def hill_heights():
    """{cell: tier} for every hill cell. Tier k covers x from HILL_WEST to its edge, and is a block (three rows) shorter
    at each end than the tier below it, so the ends step down too."""
    rng = random.Random(3)
    blocks = {}
    for block in range((HILL_Z1 - HILL_Z0) // 3 + 1):
        edges = [-6]
        for _ in range(HILL_TIERS - 1):
            edges.append(edges[-1] - 2 - rng.choice((0, 0, 1)))
        blocks[block] = edges
    heights = {}
    for z in range(HILL_Z0, HILL_Z1 + 1):
        edges = blocks[(z - HILL_Z0) // 3]
        for tier in range(1, HILL_TIERS + 1):
            if not HILL_Z0 + 3 * (tier - 1) <= z <= HILL_Z1 - 3 * (tier - 1):
                break
            for x in range(HILL_WEST, edges[tier - 1] + 1):
                heights[(x, z)] = tier
    return heights


def carve_pocket(heights):
    """The hill and the pocket behind it, and lower terraces south of the pocket: the camera looks north from the
    south, and a 12 m terrace there would hide the pocket's south half."""
    heights = {cell: height for cell, height in heights.items() if cell not in POCKET}
    heights.update({cell: 1 for cell in MOUND})
    # The terraces end a row north of the pocket; a second row keeps its north wall two cells thick.
    north = min(z for _, z in POCKET) - 2
    heights.update({(x, north): 1 for x in range(HILL_WEST, max(x for x, _ in POCKET) + 1)})
    for x in range(min(x for x, _ in POCKET) - 1, max(x for x, _ in POCKET) + 1):
        for z in (max(z for _, z in POCKET) + 1, max(z for _, z in POCKET) + 2):
            heights[(x, z)] = min(heights.get((x, z), 1), 1)
    return heights


HILLS = carve_pocket(hill_heights())
HILL = set(HILLS)
assert not (HILL & GROUND), "hill over the ledge or the pocket"
for x, z in POCKET:
    assert all(n in HILL or n in POCKET for n in ((x + 1, z), (x - 1, z), (x, z + 1), (x, z - 1))), ("pocket open at", x, z)


def hill_tiles():
    """Top tiles at each cell's own tier, and cliff tiles wherever a tier's edge steps down: build_floor's tiles for the
    cells at or above each tier, raised by that tier's height."""
    cells = {}
    for tier in range(1, HILL_TIERS + 1):
        shape = {cell for cell, height in HILLS.items() if height >= tier}
        for (x, y, z), tile in level.build_floor(shape, set()).items():
            if y == -1 and HILLS[(x, z)] != tier:
                continue  # covered by a higher tier
            cells[(x, y + 2 * tier, z)] = tile
    return cells


# No water: the kill box sits a few metres down the chasm, so a carrier who steps off visibly drops before the game over.
# The floor GridMap runs under the hills too, so the ledge's west edge is flat where the first tier rises from it.
level.add_terrain(GROUND | HILL, MOUTHS, decoration_count=0, fall_z=-60, fall_y=FALL_TOP - 5.028)
# Under the navigation region, so the bake leaves the cells under the hills out of the navmesh.
level.nodes.append(level._grid_map("Hills", "Level/NavigationRegion3D", hill_tiles(),
                                   'cell_size = Vector3(2.999, 2, 2.999)\ncollision_layer = 4\ncollision_mask = 0'))
# Three tiers (12 m) under the tops: past the black depth, deeper ones would never show.
level.nodes.append(level._grid_map("CanyonCliffs", "Level", level._deep_cliffs(GROUND | HILL, 3),
                                   'cell_size = Vector3(2.999, 2, 2.999)\ncollision_layer = 0\ncollision_mask = 0'))


# Everything below the ledge tops fades to black, fully black BLACK_DEPTH down (canyon_rock.gdshader's black_depth, and
# the castle stone's per-instance fade), so the gorge reads as a bottomless hole. Scenery down there (mesas, spires)
# would only be black shapes, so there is none.
BLACK_DEPTH = 8.0  # four GridMap layers of 2 m


def add_gorge_floor():
    """A black floor far below, under everything, so nothing shows through past the deepest cliffs."""
    level.extra_sub_resources.append('[sub_resource type="StandardMaterial3D" id="Material_canyon_floor"]\n'
                                     'shading_mode = 0\nalbedo_color = Color(0, 0, 0, 1)\ndisable_fog = true')
    level.extra_sub_resources.append('[sub_resource type="PlaneMesh" id="PlaneMesh_canyon_floor"]\n'
                                     'material = SubResource("Material_canyon_floor")\nsize = Vector2(400, 400)')
    level.node("CanyonFloor", "Level", "MeshInstance3D", props={
        "transform": tf(0, CANYON_FLOOR_Y, -60), "mesh": 'SubResource("PlaneMesh_canyon_floor")', "cast_shadow": "0"})


# Castle stone fades over a shorter depth than the rock (a hand edit, kept here).
CASTLE_FADE_DEPTH = 3.5


def fade_into_the_gorge(material=None):
    """Properties turning on the castle stone's fade to black on a mesh (instance uniforms, off by default), and
    swapping in `material` (a castle_stone_chasm one) when its own uses plain castle stone."""
    props = {}
    if material:
        props["surface_material_override/0"] = f'SubResource("{material}")'
    props.update({"instance_shader_parameters/fade_depth": f"{CASTLE_FADE_DEPTH:.1f}",
                  "instance_shader_parameters/fade_top_y": f"{FLOOR_TOP:.1f}"})
    return props


add_gorge_floor()


def add_wall():
    """The castle's west wall: a stone block from the canyon floor to the wall walk, one cell thick, with merlons on both
    edges, and towers at each end. Only its west face shows, side on, so it carries no banners."""
    level.extra_sub_resources.append('[sub_resource type="ShaderMaterial" id="ShaderMaterial_wall"]\n'
                                     'render_priority = 0\nshader = ExtResource("castle_stone_chasm")')
    # castle_stone_chasm.gdshader fogs and fades the stone itself, so it goes as black as the unfogged gorge floor.
    level.extra_sub_resources.append('[sub_resource type="ShaderMaterial" id="ShaderMaterial_tower_chasm"]\n'
                                     'render_priority = 0\nshader = ExtResource("castle_stone_chasm")')
    level.extra_sub_resources.append('[sub_resource type="ShaderMaterial" id="ShaderMaterial_pier_chasm"]\n'
                                     'render_priority = 0\nshader = ExtResource("castle_stone_chasm")\n'
                                     'shader_parameter/timber_top = true\nshader_parameter/local_space = true\n'
                                     'shader_parameter/water_y = -4.2\nshader_parameter/damp_height = 1.4')
    level.extra_sub_resources.append('[sub_resource type="BoxMesh" id="BoxMesh_merlon"]\n'
                                     'material = SubResource("ShaderMaterial_wall")\nsize = Vector3(0.4, 0.75, 0.85)')
    level.node("Castle", "Level", "Node3D")
    wx, _ = world(WALL_X, 0)
    _, north = world(0, WALL_Z0)
    _, south = world(0, WALL_Z1)
    north -= CELL / 2
    south += CELL / 2
    length, height = south - north, WALL_TOP - CANYON_FLOOR_Y
    level.extra_sub_resources.append(f'[sub_resource type="BoxMesh" id="BoxMesh_wall"]\n'
                                     f'material = SubResource("ShaderMaterial_wall")\nsize = Vector3({CELL:.3f}, {height:.3f}, {length:.3f})')
    level.extra_sub_resources.append(f'[sub_resource type="BoxShape3D" id="BoxShape3D_wall"]\nsize = Vector3({CELL:.3f}, {height:.3f}, {length:.3f})')
    path = "Level/Castle/WestWall"
    middle_y = (WALL_TOP + CANYON_FLOOR_Y) / 2
    level.node("WestWall", "Level/Castle", "StaticBody3D", props={
        "transform": tf(wx, 0, (north + south) / 2), "collision_layer": "4", "collision_mask": "0",
        "metadata/footstep_surface": '&"stone"'})
    level.node("Mesh", path, "MeshInstance3D", props={"transform": tf(0, middle_y, 0), "mesh": 'SubResource("BoxMesh_wall")',
                                                     **fade_into_the_gorge()})
    level.node("CollisionShape3D", path, "CollisionShape3D", props={"transform": tf(0, middle_y, 0), "shape": 'SubResource("BoxShape3D_wall")'})
    for index in range(int(length // 1.5)):
        z = -length / 2 + 0.75 + index * 1.5
        for side, x in (("W", -CELL / 2 + 0.2), ("E", CELL / 2 - 0.2)):
            level.node(f"Merlon{side}{index}", path, "MeshInstance3D", props={
                "transform": tf(x, WALL_TOP + 0.375, z), "mesh": 'SubResource("BoxMesh_merlon")'})
    # Towers stand with their base 8 m under their top; sunk so their parapet sits a little above the wall walk.
    for name, cz in (("SouthTower", WALL_Z1), ("MidTower", -16)):
        twx, twz = world(WALL_X, cz)
        level.node(name, "Level/Castle", instance="tower", props={"transform": tf(twx, WALL_TOP - 7.6, twz)})
        level.node("Body", f"Level/Castle/{name}", props=fade_into_the_gorge("ShaderMaterial_tower_chasm"))


add_wall()


def add_front_wall():
    """The castle wall on the field's right, like the west wall: a stone block from the gorge floor to the wall walk
    either side of the gate, merlons on both edges, and a gatehouse block over the gate. Its west face shows side on,
    so it carries no banners."""
    height = WALL_TOP - CANYON_FLOOR_Y
    middle_y = (WALL_TOP + CANYON_FLOOR_Y) / 2
    wx, _ = world(FRONT_WALL_X, 0)
    for index, (z0, z1) in enumerate(FRONT_WALL_RUNS, 1):
        north = world(0, z0)[1] - CELL / 2
        south = world(0, z1)[1] + CELL / 2
        length = south - north
        name = f"FrontWall{index}"
        level.extra_sub_resources.append(f'[sub_resource type="BoxMesh" id="BoxMesh_{name}"]\nmaterial = SubResource("ShaderMaterial_wall")\n'
                                         f'size = Vector3({CELL:.3f}, {height:.3f}, {length:.3f})')
        level.extra_sub_resources.append(f'[sub_resource type="BoxShape3D" id="BoxShape3D_{name}"]\nsize = Vector3({CELL:.3f}, {height:.3f}, {length:.3f})')
        path = f"Level/Castle/{name}"
        level.node(name, "Level/Castle", "StaticBody3D", props={
            "transform": tf(wx, 0, (north + south) / 2), "collision_layer": "4", "collision_mask": "0", "metadata/footstep_surface": '&"stone"'})
        level.node("Mesh", path, "MeshInstance3D", props={"transform": tf(0, middle_y, 0), "mesh": f'SubResource("BoxMesh_{name}")', **fade_into_the_gorge()})
        level.node("CollisionShape3D", path, "CollisionShape3D", props={"transform": tf(0, middle_y, 0), "shape": f'SubResource("BoxShape3D_{name}")'})
        for m in range(int(length // 1.5)):
            z = -length / 2 + 0.75 + m * 1.5
            for side, x in (("W", -CELL / 2 + 0.2), ("E", CELL / 2 - 0.2)):
                level.node(f"Merlon{side}{m}", path, "MeshInstance3D", props={
                    "transform": tf(x, WALL_TOP + 0.375, z), "mesh": 'SubResource("BoxMesh_merlon")'})
    # The gatehouse: a stone block over the gate opening, from the wall walk up 3.5 m, no collision.
    gate_north = world(0, GATE_Z[0])[1] - CELL / 2 - 1.0
    gate_south = world(0, GATE_Z[1])[1] + CELL / 2 + 1.0
    level.extra_sub_resources.append(f'[sub_resource type="BoxMesh" id="BoxMesh_gatehouse"]\nmaterial = SubResource("ShaderMaterial_wall")\n'
                                     f'size = Vector3({CELL + 0.6:.3f}, 3.5, {gate_south - gate_north:.3f})')
    level.node("Gatehouse", "Level/Castle", "MeshInstance3D", props={
        "transform": tf(wx, WALL_TOP + 0.75, (gate_north + gate_south) / 2), "mesh": 'SubResource("BoxMesh_gatehouse")'})


add_front_wall()


def add_void_towers():
    """Stone towers standing out of the void beside the islands: a column from the gorge floor to a parapet level with
    the wall walk, castle stone fading into the dark like the wall, with merlons round the top."""
    level.extra_sub_resources.append(f'[sub_resource type="CylinderMesh" id="CylinderMesh_void_tower"]\n'
                                     f'material = SubResource("ShaderMaterial_wall")\ntop_radius = {TOWER_RADIUS}\n'
                                     f'bottom_radius = {TOWER_RADIUS}\nheight = {WALL_TOP - CANYON_FLOOR_Y}\nradial_segments = 20\nrings = 1')
    level.extra_sub_resources.append(f'[sub_resource type="CylinderShape3D" id="CylinderShape3D_void_tower"]\n'
                                     f'radius = {TOWER_RADIUS}\nheight = {WALL_TOP - CANYON_FLOOR_Y}')
    middle_y = (WALL_TOP + CANYON_FLOOR_Y) / 2
    for name, cx, cz in TOWERS:
        wx, wz = world(cx, cz)
        path = f"Level/Castle/{name}"
        level.node(name, "Level/Castle", "StaticBody3D", props={
            "transform": tf(wx, 0, wz), "collision_layer": "4", "collision_mask": "0", "metadata/footstep_surface": '&"stone"'})
        level.node("Mesh", path, "MeshInstance3D", props={
            "transform": tf(0, middle_y, 0), "mesh": 'SubResource("CylinderMesh_void_tower")', **fade_into_the_gorge()})
        level.node("CollisionShape3D", path, "CollisionShape3D", props={
            "transform": tf(0, middle_y, 0), "shape": 'SubResource("CylinderShape3D_void_tower")'})
        for index in range(10):
            angle = index * math.tau / 10
            x, z = math.sin(angle) * (TOWER_RADIUS - 0.25), math.cos(angle) * (TOWER_RADIUS - 0.25)
            c, s = math.cos(angle), math.sin(angle)
            level.node(f"Merlon{index}", path, "MeshInstance3D", props={
                "transform": tf(x, WALL_TOP + 0.375, z, f"{c:.4f}, 0, {s:.4f}, 0, 1, 0, {-s:.4f}, 0, {c:.4f}"),
                "mesh": 'SubResource("BoxMesh_merlon")'})


add_void_towers()


def add_balconies():
    """Wooden balconies on the castle wall's east face, 2 m below its walk, on posts. In the navigation region with
    `bake_walkways`, so the catapult skeletons on them walk round their stakes."""
    level.extra_sub_resources.append('[sub_resource type="CylinderMesh" id="CylinderMesh_balcony_post"]\n'
                                     'material = SubResource("Material_deck_beam")\ntop_radius = 0.18\nbottom_radius = 0.2\n'
                                     'height = 8.0\nradial_segments = 8\nrings = 1')
    level.node("Balconies", "Level/NavigationRegion3D", "Node3D", props={"metadata/bake_walkways": "true"})
    west = world(BALCONY_COLUMNS[0], 0)[0] - CELL / 2
    east = world(BALCONY_COLUMNS[1], 0)[0] + CELL / 2
    for index, (z0, z1) in enumerate(BALCONIES, 1):
        north = world(0, z0)[1] - CELL / 2
        south = world(0, z1)[1] + CELL / 2
        name = f"Balcony{index}"
        size = (east - west, 0.4, south - north)
        level.extra_sub_resources.append(f'[sub_resource type="BoxMesh" id="BoxMesh_{name}"]\nmaterial = SubResource("Material_deck_x")\n'
                                         f'size = Vector3({size[0]:.3f}, {size[1]}, {size[2]:.3f})')
        level.extra_sub_resources.append(f'[sub_resource type="BoxShape3D" id="BoxShape3D_{name}"]\nsize = Vector3({size[0]:.3f}, {size[1]}, {size[2]:.3f})')
        path = f"Level/NavigationRegion3D/Balconies/{name}"
        level.node(name, "Level/NavigationRegion3D/Balconies", "StaticBody3D", props={
            "transform": tf((west + east) / 2, BALCONY_TOP - 0.2, (north + south) / 2), "collision_layer": "4",
            "collision_mask": "0", "metadata/footstep_surface": '&"wood"'})
        level.node("Mesh", path, "MeshInstance3D", props={"mesh": f'SubResource("BoxMesh_{name}")'})
        level.node("CollisionShape3D", path, "CollisionShape3D", props={"shape": f'SubResource("BoxShape3D_{name}")'})
        for post, z in enumerate((-size[2] / 2 + 0.4, size[2] / 2 - 0.4)):
            level.node(f"Post{post + 1}", path, "MeshInstance3D", props={
                "transform": tf(size[0] / 2 - 0.4, -4.0, z), "mesh": 'SubResource("CylinderMesh_balcony_post")'})


# Decks sit this far above the floor tops: level with them, where they reach onto an island or the pad, the two
# surfaces flickered through each other.
DECK_LIFT = 0.03


def add_deck_materials():
    """Planks in world space (sky_decks/wood_planks.gdshader), laid across each bridge: one material per direction."""
    level.extra_ext.append(("Shader", None, "res://src/world/elements/sky_decks/wood_planks.gdshader", "wood_planks"))
    for axis, along_z in (("x", "true"), ("z", "false")):
        level.extra_sub_resources.append(f'[sub_resource type="ShaderMaterial" id="Material_deck_{axis}"]\n'
                                         f'render_priority = 0\nshader = ExtResource("wood_planks")\n'
                                         f'shader_parameter/wood_color = Color(0.52, 0.34, 0.19, 1)\n'
                                         f'shader_parameter/plank_width = 0.5\nshader_parameter/plank_length = 3.2\n'
                                         f'shader_parameter/planks_along_z = {along_z}')
    level.extra_sub_resources.append('[sub_resource type="StandardMaterial3D" id="Material_deck_beam"]\n'
                                     'albedo_color = Color(0.27, 0.17, 0.1, 1)\nroughness = 0.9')


def wood_deck(parent, name, first, last, overhang, width=CELL - 0.4, beams=True):
    """A wooden deck level with the floor tops over a straight run of cells, from `first` to `last`, reaching
    `overhang` metres past each end; with low beams along its edges if `beams`."""
    (x0, z0), (x1, z1) = first, last
    along_x = z0 == z1
    cells = (abs(x1 - x0) + 1) if along_x else (abs(z1 - z0) + 1)
    length = cells * CELL + 2 * overhang
    (ax, az), (bx, bz) = world(x0, z0), world(x1, z1)
    size = (length, 0.5, width) if along_x else (width, 0.5, length)
    material = "Material_deck_x" if along_x else "Material_deck_z"
    level.extra_sub_resources.append(f'[sub_resource type="BoxMesh" id="BoxMesh_{name}"]\nmaterial = SubResource("{material}")\n'
                                     f'size = Vector3({size[0]:.3f}, {size[1]}, {size[2]:.3f})')
    level.extra_sub_resources.append(f'[sub_resource type="BoxShape3D" id="BoxShape3D_{name}"]\n'
                                     f'size = Vector3({size[0]:.3f}, {size[1]}, {size[2]:.3f})')
    path = f"{parent}/{name}"
    level.node(name, parent, "StaticBody3D", props={
        "transform": tf((ax + bx) / 2, FLOOR_TOP - 0.25 + DECK_LIFT, (az + bz) / 2), "collision_layer": "4", "collision_mask": "0",
        "metadata/footstep_surface": '&"wood"'})
    level.node("Mesh", path, "MeshInstance3D", props={"mesh": f'SubResource("BoxMesh_{name}")'})
    level.node("CollisionShape3D", path, "CollisionShape3D", props={"shape": f'SubResource("BoxShape3D_{name}")'})
    if not beams:
        return
    beam = (length, 0.18, 0.18) if along_x else (0.18, 0.18, length)
    level.extra_sub_resources.append(f'[sub_resource type="BoxMesh" id="BoxMesh_{name}_beam"]\nmaterial = SubResource("Material_deck_beam")\n'
                                     f'size = Vector3({beam[0]:.3f}, {beam[1]}, {beam[2]:.3f})')
    for side in (-1, 1):
        offset = (0, 0.3, side * (width / 2 - 0.09)) if along_x else (side * (width / 2 - 0.09), 0.3, 0)
        level.node(f"Beam{'AB'[side > 0]}", path, "MeshInstance3D", props={
            "transform": tf(*offset), "mesh": f'SubResource("BoxMesh_{name}_beam")'})


def add_island_bridges():
    """Fixed wooden decks between the islands, level with their tops. They sit under the navigation region with
    `bake_walkways`, so bake_nav.gd bakes them and the skeletons chase across them."""
    level.node("IslandBridges", "Level/NavigationRegion3D", "Node3D", props={"metadata/bake_walkways": "true"})
    for index, (first, last) in enumerate(ISLAND_BRIDGES, 1):
        wood_deck("Level/NavigationRegion3D/IslandBridges", f"Bridge{index}", first, last, 0.5)  # half a metre onto each island


def add_s_bridge():
    """Section 4's S: a deck per straight run, full cell width so runs meet flush at the corners, without edge beams
    (they'd cross the way at every corner and outcrop), and the outcrops off its side. Nothing chases here, so they
    stay out of the navmesh."""
    level.node("SBridge", "Level", "Node3D")
    for index, (first, last) in enumerate(zip(S_BRIDGE, S_BRIDGE[1:]), 1):
        overhang = 0.5 if index == 1 else 0.0  # onto the pad
        if index > 1:
            # Each corner cell belongs to the run before: two decks over it flickered through each other.
            step = ((last[0] > first[0]) - (last[0] < first[0]), (last[1] > first[1]) - (last[1] < first[1]))
            first = (first[0] + step[0], first[1] + step[1])
        wood_deck("Level/SBridge", f"Run{index}", first, last, overhang, width=CELL, beams=False)
    for index, ((jx, jz), (dx, dz)) in enumerate(OUTCROPS, 1):
        first = (jx + dx, jz + dz)
        last = (jx + dx * OUTCROP_LENGTH, jz + dz * OUTCROP_LENGTH)
        wood_deck("Level/SBridge", f"Outcrop{index}", first, last, 0.0, width=CELL, beams=False)


add_deck_materials()
add_island_bridges()
add_s_bridge()
add_balconies()

# ---- Rocks. ----
# Sandstone rocks saved by build_canyon_tiles.gd, placed freely: (name, its bounds' lowest y, its width). Rock_3 are
# boulders centred on their origin; Rock_5 stands on its.
ROCK_MESHES = {
    "Rock_3_A": (-0.465, 0.96), "Rock_3_C": (-0.519, 0.86), "Rock_3_F": (-0.588, 1.19), "Rock_3_H": (-0.976, 1.95),
    "Rock_5_E": (-0.025, 2.03),
}
BOULDERS = ("Rock_3_A", "Rock_3_C", "Rock_3_F", "Rock_3_H")
# Boulders at the foot of the first hill tier, half sunk into its cliff, with collision: cell rows along the ledge.
CLIFF_FOOT_ROWS = (8, 4, 0, -16)


def yawed(x, y, z, scale, yaw_deg):
    c, s = math.cos(math.radians(yaw_deg)) * scale, math.sin(math.radians(yaw_deg)) * scale
    return tf(x, y, z, f"{c:.4f}, 0, {s:.4f}, 0, {scale:.4f}, 0, {-s:.4f}, 0, {c:.4f}")


def add_rock(parent, name, rock, x, ground_y, z, scale, yaw, sink=0.0):
    """Stands `rock` on the ground at `ground_y`, sunk by `sink` of its height."""
    low, _width = ROCK_MESHES[rock]
    ext = "rock_" + rock.lower()
    if not any(entry[3] == ext for entry in level.extra_ext):
        level.extra_ext.append(("ArrayMesh", None, f"res://src/world/elements/canyon/rocks/{rock.lower()}.res", ext))
    y = ground_y - low * scale * (1.0 - sink)
    level.node(name, parent, "MeshInstance3D", props={"transform": yawed(x, y, z, scale, yaw), "mesh": f'ExtResource("{ext}")'})
    return y


def add_rocks():
    rng = random.Random(11)
    level.node("Rocks", "Level", "Node3D")
    # Boulders on the hill tiers: nobody can reach them, so no collision.
    tops = sorted(HILL - MOUND)  # the hill on the ledge holds the catapult's stake
    for index, cell in enumerate(rng.sample(tops, 26), 1):
        wx, wz = world(*cell)
        rock = rng.choice(BOULDERS + ("Rock_5_E",))
        add_rock("Level/Rocks", f"HillRock{index}", rock, wx + rng.uniform(-0.8, 0.8), 4 * HILLS[cell] + FLOOR_TOP,
                 wz + rng.uniform(-0.8, 0.8), rng.uniform(1.4, 2.8), rng.uniform(0, 360), sink=0.35)
    # The first tier's cliff face, along the ledge's west edge.
    face_x = world(-6, 0)[0] + CELL / 2
    for index, cz in enumerate(CLIFF_FOOT_ROWS, 1):
        assert (-5, cz) in FLOOR and HILLS.get((-6, cz)) is not None, ("no cliff foot at row", cz)
        _, wz = world(0, cz)
        rock = rng.choice(("Rock_3_C", "Rock_3_H", "Rock_3_F"))
        scale = rng.uniform(1.4, 2.0)
        _low, width = ROCK_MESHES[rock]
        x = face_x + width * scale * 0.15
        name = f"CliffFootRock{index}"
        y = add_rock("Level/Rocks", name, rock, x, FLOOR_TOP, wz + rng.uniform(-0.6, 0.6), scale, rng.uniform(0, 360), sink=0.2)
        level.extra_sub_resources.append(f'[sub_resource type="SphereShape3D" id="SphereShape3D_{name}"]\nradius = {width * scale * 0.42:.3f}')
        level.node("Body", f"Level/Rocks/{name}", "StaticBody3D", props={
            "transform": tf(0, 0, 0, f"{1 / scale:.4f}, 0, 0, 0, {1 / scale:.4f}, 0, 0, 0, {1 / scale:.4f}"),
            "collision_layer": "4", "collision_mask": "0", "metadata/footstep_surface": '&"stone"'})
        level.node("CollisionShape3D", f"Level/Rocks/{name}/Body", "CollisionShape3D", props={"shape": f'SubResource("SphereShape3D_{name}")'})


add_rocks()

# ---- Sandstorm: sand streaks and dust blowing east, off the hills toward the castle, with gusts. Visual only. ----
level.extra_ext.append(("PackedScene", None, "res://src/world/elements/canyon/sandstorm.tscn", "sandstorm"))
level.node("Sandstorm", "Level", instance="sandstorm", paths=["world_environment"],
           props={"world_environment": 'NodePath("../../WorldEnvironment")'})

# ---- Events. ----
level.set_bridges(BRIDGES)
for number in (1, 2, 3, 4, 5):
    level.bridge_event(f"OpenBridge{number}", number)


def offensive(name, group, next_event=None):
    props = {"script": 'ExtResource("change_behavior")', "enemy_group": f'NodePath("../../../Enemies/{group}")'}
    paths = ["enemy_group"]
    if next_event:
        props["next_event"] = f'NodePath("../{next_event}")'
        paths.append("next_event")
    level.node(name, "Level/Events", "Node", paths=paths, props=props)


# (1) The wall.
offensive("MakeWallGuardsOffensive", "WallGuards")
# (2) The catapult: stepping onto the second ledge lowers bridge 1 behind the carriers and wakes him.
level.bridge_event("CloseBridge1", 1, True, "MakeCatapultCrewOffensive")
offensive("MakeCatapultCrewOffensive", "CatapultCrew")
# (3) The islands: stepping onto the first lowers bridge 2 and brings everything in.
level.bridge_event("CloseBridge2", 2, True, "StartIslandChasers")
offensive("StartIslandChasers", "IslandChasers", "StartIslandCatapults")
offensive("StartIslandCatapults", "IslandCatapults", "StartTowerGuards")
offensive("StartTowerGuards", "TowerGuards")
level.node("IslandsCleared", "Level/Events", "Node", paths=["next_event", "groups", "checkpoint"], props={
    "script": 'ExtResource("groups_gate")', "next_event": 'NodePath("../OpenBridge3")',
    "groups": node_paths([f"../../../Enemies/{g}" for g in ISLAND_GROUPS]),
    "checkpoint": 'NodePath("../../../CheckpointManager/Checkpoint4")'})
# (4) The S-bridge: stepping onto the pad lowers bridge 3 and wakes the four catapults.
level.bridge_event("CloseBridge3", 3, True, "StartBridgeCatapults")
offensive("StartBridgeCatapults", "BridgeCatapults")
# (5) The castle front: stepping into the field lowers bridge 4 and starts the wall, the balconies and the horde.
level.bridge_event("CloseBridge4", 4, True, "StartFrontGuards")
offensive("StartFrontGuards", "FrontGuards", "StartFrontCatapults")
offensive("StartFrontCatapults", "FrontCatapults", "StartFrontHorde")
offensive("StartFrontHorde", "FrontHorde")
level.node("StopFrontHorde", "Level/Events", "Node", paths=["survival_group"], props={
    "script": 'ExtResource("stop_survival")', "survival_group": 'NodePath("../../../Enemies/FrontHorde")'})
# The wall's crossbowmen and catapults dead: the horde stops, Checkpoint6, the gate's stone bridge rises. The
# skeletons left in the field still chase.
level.node("FrontCleared", "Level/Events", "Node", paths=["next_event", "groups", "checkpoint", "also_trigger"], props={
    "script": 'ExtResource("groups_gate")', "next_event": 'NodePath("../OpenBridge5")',
    "groups": node_paths(["../../../Enemies/FrontGuards", "../../../Enemies/FrontCatapults"]),
    "checkpoint": 'NodePath("../../../CheckpointManager/Checkpoint6")',
    "also_trigger": node_paths(["../StopFrontHorde", "../UnfocusCamera"])})
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})
# The crossbowmen and the hidden catapult can't be walked to, so their fights are framed. On the islands everything
# but the two tower crossbowmen can be walked to, so that fight keeps the normal zoom.
level.add_focus({"Wall": (-5, WALL_X + 1, 3, -6), "Pocket": (min(x for x, _ in POCKET), 2, -8, -16),
                 "Front": (-7, FRONT_WALL_X + 3, -62, -80)})
level.add_end_area(FRONT_WALL_X + 3, sum(GATE_Z) / 2)
level.add_bridge_nodes()
for platforms in level.platforms.values():  # their stone piers hang into the gorge
    for platform in platforms:
        level.node("Pier", f"Level/Bridges/{platform}/AnimatableBody3D", props=fade_into_the_gorge("ShaderMaterial_pier_chasm"))
level.add_triggers(((T, -1.5, 3.5, "approach"), (T + "2", -1.5, -9.5, "approach"), (T + "3", -1, -21.5, "island"),
                    (T + "4", -1, -42.5, "island"), (T + "5", -1, -66.5, "approach")))
wx, wz = world(-1, 7)
# Turned to throw towards -z, with its back handles (local z = -2.7) over the shooter's marker.
level.add_weapon("Catapult", tf(wx, 1.8726845, wz + SHOOTER[1] - 2.7, "-1, 0, 0, 0, 1, 0, 0, 0, -1"))
level.add_audio_and_hint()

# ---- Signals. ----
CORNERS = ("SW", "SE", "NW", "NE")
level.connect("all_players_inside", AREAS + T, EVENTS + "MakeWallGuardsOffensive")
for corner in CORNERS:
    level.connect("all_players_inside", AREAS + T, EVENTS + f"FocusWall{corner}")
for target in ("CheckpointManager/Checkpoint2", EVENTS + "OpenBridge1", EVENTS + "UnfocusCamera"):
    level.connect("enemies_defeated", GROUPS + "WallGuards", target, "_trigger_checkpoint" if "Checkpoint" in target else "trigger")
level.connect("all_players_inside", AREAS + T + "2", EVENTS + "CloseBridge1")
for corner in CORNERS:
    level.connect("all_players_inside", AREAS + T + "2", EVENTS + f"FocusPocket{corner}")
for target in ("CheckpointManager/Checkpoint3", EVENTS + "OpenBridge2", EVENTS + "UnfocusCamera"):
    level.connect("enemies_defeated", GROUPS + "CatapultCrew", target, "_trigger_checkpoint" if "Checkpoint" in target else "trigger")
level.connect("all_players_inside", AREAS + T + "3", EVENTS + "CloseBridge2")
for group in ISLAND_GROUPS:
    level.connect("enemies_defeated", GROUPS + group, EVENTS + "IslandsCleared")
level.connect("all_players_inside", AREAS + T + "4", EVENTS + "CloseBridge3")
for target in ("CheckpointManager/Checkpoint5", EVENTS + "OpenBridge4"):
    level.connect("enemies_defeated", GROUPS + "BridgeCatapults", target, "_trigger_checkpoint" if "Checkpoint" in target else "trigger")
level.connect("all_players_inside", AREAS + T + "5", EVENTS + "CloseBridge4")
for corner in CORNERS:
    level.connect("all_players_inside", AREAS + T + "5", EVENTS + f"FocusFront{corner}")
for group in ("FrontGuards", "FrontCatapults"):
    level.connect("enemies_defeated", GROUPS + group, EVENTS + "FrontCleared")
level.connect("all_players_inside", "Level/EndLevelArea", EVENTS + "LevelSucceeded")

level.write(sys.argv[1:])
