#!/usr/bin/env python3
"""Prototype of a level in the sky: world_local_sky.tscn. Floating islands over layered clouds, no water.

Run from the project root; see docs/level-creation-for-agents.md.
"""
import sys

from levelgen import (AREAS, EVENTS, GROUPS, TRIGGER as T, Level, checkpoint, rect, single_bridge, tf)


def rounded(x0, x1, z0, z1):
    """A rectangle with its corners cut, so islands don't read as boxes."""
    corners = {(x0, z0), (x0, z1), (x1, z0), (x1, z1)}
    return rect(x0, x1, z0, z1) - corners


# ---- Layout, in grid cells. Forward is -z. ----
START = rounded(-3, 3, -3, 3) | rect(-1, 1, -5, -4)
RING = rounded(-5, 5, -18, -8) - rect(-1, 1, -14, -12)  # the pit looks straight down through the clouds
CAUSEWAY = rect(-2, 2, -30, -21)
PERCHES = rounded(-8, -5, -28, -24) | rounded(5, 8, -28, -24)
END_PAD = rounded(-3, 3, -38, -33)
FLOOR = START | RING | CAUSEWAY | PERCHES | END_PAD

BRIDGES = {1: single_bridge(-6, -7), 2: single_bridge(-19, -20), 3: single_bridge(-31, -32)}
MOUTHS = {(0, -5), (0, -8), (0, -18), (0, -21), (0, -30), (0, -33)}
assert MOUTHS <= FLOOR

# Decorative only: (name, world position, shape in cells around the island's own origin, trees).
DISTANT_ISLANDS = (
    ("IslandA", (-54, -28, 14), rounded(-3, 3, -2, 2), 5),
    ("IslandB", (62, -32, -14), rounded(-4, 4, -3, 3), 9),
    ("IslandC", (-68, -34, -42), rounded(-3, 4, -4, 3), 8),
    ("IslandD", (58, -26, -60), rounded(-2, 2, -2, 2), 3),
    ("IslandE", (-58, -30, -86), rounded(-4, 3, -3, 3), 8),
    ("IslandF", (70, -34, -102), rounded(-5, 5, -4, 4), 14),
    ("IslandG", (-72, -34, -130), rounded(-4, 4, -3, 3), 9),
)

level = Level("src/world/levels/world_local_sky.tscn", palette=1, weapon="bazooka", floor_seed=9, deco_seed=17, music="overworld_orchestra")
level.curve = (3.0, 3.0)  # no survival group here, but the scene format expects the curve
level.boxes = {"fall": (500, 1, 500), "firing": (21, 3, 10), "ring": (33, 3, 9), "causeway": (15, 3, 6), "end": (21, 3, 9)}
level.add_shell()

# ---- Enemies. ----
level.enemy_group("EnemyGroup")  # idle packs across the open air
pack = 0
for cx, cz in ((-3, -9), (0, -9), (3, -9)):  # 1 m apart, well inside a rocket's 3.5 m blast
    pack += 1
    level.melee("EnemyGroup", f"EnemyLocal{pack}a", cx, cz)
    level.melee("EnemyGroup", f"EnemyLocal{pack}b", cx - 0.35, cz - 0.35)
    level.melee("EnemyGroup", f"EnemyLocal{pack}c", cx + 0.35, cz - 0.35)
level.enemy_group("EnemyGroup2")  # they walk around the pit, rockets fly across it
for i, (cx, cz) in enumerate(((-3, -16), (-4, -17), (-2, -17), (-3, -15), (3, -16), (4, -17), (2, -17), (3, -15), (0, -16), (-4, -13), (4, -13)), 1):
    level.melee("EnemyGroup2", f"EnemyLocal{i}", cx, cz)
level.enemy_group("EnemyGroup3")  # mages out of reach on their own islands
for i, (cx, cz) in enumerate(((-7, -25), (-6, -27), (6, -27), (7, -25)), 1):
    level.mage("EnemyGroup3", f"EnemyMage{i}", cx, cz, cast_max=24.0, cooldown=4.0)  # they sit about 20 m from the path
