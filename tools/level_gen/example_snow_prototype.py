#!/usr/bin/env python3
"""Prototype of a snow level: world_local_snow.tscn. Snowy shores over an icy sea, slippery ice, and blue orcs.

Ice cells use the "Ice_" tiles, which IceFloor makes slippery for the carriers (src/world/elements/snow/ice_floor.gd).
Run from the project root; see docs/level-creation-for-agents.md.
"""
import sys

from levelgen import EVENTS, GROUPS, AREAS, TRIGGER as T, Level, checkpoint, double_bridge, rect, tf, world


def rounded(x0, x1, z0, z1):
    """A rectangle with its corners cut."""
    return rect(x0, x1, z0, z1) - {(x0, z0), (x0, z1), (x1, z0), (x1, z1)}


# ---- Layout, in grid cells. Forward is -z. ----
SHORE = rounded(-5, 5, -6, 3)
LAKE = rounded(-7, 7, -22, -9)
RIVER = rounded(-6, 6, -38, -25)
SUMMIT = rounded(-4, 4, -47, -41)
FLOOR = SHORE | LAKE | RIVER | SUMMIT

BRIDGES = {1: double_bridge(-7, -8), 2: double_bridge(-23, -24), 3: double_bridge(-39, -40)}
MOUTHS = {(x, z) for x in (-1, 0, 1) for z in (-6, -9, -22, -25, -38, -41)}
assert MOUTHS <= FLOOR

# The lake's ice runs out to its east cliff: slide too far and you are in the sea.
LAKE_ICE = (rect(-3, 7, -18, -13) | rect(-1, 4, -19, -12)) & LAKE
# The frozen river crosses the whole section, edge to edge, so it can't be walked around.
RIVER_ICE = rect(-6, 6, -33, -30) & RIVER
ICE = LAKE_ICE | RIVER_ICE

PROPS = {
    (-4, 1): ("PineA", 0), (4, 1): ("PineB", 10), (-4, -4): ("Boulder", 0), (3, -4): ("BareTree", 0),
    (-5, -11): ("PineB", 0), (-6, -16): ("Boulder", 16), (-5, -20): ("PineA", 10), (5, -20): ("BareTree", 0),
    (-4, -35): ("PineA", 0), (4, -35): ("PineB", 16), (-2, -27): ("Boulder", 10), (3, -27): ("BoulderB", 0),
    (-3, -45): ("PineB", 0), (3, -45): ("PineA", 0),
}
ISLES = (
    ("IsleA", (-42, -1.6, -10), rounded(-2, 2, -2, 2), {(0, 0): ("IslePine", 0), (-1, 1): ("IsleRock", 10)}),
    ("IsleB", (48, -1.8, -40), rounded(-3, 2, -2, 3), {(0, 0): ("IslePineB", 0), (1, 1): ("IslePine", 16), (-2, 0): ("IsleBareTree", 0)}),
    ("IsleC", (-50, -1.6, -78), rounded(-2, 3, -3, 2), {(1, 0): ("IslePine", 0), (-1, -1): ("IslePineB", 10)}),
    ("IsleD", (44, -1.6, 10), rounded(-2, 2, -2, 2), {(0, 0): ("IsleBareTree", 0), (1, -1): ("IsleRock", 0)}),
    ("IsleE", (52, -1.8, -112), rounded(-3, 3, -2, 2), {(0, 0): ("IslePine", 10), (-2, 0): ("IslePineB", 0), (2, 1): ("IsleRock", 16)}),
)

level = Level("src/world/levels/world_local_snow.tscn", palette="snow", weapon="sword", floor_seed=7, deco_seed=7,
              hint="[color=#ff8888]Sword usage[/color]\n\nUse dash to swing and attack with the sword !\nIce is slippery: you keep sliding after you stop.",
              music="overworld_orchestra")
level.use_snow()
level.curve = (3.0, 3.0)  # no survival group here, but the scene format expects the curve
level.boxes = {"fall": (400, 1, 400), "lake": (45, 3, 9), "river": (39, 3, 9), "end": (21, 3, 9)}
level.add_shell()