for i, (cx, cz) in enumerate(((-1, -28), (1, -28), (0, -29)), 1):
    level.melee("EnemyGroup3", f"EnemyLocal{i}", cx, cz)

level.checkpoints([
    checkpoint("Checkpoint", 0, 0, react="FiringLineTrigger"),
    checkpoint("Checkpoint2", 0, -4, "OpenBridge1", "EnemyGroup2", "EnemyGroup", T, "FiringLineTrigger"),
    checkpoint("Checkpoint3", 0, -16, "OpenBridge2", "EnemyGroup3", "EnemyGroup2", T + "2", T),
    checkpoint("Checkpoint4", 0, -29, "OpenBridge3", None, "EnemyGroup3", None, T + "2"),
], setter_marker=(0, -0.5082588), shooter_marker=(0, 2.1002235))

# ---- Terrain and sky. fall_y puts the kill plane about 11 m under the islands. ----
level.add_terrain(FLOOR, MOUTHS, decoration_count=60, fall_z=-60, fall_y=-17)
level.add_sky(FLOOR)
level.node("DistantIslands", "Level", "Node")
for name, position, shape, trees in DISTANT_ISLANDS:
    level.add_distant_island(name, position, shape, trees)

# ---- Events. ----
level.set_bridges(BRIDGES)
level.bridge_event("OpenBridge1", 1)
level.bridge_event("CloseBridge1", 1, True, "MakeEnemiesGroup2Offensive")
level.offensive_event("MakeEnemiesGroup2Offensive", "EnemyGroup2")
level.bridge_event("OpenBridge2", 2)
level.bridge_event("CloseBridge2", 2, True, "MakeEnemiesGroup3Offensive")
level.offensive_event("MakeEnemiesGroup3Offensive", "EnemyGroup3")
level.bridge_event("OpenBridge3", 3)
level.node("LevelSucceeded", "Level/Events", "Node", props={"script": 'ExtResource("finished")'})
# Framing only where enemies can't be walked to: the packs across the first gap, and the mages on their islands.
level.add_focus({"Range": (-5, 5, -5, -12), "Mages": (-8, 8, -21, -30)})
level.add_end_area(0, -36)
level.add_bridge_nodes()
level.add_triggers((("FiringLineTrigger", 0, -4, "firing"), (T, 0, -10, "ring"), (T + "2", 0, -23, "causeway")))
level.add_weapon("Bazooka", tf(1.5, 0.593, 1.5))
level.add_audio_and_hint()

# ---- Signals. ----
for group, number, cp_name in (("EnemyGroup", 1, "Checkpoint2"), ("EnemyGroup2", 2, "Checkpoint3"), ("EnemyGroup3", 3, "Checkpoint4")):
    level.connect("enemies_defeated", GROUPS + group, "CheckpointManager/" + cp_name, "_trigger_checkpoint")
    level.connect("enemies_defeated", GROUPS + group, EVENTS + f"OpenBridge{number}")
    level.connect("enemies_defeated", GROUPS + group, EVENTS + "UnfocusCamera")
level.connect("all_players_inside", "Level/EndLevelArea", EVENTS + "LevelSucceeded")
level.connect("all_players_inside", AREAS + T, EVENTS + "CloseBridge1")
level.connect("all_players_inside", AREAS + T, EVENTS + "UnfocusCamera")
level.connect("all_players_inside", AREAS + T + "2", EVENTS + "CloseBridge2")
for corner in ("SW", "SE", "NW", "NE"):
    level.connect("all_players_inside", AREAS + "FiringLineTrigger", EVENTS + f"FocusRange{corner}")
    level.connect("all_players_inside", AREAS + T + "2", EVENTS + f"FocusMages{corner}")

level.write(sys.argv[1:])