# ---- Enemies: blue orcs. ----
SHORE_ORCS = ((-2, 0), (2, 0), (-3, -3), (0, -3), (3, -2))
LAKE_ORCS = ((-6, -19), (-4, -21), (-1, -21), (1, -21), (4, -21), (6, -19), (-6, -13), (6, -11), (-4, -10), (4, -10))
RIVER_ORCS = ((-3, -36), (0, -36), (3, -36), (-5, -34), (5, -34), (-1, -37), (1, -37))
level.enemy_group("EnemyGroup")  # idle targets on plain snow, to learn the swing
for i, (cx, cz) in enumerate(SHORE_ORCS, 1):
    level.melee("EnemyGroup", f"EnemyOrc{i}", cx, cz)
level.enemy_group("EnemyGroup2")  # they come around and across the frozen lake
for i, (cx, cz) in enumerate(LAKE_ORCS, 1):
    level.melee("EnemyGroup2", f"EnemyOrc{i}", cx, cz)
level.enemy_group("EnemyGroup3")  # they wait beyond the frozen river
for i, (cx, cz) in enumerate(RIVER_ORCS, 1):
    level.melee("EnemyGroup3", f"EnemyOrc{i}", cx, cz)
for cx, cz in SHORE_ORCS + LAKE_ORCS + RIVER_ORCS:
    assert (cx, cz) in FLOOR and (cx, cz) not in PROPS, (cx, cz)

level.checkpoints([
    checkpoint("Checkpoint", 0, 2),
    checkpoint("Checkpoint2", 0, -5, "OpenBridge1", "EnemyGroup2", "EnemyGroup", T),
    checkpoint("Checkpoint3", 0, -21, "OpenBridge2", "EnemyGroup3", "EnemyGroup2", T + "2", T),
    checkpoint("Checkpoint4", 0, -37, "OpenBridge3", None, "EnemyGroup3", None, T + "2"),
], setter_marker=(0, -0.5082588), shooter_marker=(0, 2.1002235))

# ---- Terrain and scenery. ----
level.add_snow_terrain(FLOOR, MOUTHS, ICE, PROPS, fall_z=-40, water_z=-40)
level.add_snow_isles(ISLES)

# ---- Events. No camera framing: every orc can be walked to. ----
level.set_bridges(BRIDGES)
level.bridge_event("OpenBridge1", 1)
level.bridge_event("CloseBridge1", 1, True, "MakeEnemiesGroup2Offensive")
level.offensive_event("MakeEnemiesGroup2Offensive", "EnemyGroup2")
level.bridge_event("OpenBridge2", 2)
level.bridge_event("CloseBridge2", 2, True, "MakeEnemiesGroup3Offensive")
level.offensive_event("MakeEnemiesGroup3Offensive", "EnemyGroup3")
level.bridge_event("OpenBridge3", 3)
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})
level.add_end_area(0, -44)
level.add_bridge_nodes()
level.add_triggers(((T, 0, -11, "lake"), (T + "2", 0, -27, "river")))
wx, wz = world(0, 2)
level.add_weapon("Sword", tf(wx, 0.593, wz))
level.add_audio_and_hint()

# ---- Signals. ----
for group, number, cp_name in (("EnemyGroup", 1, "Checkpoint2"), ("EnemyGroup2", 2, "Checkpoint3"), ("EnemyGroup3", 3, "Checkpoint4")):
    level.connect("enemies_defeated", GROUPS + group, "CheckpointManager/" + cp_name, "_trigger_checkpoint")
    level.connect("enemies_defeated", GROUPS + group, EVENTS + f"OpenBridge{number}")
level.connect("all_players_inside", "Level/EndLevelArea", EVENTS + "LevelSucceeded")
level.connect("all_players_inside", AREAS + T, EVENTS + "CloseBridge1")
level.connect("all_players_inside", AREAS + T + "2", EVENTS + "CloseBridge2")

level.write(sys.argv[1:])
